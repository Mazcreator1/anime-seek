// lib/screens/TraceSearchPage.dart
import 'dart:io';
import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:video_player/video_player.dart';
import 'package:anime_finder/models/scene_history_model.dart';
import 'package:anime_finder/models/favorites_model.dart';

class TraceSearchPage extends StatefulWidget {
  const TraceSearchPage({Key? key}) : super(key: key);

  @override
  State<TraceSearchPage> createState() => _TraceSearchPageState();
}

class _TraceSearchPageState extends State<TraceSearchPage> {
  final ImagePicker _picker = ImagePicker();
  late final Dio _dio;

  final TextEditingController _urlController = TextEditingController();
  bool _isLoading = false, _isPicking = false;
  List<Map<String, dynamic>> _results = [];
  String? _currentTier;
  int? _remainingSearches;
  int _searchVersion = 0;
  Completer<void>? _authReady;

  String? _jwt, _apiKey;
  CancelToken? _inflight;
  Timer? _deb;
  int _qvCounter = 0;
  int _qvApplied = 0;
  final Set<int> _pendingQuota = <int>{};

  @override
  void initState() {
    super.initState();

    _dio = Dio(
      BaseOptions(
        baseUrl: 'https://api.anime-seek.com',
        connectTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 60),      // ✅ IMPORTANT for uploads
        receiveTimeout: const Duration(minutes: 3),    // ✅ don’t wait forever
      ),
    );


    _installInterceptors();


    () async {
      await _warmTokens();


      if ((_apiKey == null || _apiKey!.isEmpty)) {
        await _ensureApiKeyFromMe();
      }
    }();
  }


  bool get _canSearch => (_apiKey?.isNotEmpty ?? false) || (_jwt?.isNotEmpty ?? false);
  
  
  void _installInterceptors() {
    // --- Main app interceptor (loads JWT/API key on-demand) ---
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          options.headers['Cache-Control'] = 'no-cache';
          options.headers['Pragma'] = 'no-cache';

          String? jwt;
          final authHdr = options.headers['Authorization']?.toString();
          if (authHdr != null && authHdr.startsWith('Bearer ')) {
            jwt = authHdr.substring(7);
          }
          String? apiKey = (options.headers['x-api-key'] ?? options.headers['X-API-Key'])?.toString();

          if (jwt == null || jwt.isEmpty || apiKey == null || apiKey.isEmpty) {
            try {
              final prefs = await SharedPreferences.getInstance();
              jwt ??= prefs.getString('access_token');
              apiKey ??= prefs.getString('api_key');
            } catch (e, st) {
              debugPrint('AniList enrichment failed: $e\n$st');
            }
          }

          if (jwt != null && jwt.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $jwt';
          }

          if (apiKey != null && apiKey.isNotEmpty) {
            options.headers['x-api-key'] = apiKey;
            options.headers['X-API-Key'] = apiKey;
            options.queryParameters = {
              'key': apiKey,
              ...options.queryParameters,
            };
          }

          final qv = ++_qvCounter;
          options.extra['qv'] = qv;
          options.headers['X-QV'] = '$qv';

          final isSearch = options.path.endsWith('/search');
          if (isSearch && _remainingSearches != null) {
            _pendingQuota.add(qv);
            if (mounted) {
              setState(() {
                _remainingSearches = (_remainingSearches! - 1).clamp(0, 1 << 30);
              });
            }
          }

          return handler.next(options);
        },
        onResponse: (resp, handler) {
          final isSearch = resp.requestOptions.path.endsWith('/search');
          final ok = resp.statusCode == 200;

          _applyQuotaFromResponse(resp, consumed: isSearch && ok);

          final qv = (resp.requestOptions.extra['qv'] as int?) ?? 0;
          _pendingQuota.remove(qv);

          handler.next(resp);
        },
        onError: (e, handler) {
  final resp = e.response;
  if (resp != null) {
    final isSearch = resp.requestOptions.path.endsWith('/search');
    final ok = resp.statusCode == 200;
    _applyQuotaFromResponse(resp, consumed: isSearch && ok);
    final qv = (resp.requestOptions.extra['qv'] as int?) ?? 0;
    _pendingQuota.remove(qv);
  }
  handler.next(e);
        },

      ),
    );

    // --- Debug logger LAST (so it sees injected headers/qp) ---
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) {
          final qp = Map.of(o.queryParameters);
          final hdrs = Map.of(o.headers);

          final rawKey = (hdrs['x-api-key'] ?? hdrs['X-API-Key'] ?? qp['key'] ?? '')?.toString() ?? '';
          final masked = rawKey.isEmpty ? '(none)' : '${rawKey.substring(0, 4)}…${rawKey.substring(rawKey.length - 4)}';

          debugPrint('[REQ] ${o.method} ${o.baseUrl}${o.path}  qp=${o.queryParameters}');
          debugPrint('[REQ] Authorization? ${hdrs.containsKey('Authorization')}   x-api-key=$masked');
          return h.next(o);
        },
      ),
    );
  }


  @override
  void dispose() {
    _urlController.dispose();
    _deb?.cancel();
    _inflight?.cancel();
    super.dispose();
  }
  void _handleSceneResult(dynamic data) {
    final version = _searchVersion;                 // snapshot for staleness guard
    final list = _normalizeResults(data);

    if (!mounted || version != _searchVersion) return;

    setState(() {
      _results = list;
      _isLoading = false;
      _isPicking = false;
    });

    _kickoffEnrichment(list, version);             // background enrichment
  }
  Future<void> _warmTokens() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _jwt = p.getString('access_token');
      _apiKey = p.getString('api_key');
    });
  }
  void _appendHistory(List<Map<String, dynamic>> list) {
    if (list.isEmpty) return;
    final hist = context.read<SceneHistoryModel>();
    final topFour = list.take(4).toList().reversed;
    for (final item in topFour) {
      hist.addEntry(_makeEntry(item));
    }
  }
  // ---------- Helpers to normalize shapes ----------

  String _pickPreviewUrl(Map<String, dynamic> item) {
  final ani = _normalizeAni(item['anilist']);
  final coverMap = (ani['coverImage'] as Map<String, dynamic>? ?? {});

  final preview = (item['image'] as String? ?? '').trim();
  final large = (coverMap['large'] as String? ?? '').trim();
  final medium = (coverMap['medium'] as String? ?? '').trim();

  if (preview.isNotEmpty) return preview;
  if (large.isNotEmpty) return large;
  if (medium.isNotEmpty) return medium;
  return '';
}

String _pickTitle(Map<String, dynamic> item) {
  final ani = _normalizeAni(item['anilist']);
  final titleMap = (ani['title'] as Map<String, dynamic>? ?? {});

  return (titleMap['romaji'] as String? ??
          titleMap['english'] as String? ??
          titleMap['native'] as String? ??
          (item['title'] as String?) ??
          (item['filename'] as String?) ??
          '[Unknown]')
      .trim();
}

Widget _previewImage(
  Map<String, dynamic> item, {
  double height = 180,
  BoxFit fit = BoxFit.cover,
}) {
  final ani = _normalizeAni(item['anilist']);
  final coverMap = (ani['coverImage'] as Map<String, dynamic>? ?? {});

  final preview = (item['image'] as String? ?? '').trim();
  final large = (coverMap['large'] as String? ?? '').trim();
  final medium = (coverMap['medium'] as String? ?? '').trim();
  final fallbackText = _pickTitle(item);

  Widget textFallback() => SizedBox(
        height: height,
        child: Center(
          child: Text(
            fallbackText,
            textAlign: TextAlign.center,
          ),
        ),
      );

  if (preview.isNotEmpty) {
    return Image.network(
      preview,
      height: height,
      fit: fit,
      cacheWidth: 360,
      errorBuilder: (_, __, ___) {
        if (large.isNotEmpty) {
          return Image.network(
            large,
            height: height,
            fit: fit,
            cacheWidth: 360,
            errorBuilder: (_, __, ___) {
              if (medium.isNotEmpty) {
                return Image.network(
                  medium,
                  height: height,
                  fit: fit,
                  cacheWidth: 360,
                  errorBuilder: (_, __, ___) => textFallback(),
                );
              }
              return textFallback();
            },
          );
        }
        if (medium.isNotEmpty) {
          return Image.network(
            medium,
            height: height,
            fit: fit,
            cacheWidth: 360,
            errorBuilder: (_, __, ___) => textFallback(),
          );
        }
        return textFallback();
      },
    );
  }

  if (large.isNotEmpty) {
    return Image.network(
      large,
      height: height,
      fit: fit,
      cacheWidth: 360,
      errorBuilder: (_, __, ___) {
        if (medium.isNotEmpty) {
          return Image.network(
            medium,
            height: height,
            fit: fit,
            cacheWidth: 360,
            errorBuilder: (_, __, ___) => textFallback(),
          );
        }
        return textFallback();
      },
    );
  }

  if (medium.isNotEmpty) {
    return Image.network(
      medium,
      height: height,
      fit: fit,
      cacheWidth: 360,
      errorBuilder: (_, __, ___) => textFallback(),
    );
  }

  return textFallback();
  }

  Future<void> _ensureApiKeyFromMe() async {
    try {
      // Force-include Authorization if we have it; this helps when cookies aren't present on mobile.
      final resp = await _dio.get(
        '/auth/me',
        options: Options(
          headers: {
            if (_jwt != null && _jwt!.isNotEmpty) 'Authorization': 'Bearer $_jwt',
          },
        ),
      );

      // Minimal debug breadcrumbs (safe to leave on in dev)
      if (resp.statusCode != 200) {
        debugPrint('[ME] /auth/me status=${resp.statusCode}  body=${resp.data}');
        return;
      }

      final data = resp.data is Map ? resp.data as Map<String, dynamic> : const <String, dynamic>{};
      final key = (data['api_key'] as String?)?.trim();

      debugPrint('[ME] received api_key? ${key == null || key.isEmpty ? "NO" : "YES"}');

      if (key != null && key.isNotEmpty) {
        final p = await SharedPreferences.getInstance();
        await p.setString('api_key', key);
        if (mounted) setState(() => _apiKey = key);
      } else {
        // Helpful hint if the backend didn't include the key
        debugPrint('[ME] api_key missing in /auth/me response. Ensure backend returns "api_key".');
      }
    } catch (e, st) {
      debugPrint('[ME] error fetching /auth/me: $e\n$st');
    }
  }


  // Extract a numeric AniList ID from various incoming shapes.
  int? _extractId(dynamic raw) {
    if (raw is int) return raw;
    if (raw is String) return int.tryParse(raw);
    if (raw is Map) {
      final v = raw['id'];
      if (v is int) return v;
      if (v is String) return int.tryParse(v);
    }
    return null;
  }

  // Normalize an anilist field into a Map<String,dynamic>.
  Map<String, dynamic> _normalizeAni(dynamic ani) {
    if (ani is Map<String, dynamic>) return ani;
    if (ani is Map) return Map<String, dynamic>.from(ani);
    final id = _extractId(ani);
    return id != null ? {'id': id} : <String, dynamic>{};
  }

  String _formatHMS(num secondsRaw) {
    final total = secondsRaw.floor();
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    return '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }

  // ---------- Search flows ----------
  int _quotaVersion = 0;

  Future<void> _searchByImage() async {
    if (_isPicking) return;
    _isPicking = true;

    await _waitForAuth();

    final myVersion = ++_searchVersion;
    if (mounted) setState(() => _isLoading = true);

    _inflight?.cancel('New search started');
    _inflight = CancelToken();

    try {
      final file = await _picker.pickImage(source: ImageSource.gallery);
      if (file == null) return;

      final raw = await File(file.path).readAsBytes();
      final compressed = await FlutterImageCompress.compressWithList(
        raw,
        quality: 80,
        minWidth: 320,
        minHeight: 320,
        format: CompressFormat.jpeg,
      );

      final resp = await _dio.post(
        '/search',
        data: compressed, // ✅ send bytes directly
        queryParameters: {'top': 4},
        options: Options(
          headers: {'Content-Type': 'image/jpeg'},
          validateStatus: (s) => s != null && s < 600,
        ),
        cancelToken: _inflight,
      );

      if (resp.statusCode == 524) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Server timed out (524). Try again or use a smaller image.')),
        );
        setState(() { _isLoading = false; _isPicking = false; });
        return;
      }

      debugPrint('[RESP] status=${resp.statusCode}');
      debugPrint('[RESP] body=${resp.data}');

      if (resp.statusCode == 402) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Quota or concurrency limit exceeded (402).')),
          );
          setState(() {
            _isLoading = false;
            _isPicking = false;
          });
        }
        return;
      }


      if (!mounted || myVersion != _searchVersion) return;
      if (resp.statusCode != 200) throw Exception('Server returned ${resp.statusCode}');

      final list = _normalizeResults(resp.data);
      setState(() {
        _results = list;
        _isLoading = false;
        _isPicking = false;
      });

      _kickoffEnrichment(list, myVersion);

    } catch (e, st) {
      debugPrint('❌ Search error: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Search failed: $e')),
        );
      }
    } finally {

      if (mounted) {
        setState(() {
          _isLoading = false;
          _isPicking = false;
        });
      }
    }
  }


  Future<void> _waitForAuth() async {
    if (_authReady != null && !_authReady!.isCompleted) {
      return _authReady!.future;
    }
    _authReady = Completer<void>();
    try {
      // Load from prefs
      await _warmTokens();
      // If we still don't have api key, fetch once from /auth/me
      if ((_apiKey == null || _apiKey!.isEmpty)) {
        await _ensureApiKeyFromMe();
      }
    } finally {
      _authReady?.complete();
    }
  }



  Future<void> _searchByUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid image URL.')),
      );
      return;
    }

    await _waitForAuth(); //

    if (mounted) setState(() => _isLoading = true);

    _inflight?.cancel('New search started');
    _inflight = CancelToken();

    try {
      final resp = await _dio.get(
  '/search',
  queryParameters: {'url': url, 'top': 4},
  cancelToken: _inflight,
  options: Options(validateStatus: (s) => s != null && s < 600),
    );


      if (resp.statusCode != 200) throw Exception('Server returned ${resp.statusCode}');
      _handleSceneResult(resp.data);

    } catch (e, st) {
      debugPrint('❌ Search error: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Search failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }



  // kick off enrichment without blocking UI; guarded by version
  void _kickoffEnrichment(List<Map<String, dynamic>> baseList, int version) {
    () async {
      try {
        final enriched = await _enrichAniListSafe(baseList).timeout(const Duration(seconds: 6));
        if (!mounted || version != _searchVersion) return;
        setState(() => _results = enriched);
        if (enriched.isNotEmpty) _appendHistory(enriched); // << here only
            } catch (e, st) {
        debugPrint('AniList enrichment failed: $e\n$st');
      }
    }();
  }

  Future<List<Map<String, dynamic>>> _enrichAniListSafe(List<Map<String, dynamic>> list) async {
    final ids = <int>[
      for (final e in list)
        if (_extractId(e['anilist']) != null) _extractId(e['anilist'])!,
    ];
    if (ids.isEmpty) return List<Map<String, dynamic>>.from(list);

    try {
      final resp = await http.post(
        Uri.parse('https://graphql.anilist.co'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"query": _anilistQuery, "variables": {"ids": ids}}),
      ).timeout(const Duration(seconds: 4));   // tighter timeout

      if (resp.statusCode != 200) {
        debugPrint('AniList GraphQL failed: status=${resp.statusCode} body=${resp.body}');
        return List<Map<String, dynamic>>.from(list);
      }

      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final media = (((decoded['data'] as Map?)?['Page'] as Map?)?['media'] as List?) ?? [];
      final byId = {
        for (final m in media.whereType<Map>())
          (m['id'] as num).toInt(): Map<String, dynamic>.from(m)
      };

      final out = <Map<String, dynamic>>[];
      for (final e in list) {
        final copy = Map<String, dynamic>.from(e);
        final id = _extractId(copy['anilist']);
        final rep = id != null ? byId[id] : null;
        copy['anilist'] = rep ?? _normalizeAni(copy['anilist']);
        out.add(copy);
      }
      return out;
    } catch (_) {
      return List<Map<String, dynamic>>.from(list);
    }
  }

  List<Map<String, dynamic>> _normalizeResults(dynamic data) {
    List<dynamic>? raw;
    if (data is Map<String, dynamic>) {
      raw = (data['result'] ?? data['docs'] ?? (data['result'] is Map ? data['result']['docs'] : null)) as List?;
    }
    if (raw == null) return [];

    final list = raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    list.sort(
          (a, b) => ((b['similarity'] ?? 0) as num).compareTo((a['similarity'] ?? 0) as num),
    );

    return list.length > 4 ? list.take(4).toList() : list;
  }

  Future<void> _enrichAniList(List<Map<String, dynamic>> list) async {
    final ids = <int>[
      for (final e in list)
        if (_extractId(e['anilist']) != null) _extractId(e['anilist'])!,
    ];
    if (ids.isEmpty) return;

    final resp = await http.post(
      Uri.parse('https://graphql.anilist.co'),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"query": _anilistQuery, "variables": {"ids": ids}}),
    );
    if (resp.statusCode != 200) return;

    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final media = (((decoded['data'] as Map?)?['Page'] as Map?)?['media'] as List?) ?? [];

    final byId = {
      for (final m in media.whereType<Map>())
        (m['id'] as num).toInt(): Map<String, dynamic>.from(m)
    };

    setState(() {
      for (final e in _results) {
        final id = _extractId(e['anilist']);
        if (id != null && byId[id] != null) {
          e['anilist'] = byId[id]!;
        } else {
          // keep normalized minimal map to avoid later type errors
          e['anilist'] = _normalizeAni(e['anilist']);
        }
      }
    });
  }

  void _applyQuotaFromResponse(Response resp, {bool consumed = false}) {
    try {
      final int reqQv = (resp.requestOptions.extra['qv'] as int?) ?? 0;
      if (reqQv != 0 && reqQv <= _qvApplied) return; // stale update

      final Map<String, dynamic> body =
      resp.data is Map ? (resp.data as Map<String, dynamic>) : const <String, dynamic>{};

      final headerTier = resp.headers.value('X-Tier') ?? resp.headers.value('x-tier');

      // Could be duplicated or collapsed "13, 12" → we want the LAST number
      String? headerRemRaw =
          resp.headers.value('X-Remaining-Searches') ?? resp.headers.value('x-remaining-searches');

      int? parseLastInt(String s) {
        // split on comma if a proxy collapsed multiple headers, trim, take last token
        final parts = s.split(',').map((p) => p.trim()).toList();
        final last = parts.isNotEmpty ? parts.last : s;
        final m = RegExp(r'-?\d+').firstMatch(last);
        return m != null ? int.tryParse(m.group(0)!) : null;
      }

      int? remaining;
      if (headerRemRaw != null && headerRemRaw.trim().isNotEmpty) {
        remaining = parseLastInt(headerRemRaw);
      } else if (body['remaining_searches'] != null) {
        remaining = int.tryParse(body['remaining_searches'].toString());
      }

      // If we optimistically decremented, don't allow the server to bump the number UP
      if (consumed && remaining != null && _remainingSearches != null) {
        remaining = remaining < _remainingSearches! ? remaining : _remainingSearches!;
      }

      if (!mounted) return;
      setState(() {
        if (headerTier != null) _currentTier = headerTier;
        if (remaining != null) _remainingSearches = remaining;
        if (reqQv != 0) _qvApplied = reqQv;
      });
    } catch (_) {}
  }


  SceneHistoryEntry _makeEntry(Map<String, dynamic> item) {
    final ani = _normalizeAni(item['anilist']);
    final aniId = _extractId(ani) ?? 0;

    String title = (item['title'] as String?)?.trim().isNotEmpty == true
    ? (item['title'] as String).trim()
    : ((item['filename'] as String?)?.trim().isNotEmpty == true
        ? (item['filename'] as String).trim()
        : "Unknown Title");

    final titleMap = ani['title'];
    if (titleMap is Map) {
      title = (titleMap['romaji'] ??
              titleMap['english'] ??
              titleMap['native'] ??
              title)
          .toString()
          .trim();
    }

    String cover = ((item['image'] as String?) ?? '').trim();
    final coverMap = ani['coverImage'];
    if (cover.isEmpty && coverMap is Map) {
      cover = (coverMap['large'] ?? coverMap['medium'] ?? '').toString().trim();
    }
    final epRaw = item['episode'];
    final episode = epRaw == null
        ? "Unknown"
        : (epRaw is String ? epRaw : epRaw.toString());

    final from = (item['from'] ?? "").toString();
    final to = (item['to'] ?? "").toString();
    final range = (from.isNotEmpty && to.isNotEmpty) ? "$from - $to" : "";

    return SceneHistoryEntry(
      aniListId: aniId,
      title: title,
      coverUrl: cover,
      episode: episode,
      timeRange: range,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  static const _anilistQuery = r'''
query ($ids: [Int]) {
  Page(perPage: 50) {
    media(id_in: $ids, type: ANIME) {
      id
      title { romaji english native }
      coverImage { large medium }
      episodes
      duration
      format
      startDate { year month day }
      endDate { year month day }
      synonyms
      genres
      studios { edges { node { name } } }
      externalLinks { site url }
      description
    }
  }
}
''';

  void _debouncedUrlSearch() {
    _deb?.cancel();
    _deb = Timer(const Duration(milliseconds: 400), _searchByUrl);
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    return _buildMainScaffold();
  }


  Widget _buildMainScaffold() {
    final hasResults = _results.isNotEmpty;
    final Map<String, dynamic>? top = hasResults ? _results[0] : null;
    bool hasAniMeta = false;

    String topCover = '', topTitle = '[Unknown]', topSim = '0.00%';
    String ep = '', fromStr = '', toStr = '';

    final favModel = context.watch<FavoritesModel>();

    if (hasResults && top != null) {
      final aniMap = _normalizeAni(top['anilist']);
      hasAniMeta =
          aniMap.containsKey('title') || aniMap.containsKey('coverImage');

      topCover = _pickPreviewUrl(top);

      final titleMap = (aniMap['title'] as Map<String, dynamic>? ?? {});
      topTitle = _pickTitle(top);
      final simNum = (top['similarity'] as num?) ?? 0.0;
      topSim = '${(simNum * 100).toStringAsFixed(2)}%';

      final epRaw = top['episode'];
      ep = epRaw == null ? '' : (epRaw is String ? epRaw : epRaw.toString());

      final f = (top['from'] as num?) ?? 0;
      final t = (top['to'] as num?) ?? 0;
      fromStr = _formatHMS(f);
      toStr = _formatHMS(t);
    }
    final disabled = !_canSearch || _isLoading || _isPicking;

    return Scaffold(
      appBar: AppBar(title: const Text('Scene Search')),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            const SizedBox(height: 12),
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'Image URL',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _debouncedUrlSearch(),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _searchByUrl,
                    child: const Text('Search by URL'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _searchByImage,
                    child: const Text('Upload Image'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_currentTier != null && _remainingSearches != null)
              Card(
                color: Colors.grey[100],
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      RichText(
                        text: TextSpan(
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.black, // base color for the line
                          ),
                          children: [
                            const TextSpan(text: 'Tier: '),
                            TextSpan(
                              text: (_currentTier ?? '').toString(),
                              style: const TextStyle(color: Colors.blueGrey),
                            ),
                            const TextSpan(text: '   |   Searches left: '),

                            // 🎯 style ONLY the number with background + text color
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: (_remainingSearches ?? 0) == 0
                                      ? Colors.red.shade50      // background when 0 left
                                      : Colors.green.shade50,   // background when > 0 left
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${_remainingSearches ?? 0}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: (_remainingSearches ?? 0) == 0
                                        ? Colors.red.shade700    // text when 0 left
                                        : Colors.green.shade800, // text when > 0 left
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_remainingSearches == 0)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'Please upgrade for a higher limit!',
                            style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            if (_isLoading)
              const Center(child: CircularProgressIndicator()),
            if (!_isLoading)
              Expanded(
                child: hasResults
                    ? SingleChildScrollView(
                  child: Column(
                    children: [
                      // Top match
                      GestureDetector(
                        onTap: () => _showDetails(_results[0]),
                        child: Column(
                          children: [
                            Text(
                              topTitle,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (ep.isNotEmpty)
                              RichText(
                                text: TextSpan(
                                  style: DefaultTextStyle.of(context).style,
                                  children: [
                                    const TextSpan(
                                      text: 'Episode: ',
                                      style: TextStyle(color: Colors.teal),
                                    ),
                                    TextSpan(text: '$ep   $fromStr – $toStr'),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 6),
                            RichText(
                              text: TextSpan(
                                style: DefaultTextStyle.of(context).style,
                                children: [
                                  const TextSpan(
                                    text: 'Similarity: ',
                                    style: TextStyle(color: Colors.teal),
                                  ),
                                  TextSpan(text: topSim),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Builder(
                              builder: (_) {
                                final videoUrl = (top!['video'] as String? ?? '').trim();
                                if (videoUrl.isNotEmpty) {
                                  return SceneClipPreview(
                                    url: videoUrl,
                                    height: 180,
                                    fallback: _previewImage(
                                      top,
                                      height: 180,
                                      fit: BoxFit.cover,
                                    ),
                                  );
                                }
                                return _previewImage(
                                  top,
                                  height: 180,
                                  fit: BoxFit.cover,
                                );
                              },
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),
                      ),

                      // Horizontal list of the rest
                      SizedBox(
                        height: 140,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _results.length - 1,
                          itemBuilder: (_, i) {
                            final item = _results[i + 1];
                            final ani2 = _normalizeAni(item['anilist']);
                            final thumb = _pickPreviewUrl(item);
                            final simPct =
                                '${(((item['similarity'] as num?) ?? 0.0) * 100).toStringAsFixed(1)}%';

                            final idStr = (_extractId(ani2) ?? 0).toString();
                            final isFav = favModel.isAnimeFavorite(idStr);

                            return Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: Stack(
                                children: [
                                  GestureDetector(
                                    onTap: () => _showDetails(item),
                                    child: SizedBox(
                                      width: 100,
                                      child: Column(
                                        children: [
                                          Expanded(
                                            child: _previewImage(
                                            item,
                                            height: 100,
                                            fit: BoxFit.cover,
                                          ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(simPct,
                                              style: const TextStyle(fontSize: 12)),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: IconButton(
                                      icon: Icon(
                                        isFav ? Icons.star : Icons.star_border,
                                        color: Colors.amber,
                                        size: 24,
                                      ),
                                      onPressed: () =>
                                          favModel.toggleAnimeFavoriteById(idStr),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                )
                    : const Center(child: Text('No matches found.')),
              ),
          ],
        ),
      ),
      bottomNavigationBar: const Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Text(
          'Information provided by anilist.co™',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 10, color: Colors.grey),
        ),
      ),
    );
  }

  void _showDetails(Map<String, dynamic> item) {
    final ani = _normalizeAni(item['anilist']);
    final bool hasAniMeta =
        ani.containsKey('title') || ani.containsKey('coverImage');

    final titleMap = (ani['title'] as Map<String, dynamic>? ?? {});
    final coverMap = (ani['coverImage'] as Map<String, dynamic>? ?? {});

    final coverUrl = _pickPreviewUrl(item);
    final epRaw = item['episode'];
    final ep = epRaw == null ? '' : (epRaw is String ? epRaw : epRaw.toString());

    final fromSec = (item['from'] as num?) ?? 0;
    final toSec = (item['to'] as num?) ?? 0;
    final fromStr = _formatHMS(fromSec);
    final toStr = _formatHMS(toSec);
    final romaji = _pickTitle(item);
    final english = titleMap['english'] as String?;
    final native = titleMap['native'] as String?;

    final episodes = ani['episodes']?.toString() ?? '';
    final duration = ani['duration']?.toString() ?? '';
    final format = ani['format']?.toString() ?? '';

    final startMap = ani['startDate'] as Map<String, dynamic>? ?? {};
    final endMap = ani['endDate'] as Map<String, dynamic>? ?? {};
    final startStr = startMap.isNotEmpty
        ? '${startMap['year']}-${startMap['month']}-${startMap['day']}'
        : '';
    final endStr = endMap.isNotEmpty
        ? '${endMap['year']}-${endMap['month']}-${endMap['day']}'
        : '';

    final synonyms =
        (ani['synonyms'] as List?)?.cast<String>().join(', ') ?? '';
    final genres = (ani['genres'] as List?)?.cast<String>().join(', ') ?? '';

    final studios = (ani['studios']?['edges'] as List?)
        ?.map((e) => ((e is Map ? e['node'] : null) as Map?)?['name'] as String? ?? '')
        .where((s) => s.isNotEmpty)
        .toList() ??
        [];

    final links = (ani['externalLinks'] as List?)
        ?.map((e) => '${(e as Map)['site']}: ${(e)['url']}')
        .join('\n') ??
        '';

    final simPct =
        (((item['similarity'] as num?) ?? 0.0) * 100).toStringAsFixed(2) + '%';

    final topId = (_extractId(ani) ?? 0).toString();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        builder: (_, ctrl) => SingleChildScrollView(
          controller: ctrl,
          padding: const EdgeInsets.all(16),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (ep.isNotEmpty)
                    RichText(
                      text: TextSpan(
                        style: DefaultTextStyle.of(context).style,
                        children: [
                          const TextSpan(
                              text: 'Episode: ',
                              style: TextStyle(color: Colors.teal)),
                          TextSpan(text: '$ep   $fromStr – $toStr'),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  Center(
                    child: ((item['video'] as String? ?? '').trim().isNotEmpty)
                        ? SceneClipPreview(
                            url: (item['video'] as String).trim(),
                            height: 180,
                            fallback: _previewImage(
                              item,
                              height: 180,
                              fit: BoxFit.cover,
                            ),
                          )
                        : _previewImage(
                            item,
                            height: 180,
                            fit: BoxFit.cover,
                          ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    romaji,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (english != null)
                    RichText(
                      text: TextSpan(
                        style: DefaultTextStyle.of(context).style,
                        children: [
                          const TextSpan(
                              text: 'English: ',
                              style: TextStyle(color: Colors.purple)),
                          TextSpan(text: english),
                        ],
                      ),
                    ),
                  if (native != null)
                    RichText(
                      text: TextSpan(
                        style: DefaultTextStyle.of(context).style,
                        children: [
                          const TextSpan(
                              text: 'Native: ',
                              style: TextStyle(color: Colors.orange)),
                          TextSpan(text: native),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  if (episodes.isNotEmpty || duration.isNotEmpty || format.isNotEmpty)
                    RichText(
                      text: TextSpan(
                        style: DefaultTextStyle.of(context).style,
                        children: [
                          if (episodes.isNotEmpty) ...[
                            const TextSpan(
                                text: 'Episodes: ',
                                style: TextStyle(color: Colors.green)),
                            TextSpan(text: episodes),
                          ],
                          if (duration.isNotEmpty) ...[
                            const TextSpan(
                                text: '   Duration: ',
                                style: TextStyle(color: Colors.green)),
                            TextSpan(text: '$duration min'),
                          ],
                          if (format.isNotEmpty) ...[
                            const TextSpan(
                                text: '   Format: ',
                                style: TextStyle(color: Colors.green)),
                            TextSpan(text: format),
                          ],
                        ],
                      ),
                    ),
                  const SizedBox(height: 4),
                  RichText(
                    text: TextSpan(
                      style: DefaultTextStyle.of(context).style,
                      children: [
                        const TextSpan(
                            text: 'Airing: ',
                            style: TextStyle(color: Colors.red)),
                        TextSpan(text: startStr),
                        if (endStr.isNotEmpty)
                          const TextSpan(
                              text: ' → ',
                              style: TextStyle(color: Colors.red)),
                        if (endStr.isNotEmpty) TextSpan(text: endStr),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  RichText(
                    text: TextSpan(
                      style: DefaultTextStyle.of(context).style,
                      children: [
                        const TextSpan(
                            text: 'Similarity: ',
                            style: TextStyle(color: Colors.blue)),
                        TextSpan(text: simPct),
                      ],
                    ),
                  ),
                  const Divider(height: 24),
                  if (!hasAniMeta)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                        'AniList metadata is temporarily unavailable. Basic match info is still shown from the search API.',
                        style: TextStyle(color: Colors.orange),
                      ),
                    ),
                  if ((ani['description'] as String?)?.isNotEmpty ?? false)
                    Text(ani['description'] as String),
                  if (synonyms.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: RichText(
                        text: TextSpan(
                          style: DefaultTextStyle.of(context).style,
                          children: [
                            const TextSpan(
                                text: 'Alias: ',
                                style: TextStyle(color: Colors.pink)),
                            TextSpan(text: synonyms),
                          ],
                        ),
                      ),
                    ),
                  if (genres.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: RichText(
                        text: TextSpan(
                          style: DefaultTextStyle.of(context).style,
                          children: [
                            const TextSpan(
                                text: 'Genres: ',
                                style: TextStyle(color: Colors.purple)),
                            TextSpan(text: genres),
                          ],
                        ),
                      ),
                    ),
                  if (studios.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: RichText(
                        text: TextSpan(
                          style: DefaultTextStyle.of(context).style,
                          children: [
                            const TextSpan(
                                text: 'Studios: ',
                                style: TextStyle(color: Colors.orange)),
                            TextSpan(text: studios.join(', ')),
                          ],
                        ),
                      ),
                    ),
                  if (links.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: RichText(
                        text: TextSpan(
                          style: DefaultTextStyle.of(context).style,
                          children: [
                            const TextSpan(
                                text: 'External Links: ',
                                style: TextStyle(color: Colors.indigo)),
                            TextSpan(text: links),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                ],
              ),
              Positioned(
                right: 16,
                top: 16,
                child: Consumer<FavoritesModel>(
                  builder: (_, favModel, __) {
                    final isFav = favModel.isAnimeFavorite(topId);
                    return IconButton(
                      icon: Icon(
                        isFav ? Icons.star : Icons.star_border,
                        color: Colors.amber,
                        size: 30,
                      ),
                      onPressed: () {
                        favModel.toggleAnimeFavoriteById(topId);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
class SceneClipPreview extends StatefulWidget {
  final String url;
  final double height;
  final Widget fallback;

  const SceneClipPreview({
    super.key,
    required this.url,
    required this.fallback,
    this.height = 180,
  });

  @override
  State<SceneClipPreview> createState() => _SceneClipPreviewState();
}

class _SceneClipPreviewState extends State<SceneClipPreview> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(0);
      await c.play();

      if (!mounted) {
        await c.dispose();
        return;
      }

      setState(() {
        _controller = c;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _failed = true);
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return widget.fallback;
    }

    if (_controller == null || !_controller!.value.isInitialized) {
      return SizedBox(
        height: widget.height,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return SizedBox(
      height: widget.height,
      child: AspectRatio(
        aspectRatio: _controller!.value.aspectRatio,
        child: VideoPlayer(_controller!),
      ),
    );
  }
}