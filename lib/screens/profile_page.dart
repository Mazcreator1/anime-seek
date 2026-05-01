// lib/screens/profile_page.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:anime_finder/services/auth_service.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:collection/collection.dart';
import 'package:anime_finder/screens/anime_match_detail_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---- THEME ----
const Color kBg = Color(0xFF0F0F10);
const Color kCard = Color(0xFF17181A);
const Color kBorder = Color(0x22222222);
const Color kText = Colors.white;
const Color kSub = Color(0xFFB7BBC3);
const Color kAccent = Color(0xFF00D1B2);

class _ProfileCacheEntry {
  final Map<String, dynamic>? profile;
  final Map<String, dynamic>? analytics;
  final List<Map<String, dynamic>> badges;
  final List<Map<String, dynamic>> recent;
  final List<dynamic> favAnime;
  final List<dynamic> favChars;
  final Map<String, dynamic>? profileSong;
  final int fetchedAtMs;
  const _ProfileCacheEntry({
    required this.profile,
    required this.analytics,
    required this.badges,
    required this.recent,
    required this.favAnime,
    required this.favChars,
    required this.profileSong,
    required this.fetchedAtMs,
  });
}

class _ProfileCache {
  static const int ttlMs = 60 * 1000; // 1 minute (tweak)
  static final Map<int, _ProfileCacheEntry> _map = {};

  static _ProfileCacheEntry? get(int id) {
    final e = _map[id];
    if (e == null) return null;
    final fresh = DateTime.now().millisecondsSinceEpoch - e.fetchedAtMs < ttlMs;
    return fresh ? e : null;
    // return e; // <- if you want "stale-while-revalidate" behavior
  }

  static void put(int id, _ProfileCacheEntry e) => _map[id] = e;
  static void invalidate(int id) => _map.remove(id);
  static void clear() => _map.clear();
}


class ProfilePage extends StatefulWidget {
  final int userId; // 0 means "me"
  const ProfilePage({Key? key, required this.userId}) : super(key: key);

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  // ---- STATE ----
  Map<String, dynamic>? _profile;        // /users/{id}
  Map<String, dynamic>? _analytics;      // /users/{id}/analytics
  List<Map<String, dynamic>> _badges = []; // /users/{id}/badges
  List<Map<String, dynamic>> _recent = []; // scenes + audio (merged)
  bool _loading = false;
  String? _error;
  int? _meId;
  Timer? _postPoll;
  bool _alive = false;
  bool get _isOwner => _meId != null && _profile?['id'] == _meId;
  Uint8List? _avatarPreview;
  int? _postCount;
  Timer? _poll;
  Timer? _analyticsPoll;
  StreamSubscription? _sub;

  void _ss(VoidCallback fn) {
    if (_alive && mounted) setState(fn);
  }

  Map<String, dynamic>? _profileSong;

  // headline + bio editable
  final _headlineCtl = TextEditingController();
  final _bioCtl = TextEditingController();
  final _headlineFocus = FocusNode();
  bool _headlineEditing = false;
  bool _bioEditing = false;
  static const String _kAutoplayPrefKey = 'profile_autoplay_enabled';
  bool _autoplayEnabled = true; // default ON
  bool _autoplayLoaded = false;
  // music search (Apple Music / iTunes)
  final _spotifySearchCtl = TextEditingController(); // name kept to minimize churn
  Timer? _spotifyDebounce;
  List<dynamic> _spotifySearchResults = const [];
  bool _spotifySearching = false;

  // favorites
  List<dynamic> _favAnime = const [];
  List<dynamic> _favChars = const [];
  String? _lastAutoplayedPreview;

  // avatar
  final _picker = ImagePicker();
  int? _avatarVBuster;

  // generic music state (no auth)
  bool _spotifyLinked = true; // always “linked” for iTunes use
  bool _spotifyLoading = false;
  String? _spotifyErr;

  // preview player state
  final _player = AudioPlayer();
  Duration _pDur = Duration.zero;   // preview duration (usually ~30s)
  Duration _pPos = Duration.zero;
  String? _currentPreviewUrl;
  bool _playingPreview = false;
  int _lastPosUiMs = -999; // throttle UI updates

  StreamSubscription<Duration>? _durSub;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<void>? _compSub;
  // tap-outside to save
  void _saveIfNeededAndCollapse() {
    if (_headlineEditing || _bioEditing) _saveProfileText();
    setState(() {
      _headlineEditing = false;
      _bioEditing = false;
      FocusScope.of(context).unfocus();
    });
  }

  @override
  void initState() {
    super.initState();
    _alive = true;
    _unawaitedLoadAutoplay();

    // Global audio context
    AudioPlayer.global.setAudioContext(const AudioContext(
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.playback,
        options: [AVAudioSessionOptions.mixWithOthers],
      ),
      android: AudioContextAndroid(
        contentType: AndroidContentType.music,
        usageType: AndroidUsageType.media,
        audioFocus: AndroidAudioFocus.gain, // persistent focus
        stayAwake: true,
      ),
    ));

    // Player listeners (store subs so we can cancel in dispose)
    _durSub = _player.onDurationChanged.listen((d) {
      if (!mounted) return;
      setState(() => _pDur = d);
    });
    _posSub = _player.onPositionChanged.listen((p) {
      if (!mounted) return;
      final ms = p.inMilliseconds;
      if ((ms - _lastPosUiMs).abs() >= 100) { // ~10 FPS UI
        _lastPosUiMs = ms;
        setState(() => _pPos = p);
      }
    });
    _compSub = _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() => _playingPreview = false);
    });
    _bootstrap();
  }


  @override
  void dispose() {
    _alive = false;
    _spotifyDebounce?.cancel();
    _poll?.cancel();
    _sub?.cancel();
    _durSub?.cancel();
    _posSub?.cancel();
    _compSub?.cancel();
    _player.dispose();
    _headlineCtl.dispose();
    _bioCtl.dispose();
    _headlineFocus.dispose();
    _analyticsPoll?.cancel();
    _spotifySearchCtl.dispose();
    _postPoll?.cancel();
    super.dispose();
  }

 
  String _extractAnimeTitleDeep(Map m) {
    // flat keys
    final flat = _pickStr(m, [
      'anime_title','anime','series',
      'title_romaji','titleRomaji','title_english','titleEnglish'
    ]);
    if (flat.isNotEmpty) return flat;

    // nested: { anime: { title: { romaji/english/native } } } or { anilist: { title: {...} } }
    Map? a = m['anime'] is Map ? m['anime'] : (m['anilist'] is Map ? m['anilist'] : null);
    if (a is Map) {
      if (a['title'] is Map) {
        final t = Map<String,dynamic>.from(a['title']);
        final romaji  = (t['romaji'] ?? '').toString();
        final english = (t['english'] ?? '').toString();
        final native  = (t['native'] ?? '').toString();
        return [romaji, english, native].firstWhere((s) => s.trim().isNotEmpty, orElse: () => '');
      }
      final t2 = _pickStr(Map<String,dynamic>.from(a), [
        'title','title_romaji','titleRomaji','title_english','titleEnglish','name'
      ]);
      if (t2.isNotEmpty) return t2;
    }

    return '';
  }

  Future<void> _unawaitedLoadAutoplay() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getBool(_kAutoplayPrefKey);
      if (!mounted) return;
      setState(() {
        _autoplayEnabled = v ?? true; // default ON
        _autoplayLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _autoplayEnabled = true;
        _autoplayLoaded = true;
      });
    }
  }

  Future<void> _setAutoplayEnabled(bool v) async {
    setState(() => _autoplayEnabled = v);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kAutoplayPrefKey, v);
    } catch (_) {}
  }
  // ---- AUDIO HELPERS (no segments) ----
  Future<void> _playUrl(String url, {Duration? at}) async {
    try {
      if (_currentPreviewUrl != url) {
        await _player.stop();
        _currentPreviewUrl = url;

        if (mounted) {
          setState(() {
            _pPos = Duration.zero;
            _pDur = Duration.zero;
          });
        }

        await _player.setReleaseMode(ReleaseMode.stop);
      }

      await _player.play(UrlSource(url)); // returns Future<void>

      if (at != null) {
        int tries = 0;
        while (_pDur == Duration.zero && tries++ < 10) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
        await _player.seek(at);
      }

      if (mounted) setState(() => _playingPreview = true);
    } catch (e) {
      if (mounted) setState(() => _spotifyErr = 'Audio error: $e');
    }
  }

  Future<void> _playPreview() async {
    final preview = (_profileSong?['preview_url'] ?? '').toString();
    if (preview.isEmpty) return;
    await _playUrl(preview);
  }

  Future<void> _stopPlayback() async {
  try {
    await _player.stop();
  } finally {
    if (mounted) {
      setState(() {
        _playingPreview = false;
        _pPos = Duration.zero;
      });
    }
  }
}

  Future<void> _maybeAutoplayProfileSong() async {
  if (!_autoplayEnabled) return;
  final preview = (_profileSong?['preview_url'] ?? '').toString();
  if (preview.isEmpty) return;
  if (_lastAutoplayedPreview == preview) return;
  await _playPreview();
  _lastAutoplayedPreview = preview;
  }

  // ---- SEARCH ----
  void _onSearchChanged(String q) {
    _spotifyDebounce?.cancel();
    _spotifyDebounce = Timer(const Duration(milliseconds: 350), () {
      if (q.trim().isEmpty) {
        if (mounted) setState(() => _spotifySearchResults = const []);
        return;
      }
      _searchMusicTracks(q.trim());
    });
  }

  bool get _isFollowing {
    final v = _profile?['is_following'];
    if (v is bool) return v;
    if (v is num) return v.toInt() == 1;
    if (v is String) return v == '1' || v.toLowerCase() == 'true';
    return false;
  }


  Future<void> _searchMusicTracks(String q) async {
    if (!mounted) return;
    try {
      if (!mounted) return;
      setState(() { _spotifySearching = true; _spotifyErr = null; });

      final headers = await AuthService.authHeaders;
      if (!mounted) return;

      final url = 'https://anime-seek.com/fastapi/music/search?q=${Uri.encodeQueryComponent(q)}&limit=15&country=US';
      final r = await http.get(Uri.parse(url), headers: {...headers, 'Accept': 'application/json'});
      if (!mounted) return;

      if (r.statusCode == 200) {
        final list = json.decode(r.body) as List<dynamic>;
        if (!mounted) return;
        setState(() => _spotifySearchResults = list);
      } else {
        if (!mounted) return;
        setState(() => _spotifyErr = 'Search ${r.statusCode}: ${r.body}');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _spotifyErr = '$e');
    } finally {
      if (!mounted) return;
      setState(() => _spotifySearching = false);
    }
  }
  int _tsMs(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v > 1e12 ? v : v * 1000;
    if (v is num) return v.toDouble() > 1e12 ? v.toInt() : (v * 1000).toInt();
    if (v is String) {
      final n = int.tryParse(v.trim());
      if (n != null) return _tsMs(n);
      final dt = DateTime.tryParse(v);
      if (dt != null) return dt.toUtc().millisecondsSinceEpoch;
    }
    return 0;
  }




  // ---- BOOTSTRAP ----
  Future<void> _bootstrap({bool force = false}) async {
    // Bail fast if we're already disposed
    if (!_alive || !mounted) return;

    final headers = await AuthService.authHeaders;

    // 1) Resolve "me" first so _isOwner is correct
    if (_meId == null) {
      try {
        final meRes = await http.get(
          Uri.parse('https://anime-seek.com/fastapi/auth/me'),
          headers: headers,
        );
        if (!_alive || !mounted) return;

        if (meRes.statusCode == 200 && meRes.body.isNotEmpty) {
          final j = json.decode(meRes.body);
          _meId = _extractUserId(j);
        }
      } catch (_) {/* swallow */}
    }

    // 2) Cache hit?
    final targetId = widget.userId == 0 ? _meId : widget.userId;
    if (!_alive || !mounted) return;

    if (!force && targetId != null) {
      final cached = _ProfileCache.get(targetId);
      if (cached != null) {
        _ss(() {
          _profile     = cached.profile;
          _analytics   = cached.analytics;
          _badges      = cached.badges;
          _recent      = cached.recent;
          _profileSong = cached.profileSong;
          _favAnime    = cached.favAnime;
          _favChars    = cached.favChars;
          _error = null;
          _loading = false;
        });
      }
    }

    _ss(() => _loading = _profile == null);


    try {
      final id = widget.userId == 0 ? _meId : widget.userId;
      if (id == null) {
        _ss(() => _error = 'No user id.');
        return;
      }

      // Fire-and-forget posts count; doesn't block bootstrap.
      unawaited(_loadPostCount(id));

      // --- PROFILE ---
      final pRes = await http.get(
        Uri.parse('https://anime-seek.com/fastapi/users/$id'),
        headers: {...headers, 'Accept': 'application/json'},
      );
      if (!_alive || !mounted) return;
      if (pRes.statusCode != 200) {
        throw Exception('Profile ${pRes.statusCode}');
      }
      final pJson = json.decode(pRes.body);
      final profile = _extractProfileMap(pJson);

      // Seed editors for owner
      if (_alive && mounted && profile.isNotEmpty) {
        _headlineCtl.text = (profile['top_line'] ?? '').toString();
        _bioCtl.text      = (profile['bio'] ?? '').toString();
      }

      final List<dynamic> favAnime = _normalizeFavList(profile['favorite_anime']);
      final List<dynamic> favChars = _normalizeFavList(profile['favorite_characters']);

      _ss(() {
        _profile  = profile;
        _favAnime = favAnime;
        _favChars = favChars;
      });

      // --- PROFILE SONG ---
      Map<String, dynamic>? profileSong;
      try {
        final r = await http.get(
          Uri.parse('https://anime-seek.com/fastapi/music/user/$id'),
          headers: {...headers, 'Accept': 'application/json'},
        );
        if (_alive && mounted && r.statusCode == 200 && r.body.isNotEmpty) {
          final j = json.decode(r.body);
          final m = (j is Map) ? _unwrap(Map<String, dynamic>.from(j), ['profile_song', 'data']) : null;
          if (m != null && m.isNotEmpty) {
            profileSong = _normalizeSongMap(m);
          }
        }
      } catch (_) {/* swallow */}

      // --- ANALYTICS (initial fetch) ---
      Map<String, dynamic>? analytics;
      try {
        analytics = await _fetchAnalytics(id);
      } catch (_) {/* swallow */}

      // --- BADGES ---
      List<Map<String, dynamic>> badges = const [];
      try {
        final bRes = await http.get(
          Uri.parse('https://anime-seek.com/fastapi/users/$id/badges'),
          headers: {...headers, 'Accept': 'application/json'},
        );
        if (_alive && mounted && bRes.statusCode == 200 && bRes.body.isNotEmpty) {
          final bJson = json.decode(bRes.body);
          badges = _unwrapList(bJson);
        }
      } catch (_) {/* swallow */}

      // --- RECENT (initial load + start poller) ---
      await _loadRecent(id, allowProfileFallback: true);
      final recentCopy = List<Map<String, dynamic>>.from(_recent);

      // Apply state
      _ss(() {
        _profile     = profile;
        _analytics   = analytics;
        _badges      = badges;
        _favAnime    = favAnime;
        _favChars    = favChars;
        _profileSong = profileSong;
        _error = null;
      });

      // Start pollers (so stats & recents keep updating)
      if (_alive && mounted) {
        _startRecentPolling(id);
        _startAnalyticsPolling(id);
        _startPostCountPolling(id);

      }

      // Cache (preserve previously cached recents if current came back empty)
      final existing = _ProfileCache.get(id);
      final safeRecent = recentCopy.isEmpty
          ? (existing?.recent ?? const <Map<String, dynamic>>[])
          : recentCopy;

      _ProfileCache.put(
        id,
        _ProfileCacheEntry(
          profile: _profile,
          analytics: _analytics,
          badges: _badges,
          recent: safeRecent,
          profileSong: _profileSong,
          favAnime: _favAnime,
          favChars: _favChars,
          fetchedAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );

      // Optional autoplay
      if (_alive && mounted) {
        // fire-and-forget after first frame, or just play on user tap instead
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_autoplayEnabled) _maybeAutoplayProfileSong();
        });
      }
    } catch (e) {
      if (_alive && mounted) {
        _ss(() => _error = '$e');
      }
    } finally {
      if (_alive && mounted) {
        _ss(() => _loading = false);
      }
    }
  }
  
  List<Map<String, dynamic>> _unwrapList(
      dynamic raw, {
        List<String> keys = const ['items','data','results','list','rows','logs'],
      }) {
    if (raw is List) {
      return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    if (raw is Map) {
      for (final k in keys) {
        final v = raw[k];
        if (v is List) {
          return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        }
      }
      // lenient: single object as list
      if (raw.isNotEmpty && raw.values.first is Map) {
        return [Map<String, dynamic>.from(raw.values.first as Map)];
      }
    }
    return const <Map<String, dynamic>>[];
  }

// Last-ditch fallback: find the first List<Map> anywhere in a nested structure.
  List<Map<String, dynamic>> _firstListOfMaps(dynamic raw) {
    if (raw is List) {
      return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    if (raw is Map) {
      for (final v in raw.values) {
        final got = _firstListOfMaps(v);
        if (got.isNotEmpty) return got;
      }
    }
    return const <Map<String, dynamic>>[];
  }
  


  Future<void> _loadPostCount(int userId) async {
    try {
      final headers = await AuthService.authHeaders;
      final noCache = {
        ...headers,
        'Accept': 'application/json',
        'Cache-Control': 'no-cache, no-store, must-revalidate',
        'Pragma': 'no-cache',
      };

      // Bust caches with a random + timestamp param.
      final ts  = DateTime.now().millisecondsSinceEpoch;
      final rnd = Random().nextInt(1 << 30);

      final url = 'https://anime-seek.com/fastapi/users/$userId/posts/count?_ts=$ts&_r=$rnd';
      final r = await http.get(Uri.parse(url), headers: noCache);
      if (!mounted) return;

      if (r.statusCode == 200 && r.body.isNotEmpty) {
        final body = json.decode(r.body);
        // Endpoint contract: { user_id, posts, since, until }
        final count = (body is Map && body['posts'] is num)
            ? (body['posts'] as num).toInt()
            : int.tryParse(body['posts']?.toString() ?? '') ?? 0;

        _ss(() => _postCount = count);

      } else if (r.statusCode == 204) {
        _ss(() => _postCount = 0);
      } else {

      }
    } catch (_) {

    }
  }

  void _startPostCountPolling(int userId) {
    _postPoll?.cancel();
    _loadPostCount(userId); // prime immediately
    _postPoll = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted) return;
      _loadPostCount(userId);
    });
  }


  Future<List<Map<String, dynamic>>> _fetchRecentScenes(
      int userId, {
        bool allowProfileFallback = true,
      }) async {
    final headers = await AuthService.authHeaders;
    final noCache = {
      ...headers,
      'Accept': 'application/json',
      'Cache-Control': 'no-cache, no-store, must-revalidate',
      'Pragma': 'no-cache',
    };
    final ts  = DateTime.now().millisecondsSinceEpoch;
    final rnd = Random().nextInt(1 << 30);

    final isMe = (_meId != null && userId == _meId);

    // Put the most precise endpoints FIRST
    final candidates = <String>[
      if (isMe) 'https://anime-seek.com/fastapi/users/me/logs/scene?limit=6&order=desc&_ts=$ts&_r=$rnd',
      if (isMe) 'https://anime-seek.com/fastapi/me/logs/scene?limit=6&order=desc&_ts=$ts&_r=$rnd',

      'https://anime-seek.com/fastapi/users/$userId/logs/scene?limit=6&order=desc&_ts=$ts&_r=$rnd',
      'https://anime-seek.com/fastapi/users/$userId/logs/scenes?limit=6&order=desc&_ts=$ts&_r=$rnd',
      'https://anime-seek.com/fastapi/users/$userId/recent-scenes?limit=6&_ts=$ts&_r=$rnd',

      // strict global form with explicit user_id
      'https://anime-seek.com/fastapi/logs/scene?user_id=$userId&limit=6&order=desc&_ts=$ts&_r=$rnd',
      'https://anime-seek.com/fastapi/logs/scenes?user_id=$userId&limit=6&order=desc&_ts=$ts&_r=$rnd',

      // LAST: very loose forms (kept for backend variations)
      'https://anime-seek.com/fastapi/$userId/logs/scene?limit=6&order=desc&_ts=$ts&_r=$rnd',
      'https://anime-seek.com/fastapi/$userId/logs/scenes?limit=6&order=desc&_ts=$ts&_r=$rnd',
    ];

    for (final url in candidates) {
      try {
        final r = await http.get(Uri.parse(url), headers: noCache);
        if (r.statusCode == 200) {
          final body = r.body.isNotEmpty ? json.decode(r.body) : [];
          var list = _unwrapList(body);
          if (list.isEmpty) list = _firstListOfMaps(body);
          if (list.isNotEmpty) return list;
        }
      } catch (_) {/* try next */}
    }

    if (!allowProfileFallback) return const <Map<String, dynamic>>[];

    // embedded fallback (stale)
    final embedded = (() {
      for (final k in ['scene_history','recent_scene_history','scenes','recentScenes']) {
        final v = _profile?[k];
        if (v is List) return v.whereType<Map>().toList();
      }
      return const <Map>[];
    })();

    return embedded.map((e) => Map<String, dynamic>.from(e)).toList();
  }





  Future<void> _loadProfileSongFor(int userId) async {
    try {
      final headers = await AuthService.authHeaders;
      if (!mounted) return;

      final r = await http.get(
        Uri.parse('https://anime-seek.com/fastapi/music/user/$userId'),
        headers: {...headers, 'Accept': 'application/json'},
      );
      if (!mounted) return;

      if (r.statusCode == 200 && r.body.isNotEmpty) {
        final m = json.decode(r.body);
        if (!mounted) return;
        if (m is Map<String, dynamic>) {
          _ss(() => _profileSong = _normalizeSongMap(m));
        } else {
          _ss(() => _profileSong = null);
        }
      } else {
        if (!mounted) return;
        _ss(() => _profileSong = null);
      }
    } catch (_) {
      // leave as-is on errors
    }
  }



  Map<String, dynamic> _normalizeSongMap(Map<String, dynamic> s) {
    final image = (s['image'] ?? s['artwork_url'] ?? '').toString();
    final name = (s['name'] ?? s['title'] ?? '').toString();
    final artists = (s['artists'] ?? s['artist'] ?? '').toString();
    return {
      ...s,
      'image': image,
      'name': name,
      'artists': artists,
    };
  }

  List<dynamic> _normalizeFavList(dynamic raw) {
    if (raw == null) return const [];
    if (raw is List) return raw;
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final d = json.decode(raw);
        if (d is List) return d;
      } catch (_) {}
    }
    return const [];
  }
  Future<List<Map<String, dynamic>>> _fetchRecentAudio(int userId) async {
    final headers = await AuthService.authHeaders;
    final noCache = {...headers, 'Accept':'application/json','Cache-Control':'no-cache, no-store, must-revalidate','Pragma':'no-cache'};
    final ts  = DateTime.now().millisecondsSinceEpoch;
    final rnd = Random().nextInt(1 << 30);

    final candidates = <String>[
      // users/{id}
      'https://anime-seek.com/fastapi/users/$userId/logs/audio?limit=6&order=desc&_ts=$ts&_r=$rnd',
      'https://anime-seek.com/fastapi/users/$userId/logs/audios?limit=6&order=desc&_ts=$ts&_r=$rnd',
      'https://anime-seek.com/fastapi/users/$userId/recent-audio?limit=6&_ts=$ts&_r=$rnd',
      // {id}
      'https://anime-seek.com/fastapi/$userId/logs/audio?limit=6&order=desc&_ts=$ts&_r=$rnd',
      'https://anime-seek.com/fastapi/$userId/logs/audios?limit=6&order=desc&_ts=$ts&_r=$rnd',
      // global typed
      'https://anime-seek.com/fastapi/logs/audio?user_id=$userId&limit=6&order=desc&_ts=$ts&_r=$rnd',
      'https://anime-seek.com/fastapi/logs/audios?user_id=$userId&limit=6&order=desc&_ts=$ts&_r=$rnd',
      'https://anime-seek.com/fastapi/logs?type=audio&user_id=$userId&limit=6&order=desc&_ts=$ts&_r=$rnd',
    ];

    for (final url in candidates) {
      try {
        final r = await http.get(Uri.parse(url), headers: noCache);
        if (r.statusCode == 200) {
          final list = _unwrapList(r.body.isNotEmpty ? json.decode(r.body) : []);
          if (list.isNotEmpty) return list;
        }
      } catch (_) {/* try next */}
    }
    return const <Map<String, dynamic>>[];
  }



  bool _deepEqualListMap(List<Map<String, dynamic>> a, List<Map<String, dynamic>> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (!const DeepCollectionEquality().equals(a[i], b[i])) return false;
    }
    return true;
  }

  void _startRecentPolling(int userId) {
    _poll?.cancel();
    _loadRecent(userId, allowProfileFallback: true); // allow embedded/profile fallback
    _poll = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      _loadRecent(userId, allowProfileFallback: true);
    });
  }

  Future<List<Map<String, dynamic>>> _fetchActivity(int userId, {int limit = 6}) async {
    final headers = await AuthService.authHeaders;
    final noCache = {
      ...headers,
      'Accept': 'application/json',
      'Cache-Control': 'no-cache, no-store, must-revalidate',
      'Pragma': 'no-cache',
    };

    final ts  = DateTime.now().millisecondsSinceEpoch;
    final rnd = Random().nextInt(1 << 30);

    final isMe = (_meId != null && userId == _meId);

    // Try user endpoint first; if you’re viewing yourself, also try /users/me/activity
    final endpoints = <String>[
      'https://anime-seek.com/fastapi/users/$userId/activity?limit=$limit&_ts=$ts&_r=$rnd',
      if (isMe) 'https://anime-seek.com/fastapi/users/me/activity?limit=$limit&_ts=$ts&_r=$rnd',
    ];

    for (final url in endpoints) {
      try {
        final r = await http.get(Uri.parse(url), headers: noCache);

        print('[activity] GET $url -> ${r.statusCode}  len=${r.body.length}');

        if (r.statusCode == 200) {
          if (r.body.isEmpty) return const <Map<String, dynamic>>[];
          final decoded = json.decode(r.body);
          if (decoded is List) {
            return decoded
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          }
          // if backend ever wraps the list
          final fromUnwrap = _unwrapList(decoded, keys: const ['items','data','results','list','rows','logs']);
          if (fromUnwrap.isNotEmpty) return fromUnwrap;
          final fromDeep = _firstListOfMaps(decoded);
          if (fromDeep.isNotEmpty) return fromDeep;
          return const <Map<String, dynamic>>[];
        } else if (r.statusCode == 204) {
          return const <Map<String, dynamic>>[];
        } else {
          // ignore: avoid_print
          print('[activity] non-200 ${r.statusCode}: ${r.body}');
          // Try next endpoint
        }
      } catch (e) {
        // ignore: avoid_print
        print('[activity] error: $e');
      }
    }

    return const <Map<String, dynamic>>[];
  }

  Future<void> _loadRecent(int targetId, {bool allowProfileFallback = true}) async {
    // 1) Prefer the activity endpoint (api_key-aware on backend)
    final activity = await _fetchActivity(targetId, limit: 6);

    List<Map<String, dynamic>> scenes;
    List<Map<String, dynamic>> audio;

    if (activity.isNotEmpty) {
      // Keep successes; drop hard failures
      final ok = activity
          .map((e) => Map<String, dynamic>.from(e))
          .where((m) {
        final code = _toInt(m['code']);
        return code == 0 || code < 400; // treat 0/200 as success; ignore 4xx/5xx
      })
          .toList();

      bool _isScene(Map m) {
        final t = (m['search_type'] ?? m['type'] ?? m['log_type'] ?? '').toString().toLowerCase();
        if (t.isNotEmpty) return t == 'scene';
        // Heuristic: rows with song_id but no anime_id likely audio
        final hasSong = _toInt(m['song_id']) > 0;
        final hasAni  = _toInt(m['anime_id']) > 0;
        if (hasSong && !hasAni) return false;
        return true; // default to scene
      }

      scenes = ok.where(_isScene).toList();
      audio  = ok.where((m) => !_isScene(m)).toList();
    } else {
      // 2) Fallback to legacy endpoints if activity returns nothing
      final scenesRaw = await _fetchRecentScenes(targetId, allowProfileFallback: allowProfileFallback);
      final audioRaw  = await _fetchRecentAudio(targetId);
      scenes = List<Map<String, dynamic>>.from(scenesRaw);
      audio  = List<Map<String, dynamic>>.from(audioRaw);
    }

    // Sort newest-first; support 'time' from your query as well
    int _cmpTs(Map a, Map b) {
      final ta = _tsMs(a['created_at'] ?? a['created'] ?? a['time'] ?? a['ts'] ?? a['timestamp'] ?? a['date']);
      final tb = _tsMs(b['created_at'] ?? b['created'] ?? b['time'] ?? b['ts'] ?? b['timestamp'] ?? b['date']);
      return tb.compareTo(ta);
    }
    scenes.sort(_cmpTs);
    audio.sort(_cmpTs);

    // SCENES (keep 3) — use AniList cover so the card never looks empty
    final mappedScenes = scenes
        .where((m) => _toInt(m['anime_id']) > 0) // require real anime_id
        .take(3)
        .map<Map<String, dynamic>>((m0) {
      final m = Map<String, dynamic>.from(m0);
      final aniId  = _toInt(m['anime_id']);
      final tsStr  = _pickStr(m, ['created_at','created','time','ts','timestamp','date']);
      final score  = _pickDouble(m, ['accuracy']) ?? 0.0;

      String title = _pickStr(m, [
        'anime_title','title','title_romaji','titleRomaji','title_english','titleEnglish'
      ]).trim();
      if (aniId > 0) {
        if (title.isNotEmpty) _titleCache[aniId] = title;
        if (title.isEmpty) title = (_titleCache[aniId] ?? '').toString().trim();
      }
      if (title.isEmpty) title = 'Scene Match';

      return {
        'type': 'scene',
        'ts': tsStr,
        'anime_id': aniId,
        'anime_title': title,
        'image_url': _aniCover(aniId), // ensures an image
        'episode': '',                 // not in logs schema
        'accuracy': score,
      };
    }).toList();

    // AUDIO (keep 3) — if anime_id exists, cover will show; otherwise image may be empty
    final mappedAudio = audio.take(3).map<Map<String, dynamic>>((m0) {
      final m = Map<String, dynamic>.from(m0);
      final aniId  = _toInt(m['anime_id']);
      final tsStr  = _pickStr(m, ['created_at','created','time','ts','timestamp','date']);
      final score  = _pickDouble(m, ['accuracy']) ?? 0.0;

      String animeTitle = _extractAnimeTitleDeep(m);
      if (aniId > 0) {
        if (animeTitle.isNotEmpty) _titleCache[aniId] = animeTitle;
        if (animeTitle.isEmpty)    animeTitle = (_titleCache[aniId] ?? '').toString().trim();
      }
      if (animeTitle.isEmpty) animeTitle = 'Audio Match';

      return {
        'type': 'audio',
        'ts': tsStr,
        'anime_id': aniId,
        'anime_title': animeTitle,
        'title': '',     // not present in logs table
        'subtitle': '',  // not present in logs table
        'image_url': aniId > 0 ? _aniCover(aniId) : '',
        'accuracy': score,
      };
    }).toList();

    final next = <Map<String, dynamic>>[...mappedScenes, ...mappedAudio];
    if (!mounted) return;
    if (next.isEmpty) return;

    if (!_deepEqualListMap(_recent, next)) {
      setState(() => _recent = next);
    }
  }

  bool _isSceneLog(Map m) {
    final t = (m['type'] ?? m['log_type'] ?? m['kind'] ?? '').toString().toLowerCase();
    if (t.contains('scene')) return true;
    if (t.contains('audio') || t.contains('song') || t.contains('music')) return false;
    // Heuristics:
    final hasFrame = [m['frame'], m['frame_url'], m['screenshot'], m['image_url']]
        .any((v) => v != null && v.toString().trim().isNotEmpty);
    final hasEpisode = [m['episode'], m['ep'], m['episode_number']]
        .any((v) => v != null && v.toString().trim().isNotEmpty);
    final hasArtist = [m['artist'], m['artists'], m['singer']]
        .any((v) => v != null && v.toString().trim().isNotEmpty);
    if (hasFrame || hasEpisode) return true;
    if (hasArtist) return false;
    // last resort: treat unknown as scene so it still shows
    return true;
  }

  Future<void> _saveProfileText() async {
    if (!_isOwner) return;
    final newHeadline = _headlineCtl.text.trim();
    final newBio = _bioCtl.text.trim();

    try {
      final headers = await AuthService.authHeaders;
      final req = http.MultipartRequest('PUT', Uri.parse('https://anime-seek.com/fastapi/users/me'))
        ..headers.addAll(headers)
        ..fields['top_line'] = newHeadline
        ..fields['bio'] = newBio;
      final res = await req.send();
      if (res.statusCode == 200 || res.statusCode == 204) {
        setState(() {
          _profile?['top_line'] = newHeadline;
          _profile?['bio'] = newBio;
        });
      }
    } catch (_) {
      // ignore toast for brevity
    }
  }

  // ---- LIKE / FOLLOW ----
  Future<void> _likeUser() async {
    if (_profile == null || _isOwner) return;
    try {
      final headers = await AuthService.authHeaders;
      final res = await http.post(
        Uri.parse('https://anime-seek.com/fastapi/users/${_profile!['id']}/like'),
        headers: {...headers, 'Accept': 'application/json'},
      );
      if (res.statusCode == 200) {
        final j = json.decode(res.body);
        final next = (j is Map && j['like_count'] is num)
            ? (j['like_count'] as num).toInt()
            : ((_profile?['like_count'] is num) ? (_profile!['like_count'] as num).toInt() + 1 : 1);
        setState(() => _profile!['like_count'] = next);
        showSnack(context, 'Liked user');
      } else {
        showSnack(context, 'Like failed (${res.statusCode})', error: true);
      }
    } catch (_) {
      showSnack(context, 'Network error', error: true);
    }
  }

  Future<void> _followUser() async {
    if (_profile == null || _isOwner) return;
    try {
      final headers = await AuthService.authHeaders;
      final res = await http.post(
        Uri.parse('https://anime-seek.com/fastapi/users/${_profile!['id']}/follow'),
        headers: {...headers, 'Accept': 'application/json'},
      );
      if (res.statusCode == 200) {
        final j = json.decode(res.body);
        final next = (j is Map && j['follower_count'] is num)
            ? (j['follower_count'] as num).toInt()
            : ((_profile?['follower_count'] is num) ? (_profile!['follower_count'] as num).toInt() + 1 : 1);
        setState(() {
          _profile!['follower_count'] = next;
          _profile!['is_following'] = true;
        });
        showSnack(context, 'Following user');
      } else if (res.statusCode == 409) {
        setState(() => _profile!['is_following'] = true);
        showSnack(context, 'You already follow this user');
      } else {
        showSnack(context, 'Follow failed (${res.statusCode})', error: true);
      }
    } catch (_) {
      showSnack(context, 'Network error', error: true);
    }
  }

  Future<void> _unfollowUser() async {
    if (_profile == null || _isOwner) return;
    try {
      final headers = await AuthService.authHeaders;
      final res = await http.delete(
        Uri.parse('https://anime-seek.com/fastapi/users/${_profile!['id']}/unfollow'),
        headers: {...headers, 'Accept': 'application/json'},
      );

      if (res.statusCode == 200) {
        setState(() {
          final curr = (_profile?['follower_count'] is num)
              ? (_profile!['follower_count'] as num).toInt()
              : 0;
          _profile!['follower_count'] = (curr - 1).clamp(0, 1 << 31);
          _profile!['is_following'] = false;
        });
        showSnack(context, 'Unfollowed user');
      } else if (res.statusCode == 409) {
        setState(() => _profile!['is_following'] = false);
        showSnack(context, "You're not following this user");
      } else {
        showSnack(context, 'Unfollow failed (${res.statusCode})', error: true);
      }
    } catch (_) {
      showSnack(context, 'Network error', error: true);
    }
  }


  // ---- AVATAR ----
  Future<void> _pickAndUploadAvatar() async {
    if (!_isOwner) return;

    final XFile? picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final file = File(picked.path);
    final bytes = await file.readAsBytes();

    // Process to square 512 jpg
    final src = img.decodeImage(bytes);
    if (src == null) return;
    final side = src.width < src.height ? src.width : src.height;
    final x = (src.width - side) ~/ 2;
    final y = (src.height - side) ~/ 2;
    final square = img.copyCrop(src, x: x, y: y, width: side, height: side);
    final resized = img.copyResize(square, width: 512, height: 512, interpolation: img.Interpolation.average);
    final outJpg = img.encodeJpg(resized, quality: 85);

    if (!mounted) return;
    setState(() => _avatarPreview = Uint8List.fromList(outJpg));

    // Upload
    final headers = await AuthService.authHeaders;
    if (!mounted) return;

    final req = http.MultipartRequest(
      'POST',
      Uri.parse('https://anime-seek.com/fastapi/users/me/upload-avatar'),
    )..headers.addAll(headers);

    req.files.add(http.MultipartFile.fromBytes(
      'file', outJpg,
      filename: 'avatar.jpg',
      contentType: MediaType('image', 'jpeg'),
    ));

    final res = await req.send();
    try { await res.stream.drain(); } catch (_) {}

    if (!mounted) return;

    if (res.statusCode >= 200 && res.statusCode < 300) {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final id = (_profile?['id'] as num?)?.toInt();

      // Build URLs (old/new) for cache eviction
      final oldRaw = (_profile?['avatar_url'] ?? '/uploads/user_avatars/user_${id ?? 0}.jpg').toString();
      final oldUrl = _absUrl(oldRaw.startsWith('/') ? oldRaw : '/$oldRaw', v: _avatarVBuster ?? (_profile?['avatar_updated_at'] as int?));
      final newPath = '/uploads/user_avatars/user_${id ?? 0}.jpg';
      final newUrl  = _absUrl(newPath, v: nowMs);

      try {
        await NetworkImage(oldUrl).evict();
        await NetworkImage(newUrl).evict();
      } catch (_) {}

      try {
        final headers = await AuthService.authHeaders;
        if (!mounted) return;
        final uid = widget.userId == 0 ? (_meId ?? 0) : widget.userId;
        final r = await http.get(
          Uri.parse('https://anime-seek.com/fastapi/users/$uid/posts/count'),
          headers: {...headers, 'Accept': 'application/json'},
        );
        if (!mounted) return;
        if (r.statusCode == 200) {
          final j = json.decode(r.body) as Map<String, dynamic>;
          setState(() => _postCount = (j['posts'] as num?)?.toInt() ?? 0);
        }
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _avatarVBuster = nowMs;
        if (_profile != null && id != null) {
          _profile!['avatar_url'] = newPath;
          _profile!['avatar_updated_at'] = nowMs;
        }
      });

      if (id != null) _ProfileCache.invalidate(id);

      // Give CDN a beat, then force refresh; keep memory preview until after
      Future.delayed(const Duration(milliseconds: 2200), () async {
        if (!mounted) return;
        await _bootstrap(force: true);
        if (!mounted) return;
        setState(() => _avatarPreview = null);
      });
    } else {
      if (!mounted) return;
      setState(() => _avatarPreview = null);
      showSnack(context, 'Avatar upload failed (${res.statusCode})', error: true);
    }
  }

  void _bustProfileCache() {
    final id = (_profile?['id'] is num) ? (_profile!['id'] as num).toInt() : null;
    if (id != null) _ProfileCache.invalidate(id);

  }


  // ---- PIN / CLEAR (new endpoints) ----
  Future<void> _setProfileSong(String trackId) async {
    try {
      final headers = await AuthService.authHeaders;
      if (!mounted) return;

      final r = await http.post(
        Uri.parse('https://anime-seek.com/fastapi/music/pin'),
        headers: {...headers, 'Content-Type': 'application/json'},
        body: json.encode({'track_id': trackId, 'country': 'US'}),
      );
      if (!mounted) return;

      if (r.statusCode == 200) {
        final j = json.decode(r.body);
        final ps = (j is Map && j['profile_song'] is Map) ? Map<String, dynamic>.from(j['profile_song']) : null;
        if (!mounted) return;
        if (ps != null) {
          _ss(() => _profileSong = _normalizeSongMap(ps));
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _maybeAutoplayProfileSong();
          });
        } else {
          await _bootstrap(); // fallback refresh
        }
      } else {
        if (!mounted) return;
        setState(() => _spotifyErr = 'Set song ${r.statusCode}: ${r.body}');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _spotifyErr = '$e');
    }
  }

  Future<void> _refresh() async {
    // ensure me is resolved first
    if (_meId == null) {
      final headers = await AuthService.authHeaders;
      try {
        final meRes = await http.get(Uri.parse('https://anime-seek.com/fastapi/auth/me'), headers: headers);
        if (meRes.statusCode == 200 && meRes.body.isNotEmpty) {
          _meId = _extractUserId(json.decode(meRes.body));
        }
      } catch (_) {}
    }

    final id = widget.userId == 0 ? (_meId ?? 0) : widget.userId;
    if (id != 0) _ProfileCache.invalidate(id);
    await _bootstrap(force: true);
  }

  Future<void> _clearProfileSong() async {
    try {
      final headers = await AuthService.authHeaders;
      if (!mounted) return;
      final r = await http.delete(
        Uri.parse('https://anime-seek.com/fastapi/music/me'),
        headers: {...headers, 'Accept': 'application/json'},
      );
      if (!mounted) return;
      if (r.statusCode == 200) _ss(() => _profileSong = null);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_profile == null && _loading) {
      return const Scaffold(
        backgroundColor: kBg,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        backgroundColor: kBg,
        appBar: _appBar(),
        body: Center(child: Text(_error!, style: const TextStyle(color: kSub))),
      );
    }
    if (_profile == null) {
      return Scaffold(
        backgroundColor: kBg,
        appBar: _appBar(),
        body: const Center(child: Text('Loading…', style: TextStyle(color: kSub))),
      );
    }

    return Scaffold(
      backgroundColor: kBg,
      appBar: _appBar(),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _saveIfNeededAndCollapse, // tap outside to save + collapse editors
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _headerCard()),
              SliverToBoxAdapter(child: _statsCard()),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
              SliverToBoxAdapter(child: _bioCard()),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
              SliverToBoxAdapter(child: _badgesCard()),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
              SliverToBoxAdapter(child: _favoritesCard(true)),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
              SliverToBoxAdapter(child: _favoritesCard(false)),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
              SliverToBoxAdapter(child: _recentCard()),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
              SliverToBoxAdapter(child: _musicCard()),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ),
        ),
      ),
    );
  }

  AppBar _appBar() => AppBar(
    backgroundColor: Colors.teal[900],
    title: const Text("Profile"),
    centerTitle: true,
  );

  Widget _headerCard() {
    final display = (_profile?['display_name'] ?? '').toString();
    final topLine = (_profile?['top_line'] ?? '').toString();
    final raw = (_profile?['avatar_url'] ?? '').toString();
    final avatarUpdatedAt = _avatarVBuster ?? (_profile?['avatar_updated_at'] as int?);
    final avatarUrl = _absUrl(
      (raw.isEmpty || raw == '/' || raw == 'null')
          ? '/uploads/user_avatars/default_avatar.jpg'
          : raw,
      v: avatarUpdatedAt,
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      decoration: _card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: _pickAndUploadAvatar,
            child: SizedBox(
              width: 112,
              height: 112,
              child: ClipOval(
                child: _avatarPreview != null
                    ? Image.memory(
                  _avatarPreview!,
                  key: const ValueKey('local-avatar'),
                  fit: BoxFit.cover,
                )
                    : Image.network(
                  avatarUrl,
                  key: ValueKey(avatarUrl),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(color: Colors.black12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            display,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(color: kText, fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          _headlineEditing
              ? TextField(
            controller: _headlineCtl,
            focusNode: _headlineFocus,
            autofocus: true,
            textAlign: TextAlign.center,
            style: const TextStyle(color: kText, fontWeight: FontWeight.w600),
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'Add a headline',
              hintStyle: TextStyle(color: kSub),
              border: UnderlineInputBorder(),
            ),
            onSubmitted: (_) => _saveIfNeededAndCollapse(),
          )
              : GestureDetector(
            onTap: () => setState(() => _headlineEditing = _isOwner),
            child: Text(
              topLine.isEmpty ? (_isOwner ? 'Tap to add headline' : '') : topLine,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(color: topLine.isEmpty ? kSub : kText, fontSize: 14),
            ),
          ),
          if (_profileSong != null) ...[
            const SizedBox(height: 10),
            const Text('Profile Song', style: TextStyle(color: kSub, fontSize: 12)),
            const SizedBox(height: 8),
            _profileSongTile(),
          ],
          const SizedBox(height: 12),
          if (!_isOwner)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _pillButton(Icons.thumb_up, 'Like', _likeUser),
                _pillButton(Icons.person_add, 'Follow', _followUser),
                _pillButton(Icons.person_remove, 'Unfollow', _unfollowUser),
              ],
            ),
        ],
      ),
    );
  }

  Future<T> _time<T>(String label, Future<T> f) async {
    final sw = Stopwatch()..start();
    try { return await f; }
    finally { debugPrint('[ProfilePage] $label ${sw.elapsedMilliseconds}ms'); }
  }
  Widget _statsCard() {
    String fmt(dynamic v) => v == null ? '0' : '$v';
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: _card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title('Stats'),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            runSpacing: 12,
            children: [
              _stat('Likes', fmt(_profile?['like_count'])),
              _stat('Followers', fmt(_profile?['follower_count'])),
              _stat('Following', fmt(_profile?['following_count'])),
              _stat('Rank', '#${fmt(_analytics?['userRank'])}'),
              _stat('Streak', '${fmt(_analytics?['longestStreakDays'])}d'),
              _stat('Audio S', fmt(_analytics?['totalAudioSearches'])),
              _stat('Audio M', fmt(_analytics?['successfulAudioMatches'])),
              _stat('Scene S', fmt(_analytics?['totalSceneSearches'])),
              _stat('Scene M', fmt(_analytics?['successfulSceneMatches'])),
              _stat('Posts', fmt(_postCount)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _badgesCard() {
    final colors = [
      const Color(0xFF2DD4BF),
      const Color(0xFFF59E0B),
      const Color(0xFF60A5FA),
      const Color(0xFF34D399),
      const Color(0xFFF472B6),
      const Color(0xFFEAB308),
      const Color(0xFFA78BFA),
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: _card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title('Badges'),
          const SizedBox(height: 10),
          if (_badges.isEmpty)
            _badgeChip('Getting Started', colors[2])
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (int i = 0; i < _badges.length; i++)
                  _badgeChip(_badgeText(_badges[i]), colors[i % colors.length]),
              ],
            ),
        ],
      ),
    );
  }

  String _badgeText(Map<String, dynamic> b) {
    final name = (b['name'] ?? '').toString();
    final desc = (b['description'] ?? '').toString();
    return desc.isEmpty ? name : '$name — $desc';
  }

  Widget _bioCard() {
    final bio = (_profile?['bio'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: _card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title('Bio'),
          const SizedBox(height: 8),
          _bioEditing
              ? TextField(
            controller: _bioCtl,
            autofocus: true,
            maxLines: 4,
            style: const TextStyle(color: kText),
            decoration: const InputDecoration(
              hintText: 'Write a short bio',
              hintStyle: TextStyle(color: kSub),
              border: UnderlineInputBorder(),
            ),
            onSubmitted: (_) => _saveIfNeededAndCollapse(),
          )
              : GestureDetector(
            onTap: () => setState(() => _bioEditing = _isOwner),
            child: Text(
              bio.isEmpty ? (_isOwner ? 'Tap to add bio' : '') : bio,
              style: TextStyle(color: bio.isEmpty ? kSub : kText, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _favoritesCard(bool anime) {
    final list = anime ? _favAnime : _favChars;
    final title = anime ? 'Top 3 Favorite Anime' : 'Top 3 Favorite Characters';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: _card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title(title),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, c) {
              const gap = 8.0;
              final tileW = (c.maxWidth - gap * 2) / 3;

              List<Widget> tiles = [];
              for (int i = 0; i < 3; i++) {
                final entry = i < list.length ? list[i] : null;
                final url = _favoriteImageUrl(entry, index: i, isAnime: anime);

                tiles.add(
                  GestureDetector(
                    onTap: _isOwner ? () => _pickAndSaveFavorite(index: i, isAnime: anime) : null,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: url == null
                          ? Container(
                        width: tileW,
                        height: tileW,
                        color: Colors.grey[800],
                        child: const Icon(Icons.add_photo_alternate, color: Colors.white),
                      )
                          : Image.network(
                        url,
                        width: tileW,
                        height: tileW,
                        fit: BoxFit.cover,
                        headers: _headersForUrl(url), // ← important
                        errorBuilder: (_, __, ___) => Container(
                          width: tileW,
                          height: tileW,
                          color: Colors.grey[800],
                          child: const Icon(Icons.broken_image, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                );
                if (i < 2) tiles.add(const SizedBox(width: gap));
              }

              return Row(children: tiles);
            },
          )
        ],
      ),
    );
  }

  Future<void> _pickAndSaveFavorite({required int index, required bool isAnime}) async {
    final XFile? imgx = await _picker.pickImage(source: ImageSource.gallery);
    if (imgx == null) return;

    final file = File(imgx.path);
    final size = await file.length();
    final lower = file.path.toLowerCase();
    if (size > 5 * 1024 * 1024 || !(lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png'))) {
      return;
    }

    try {
      final headers = await AuthService.authHeaders;
      final req = http.MultipartRequest(
        'POST',
        Uri.parse('https://anime-seek.com/fastapi/users/${_profile!['id']}/upload-favorite-image'),
      )
        ..headers.addAll(headers)
        ..fields['index'] = index.toString()
        ..fields['type']  = isAnime ? 'anime' : 'character'
        ..files.add(await http.MultipartFile.fromPath('file', file.path));

      final res = await req.send();
      final body = await res.stream.bytesToString(); // read body once

      if (res.statusCode == 200) {
        int vNow = DateTime.now().millisecondsSinceEpoch;
        try {
          final j = json.decode(body);
          final imageUrl  = (j is Map ? (j['image_url'] ?? j['url'] ?? j['path'])?.toString() : null);
          final updatedAt = (j is Map && j['updated_at'] != null)
              ? (j['updated_at'] is num ? (j['updated_at'] as num).toInt() : int.tryParse('${j['updated_at']}'))
              : vNow;

          setState(() {
            final list = isAnime ? [..._favAnime] : [..._favChars];
            final entry = {
              'image_url': imageUrl ?? '',
              'updated_at': updatedAt ?? vNow,
            };
            while (list.length < 3) list.add(null);
            list[index] = entry;
            if (isAnime) _favAnime = list; else _favChars = list;
          });
        } catch (_) {}

        final id = (_profile?['id'] as num?)?.toInt();
        if (id != null) _ProfileCache.invalidate(id);
        await _bootstrap(force: true);
      } else {
        showSnack(context, 'Upload failed (${res.statusCode})', error: true);
      }
    } catch (_) {
      showSnack(context, 'Upload error', error: true);
    }
  }

  // Put this at CLASS SCOPE (not inside any widget/method)
  Future<Map<String, dynamic>?> _fetchAniById(int id) async {
    const endpoint = 'https://graphql.anilist.co';
    const query = r'''
    query($id: Int) {
      Media(id: $id, type: ANIME) {
        id
        title { romaji english native }
        description(asHtml: false)
        season
        seasonYear
        format
        genres
        tags { name }
        coverImage { large extraLarge medium }
      }
    }
  ''';

    final r = await http.post(
      Uri.parse(endpoint),
      headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
      body: json.encode({'query': query, 'variables': {'id': id}}),
    );

    if (r.statusCode != 200) return null;
    final media = (json.decode(r.body)['data']?['Media']) as Map?;
    if (media == null) return null;

    final cover = (media['coverImage'] ?? {}) as Map;
    final tags  = (media['tags'] ?? []) as List;

    return {
      'anilist_id': media['id'],
      'title': (media['title']?['english'] ?? media['title']?['romaji'] ?? media['title']?['native'] ?? '').toString(),
      'title_romaji': (media['title']?['romaji'] ?? '').toString(),
      'title_native': (media['title']?['native'] ?? '').toString(),
      'description': (media['description'] ?? '').toString(),
      'season': (media['season'] ?? '').toString(),
      'year': media['seasonYear'],
      'type': (media['format'] ?? '').toString(),
      'genres': List<String>.from(media['genres'] ?? const []),
      'tags': List<String>.from(tags.map((t) => (t as Map)['name']).whereType<String>()),
      'cover_url': (cover['large'] ?? cover['extraLarge'] ?? cover['medium'] ?? '').toString(),
    };
  }
  Future<Map<String, dynamic>?> _fetchAnalytics(int userId) async {
    final headers = await AuthService.authHeaders;
    final noCache = {
      ...headers,
      'Accept': 'application/json',
      'Cache-Control': 'no-cache, no-store, must-revalidate',
      'Pragma': 'no-cache',
    };
    final ts  = DateTime.now().millisecondsSinceEpoch;
    final rnd = Random().nextInt(1 << 30);

    // Try user endpoint first, then me-endpoint as a fallback (some APIs restrict analytics to /me)
    final endpoints = <String>[
      'https://anime-seek.com/fastapi/users/$userId/analytics?_ts=$ts&_r=$rnd',
      if (_meId != null && userId == _meId)
        'https://anime-seek.com/fastapi/me/analytics?_ts=$ts&_r=$rnd',
      if (_meId != null && userId == _meId)
        'https://anime-seek.com/fastapi/users/me/analytics?_ts=$ts&_r=$rnd',
    ];

    Map<String, dynamic>? bodyMap;

    for (final url in endpoints) {
      try {
        final r = await http.get(Uri.parse(url), headers: noCache);
        if (r.statusCode == 200 && r.body.isNotEmpty) {
          final decoded = json.decode(r.body);
          if (decoded is Map<String, dynamic>) {
            bodyMap = decoded;
            break;
          }
        }
      } catch (_) {/* try next */}
    }
    if (bodyMap == null) return null;

    // Unwrap common envelopes
    Map<String, dynamic> _unwrap(Map<String, dynamic> m) {
      for (final k in const ['analytics', 'data', 'result']) {
        final v = m[k];
        if (v is Map<String, dynamic>) return v;
      }
      return m;
    }
    final raw = _unwrap(bodyMap);

    num _pickNum(List<String> keys, [num fallback = 0]) {
      for (final k in keys) {
        final v = raw[k];
        if (v is num) return v;
        if (v is String) {
          final n = num.tryParse(v);
          if (n != null) return n;
        }
      }
      return fallback;
    }

    // Normalize into the camelCase keys your _statsCard() reads
    final normalized = <String, dynamic>{
      'userRank':              _pickNum(['userRank', 'user_rank', 'rank']),
      'longestStreakDays':     _pickNum(['longestStreakDays', 'longest_streak_days', 'streak_days']),
      'totalAudioSearches':    _pickNum(['totalAudioSearches', 'total_audio_searches', 'audio_searches']),
      'successfulAudioMatches':_pickNum(['successfulAudioMatches', 'successful_audio_matches', 'audio_matches']),
      'totalSceneSearches':    _pickNum(['totalSceneSearches', 'total_scene_searches', 'scene_searches']),
      'successfulSceneMatches':_pickNum(['successfulSceneMatches', 'successful_scene_matches', 'scene_matches']),
      // Add any other fields you show later, mapping snake_case -> camelCase here.
    };

    return normalized;
  }


  void _startAnalyticsPolling(int userId) {
    // reuse _poll or make a second timer; here we reuse with a separate one:
    _analyticsPoll?.cancel();
    _analyticsPoll = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!mounted) return;
      final latest = await _fetchAnalytics(userId);
      if (!mounted || latest == null) return;
      // Only update if changed
      if (!const DeepCollectionEquality().equals(_analytics, latest)) {
        setState(() => _analytics = latest);
        // Optionally refresh cache entry:
        final existing = _ProfileCache.get(userId);
        if (existing != null) {
          _ProfileCache.put(
            userId,
            _ProfileCacheEntry(
              profile: existing.profile,
              analytics: latest,
              badges: existing.badges,
              recent: existing.recent,
              favAnime: existing.favAnime,
              favChars: existing.favChars,
              profileSong: existing.profileSong,
              fetchedAtMs: existing.fetchedAtMs,
            ),
          );
        }
      }
    });
  }

  void _openAnimeDetailFromId(int aniId, {String? fallbackTitle}) async {
    if (aniId <= 0) return;

    // Optional loading overlay
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    Map<String, dynamic>? meta;
    try {
      meta = await _fetchAniById(aniId).timeout(const Duration(seconds: 6));
    } catch (_) {}

    if (mounted) Navigator.of(context).pop(); // close loader

    final title = (_titleCache[aniId] ?? fallbackTitle ?? 'Anime #$aniId').toString();
    final safe = <String, dynamic>{
      'anilist_id': aniId,
      'title': title,
      'title_romaji': title,
      'title_native': title,
      'description': 'No description available.',
      'season': '',
      'year': null,
      'type': '',
      'genres': const <String>[],
      'tags': const <String>[],
      'cover_url': _aniCover(aniId),
    };

    final merged = {...safe, ...?meta};

    // Provide both shapes your detail page reads
    final payload = {
      ...merged,
      'anime': Map<String, dynamic>.from(merged),
    };

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AnimeMatchDetailPage(anime: payload),
        settings: RouteSettings(name: 'anime-$aniId'),
      ),
    );
  }


  Widget _recentCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: _card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title('Recent Activity'),
          const SizedBox(height: 12),
          SizedBox(
            height: 130,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _recent.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final e = _recent[i];
                final isScene = (e['type'] ?? '') == 'scene';
                final aniId   = _toInt(e['anime_id']);

                final imgUrl = (e['image_url'] ?? '').toString().trim().isNotEmpty
                    ? (e['image_url'] as String)
                    : (aniId > 0 ? _aniCover(aniId) : '');

                String title = (e['anime_title'] ?? '').toString().trim();
                if (title.isEmpty) title = isScene ? 'Scene Match' : 'Audio Match';

                final sub = isScene
                    ? (e['episode'] != null && '${e['episode']}'.trim().isNotEmpty ? 'Ep ${e['episode']}' : '')
                    : [e['title'], e['subtitle']]
                    .where((x) => x != null && x.toString().trim().isNotEmpty)
                    .join(' — ');

                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _openAnimeDetailSmart(e), // works even without an ID
                    child: Container(
                      width: 130,
                      decoration: BoxDecoration(
                        color: kCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: kBorder),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AspectRatio(
                              aspectRatio: 4 / 3,
                              child: imgUrl.isEmpty
                                  ? Container(
                                color: Colors.grey[800],
                                alignment: Alignment.center,
                                child: const Icon(Icons.broken_image, color: Colors.white),
                              )
                                  : Image.network(
                                imgUrl,
                                fit: BoxFit.cover,
                                headers: _headersForUrl(imgUrl),
                                errorBuilder: (_, __, ___) => Container(
                                  color: Colors.grey[800],
                                  alignment: Alignment.center,
                                  child: const Icon(Icons.broken_image, color: Colors.white),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(10, 8, 10, 2),
                              child: Text(
                                title,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: kText, fontWeight: FontWeight.w700),
                              ),
                            ),
                            if (sub.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
                                child: Text(
                                  sub,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: kSub, fontSize: 12),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }


  Widget _musicCard() {
    final hasPinned = _profileSong != null;

    // Hide the whole card on other users when there's nothing to show
    if (!_isOwner && !hasPinned) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: _card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _title('Music'),
            ],
          ),

          if (_spotifyLoading)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: LinearProgressIndicator(),
            ),

          if (_spotifyErr != null && _isOwner)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_spotifyErr!, style: const TextStyle(color: kSub)),
            ),

          // Pinned song — visible to everyone if present
          if (hasPinned) ...[
            const SizedBox(height: 10),
            const Text('Profile Song', style: TextStyle(color: kSub, fontSize: 12)),
            const SizedBox(height: 8),
            _profileSongTile(),
          ],
          if (_isOwner) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.play_circle_outline, color: kSub, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Autoplay profile song',
                    style: TextStyle(color: kText, fontWeight: FontWeight.w600),
                  ),
                ),
                Switch(
                  value: _autoplayEnabled,
                  onChanged: _autoplayLoaded ? (v) => _setAutoplayEnabled(v) : null,
                  activeColor: kAccent,
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          // Owner-only: Search
          if (_isOwner && _spotifyLinked && !_spotifyLoading) ...[
            const SizedBox(height: 16),
    
            // ----- SEARCH -----
            const Text('Search tracks (Apple Music/iTunes)', style: TextStyle(color: kSub, fontSize: 12)),
            const SizedBox(height: 6),
            TextField(
              controller: _spotifySearchCtl,
              onChanged: (v) {
                setState(() {});       // ✅ forces suffixIcon to update immediately
                _onSearchChanged(v);   // your debounce/search logic
              },
              style: const TextStyle(color: kText),
              decoration: InputDecoration(
                hintText: 'Search songs or artists',
                hintStyle: const TextStyle(color: kSub),
                isDense: true,
                filled: true,
                fillColor: const Color(0xFF151618),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: kBorder),
                ),
                suffixIcon: _spotifySearchCtl.text.isEmpty
                    ? null
                    : IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.clear, color: kSub),
                  onPressed: () {
                    setState(() {
                      _spotifySearchCtl.clear();
                      _spotifySearchResults = const [];
                    });
                  },
                ),
              ),
            ),
            if (_spotifySearching)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(),
              ),

            if (!_spotifySearching &&
                _spotifySearchCtl.text.trim().isNotEmpty &&
                _spotifySearchResults.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('No tracks found', style: TextStyle(color: kSub)),
              ),

            if (_spotifySearchResults.isNotEmpty) ...[
              const SizedBox(height: 8),
              Column(
                children: List.generate(_spotifySearchResults.length.clamp(0, 10), (i) {
                  final t = _spotifySearchResults[i] as Map<String, dynamic>;
                  final id      = (t['id'] ?? '').toString();
                  final img     = (t['artwork_url'] ?? t['image'] ?? '').toString();
                  final name    = (t['title'] ?? t['name'] ?? '').toString();
                  final artist  = (t['artist'] ?? t['artists'] ?? '').toString();
                  final preview = (t['preview_url'] ?? '').toString();

                  Future<void> _togglePreview() async {
                    if (preview.isEmpty) return;
                    if (_playingPreview && _currentPreviewUrl == preview) {
                      await _stopPlayback();
                    } else {
                      await _playUrl(preview);
                    }
                  }

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: img.isEmpty
                              ? Container(width: 48, height: 48, color: Colors.grey[800])
                              : Image.network(img, width: 48, height: 48, fit: BoxFit.cover),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: kText, fontWeight: FontWeight.w600)),
                              Text(artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: kSub, fontSize: 12)),
                            ],
                          ),
                        ),
                        // Play preview if available
                        IconButton(
                          tooltip: preview.isEmpty
                              ? 'No preview'
                              : (_playingPreview && _currentPreviewUrl == preview
                              ? 'Stop preview'
                              : 'Play preview'),
                          onPressed: preview.isEmpty ? null : _togglePreview,
                          icon: Icon(
                            preview.isEmpty
                                ? Icons.music_note
                                : (_playingPreview && _currentPreviewUrl == preview
                                ? Icons.stop
                                : Icons.play_arrow),
                            color: preview.isEmpty ? kSub : kAccent,
                          ),
                        ),
                        // Pin
                        IconButton(
                          tooltip: 'Set as profile song',
                          onPressed: id.isEmpty ? null : () => _setProfileSong(id),
                          icon: const Icon(Icons.push_pin, color: kAccent),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ],
          ],
        ],
      ),
    );
  }
  void showSnack(BuildContext context, String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? Colors.red : null,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ---- Song tile (header) ----
  Widget _profileSongTile() {
    final s = _profileSong!;
    final img     = (s['image'] ?? s['artwork_url'] ?? '').toString();
    final name    = (s['name'] ?? s['title'] ?? '').toString();
    final artists = (s['artists'] ?? s['artist'] ?? '').toString();
    final preview = (s['preview_url'] ?? '').toString();
    final ext     = (s['external_url'] ?? '').toString();

    String _fmt(Duration d) {
      final m = d.inMinutes;
      final s = d.inSeconds % 60;
      return '$m:${s.toString().padLeft(2, '0')}';
    }

    Future<void> _onPlayPressed() async {
      if (preview.isEmpty) {
        final u = ext.isNotEmpty ? Uri.parse(ext) : null;
        if (u != null) await launchUrl(u, mode: LaunchMode.externalApplication);
        return;
      }
      await _playPreview();
    }


    Future<void> _onStopPressed() async {
      await _stopPlayback();
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: img.isEmpty
                    ? Container(width: 52, height: 52, color: Colors.grey[800])
                    : Image.network(img, width: 52, height: 52, fit: BoxFit.cover),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: kText, fontWeight: FontWeight.w700)),
                    Text(artists,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: kSub, fontSize: 12)),
                  ],
                ),
              ),
              if (_isOwner)
                IconButton(
                  tooltip: 'Remove',
                  onPressed: _clearProfileSong,
                  icon: const Icon(Icons.close, color: kSub),
                ),
            ],
          ),

          const SizedBox(height: 10),

          // Play / Stop controls
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _onPlayPressed,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Play preview'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kAccent,
                  minimumSize: const Size(88, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _playingPreview ? _onStopPressed : null,
                icon: const Icon(Icons.stop),
                label: const Text('Stop'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: kText,
                  side: const BorderSide(color: kBorder),
                  minimumSize: const Size(88, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
              const Spacer(),
              if (_currentPreviewUrl == preview && _playingPreview)
                const Icon(Icons.volume_up, color: kAccent),
            ],
          ),

          if (preview.isNotEmpty) ...[
            const SizedBox(height: 10),
            // Progress / scrubbing over the whole preview
            Row(
              children: [
                Text(_fmt(_pPos), style: const TextStyle(color: kSub, fontSize: 12)),
                Expanded(
                  child: Slider(
                    value: (_pDur.inMilliseconds == 0)
                        ? 0
                        : (_pPos.inMilliseconds / _pDur.inMilliseconds).clamp(0.0, 1.0),
                    onChanged: (v) async {
                      if (_pDur == Duration.zero) return;
                      final to = Duration(milliseconds: (v * _pDur.inMilliseconds).round());
                      await _player.seek(to);
                    },
                  ),
                ),
                Text(_fmt(_pDur), style: const TextStyle(color: kSub, fontSize: 12)),
              ],
            ),
          ],

          if (preview.isEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () {
                  final u = ext.isNotEmpty ? Uri.parse(ext) : null;
                  if (u != null) launchUrl(u, mode: LaunchMode.externalApplication);
                },
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open in Apple Music'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ========================= HELPERS =========================
  final Map<int, String> _titleCache = {};

  // Unwrap helpers (support { data: {...} }, { user: {...} }, etc.)
  Map<String, dynamic> _unwrap(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v is Map<String, dynamic>) return v;
    }
    return m;
  }


  int? _extractUserId(dynamic j) {
    int? toInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v);
      return null;
    }

    if (j is Map) {
      final paths = <dynamic>[
        j['id'],
        (j['user'] is Map ? (j['user'] as Map)['id'] : null),
        (j['data'] is Map ? (j['data'] as Map)['id'] : null),
        (j['profile'] is Map ? (j['profile'] as Map)['id'] : null),
        (j['data'] is Map && (j['data'] as Map)['user'] is Map ? ((j['data'] as Map)['user'] as Map)['id'] : null),
      ];
      for (final v in paths) {
        final n = toInt(v);
        if (n != null && n > 0) return n;
      }
    }
    return null;
  }

  // Robust profile extraction from /users/{id} payloads
  Map<String, dynamic> _extractProfileMap(dynamic pJson) {
    if (pJson is Map) {
      // Try obvious places first
      final candidates = <Map<String, dynamic>?>[
        Map<String, dynamic>.from(pJson),
        (pJson['user'] is Map) ? Map<String, dynamic>.from(pJson['user']) : null,
        (pJson['profile'] is Map) ? Map<String, dynamic>.from(pJson['profile']) : null,
        (pJson['data'] is Map) ? Map<String, dynamic>.from(pJson['data']) : null,
        (pJson['data'] is Map && (pJson['data'] as Map)['user'] is Map)
            ? Map<String, dynamic>.from((pJson['data'] as Map)['user'])
            : null,
        (pJson['user'] is Map && (pJson['user'] as Map)['profile'] is Map)
            ? Map<String, dynamic>.from((pJson['user'] as Map)['profile'])
            : null,
      ];
      for (final m in candidates) {
        if (m == null) continue;
        // consider it a profile if it has id or typical fields
        if (m.containsKey('id') ||
            m.containsKey('display_name') ||
            m.containsKey('top_line') ||
            m.containsKey('bio')) {
          return m;
        }
      }
      // fallback: nested "result"
      if (pJson['result'] is Map) {
        return Map<String, dynamic>.from(pJson['result']);
      }
    } else if (pJson is List && pJson.isNotEmpty && pJson.first is Map) {
      return Map<String, dynamic>.from(pJson.first as Map);
    }
    return <String, dynamic>{};
  }

  int? _extractAniListId(Map m) {
    // IMPORTANT: never fall back to plain 'id' (that’s usually the log id)
    for (final k in [
      'anilist_id','anilistId','aniListId',
      'anime_id',
      'media_id','mediaId', // <-- add these
      'ani_id','aniId',     // <-- and these if your backend emits them
    ]) {
      final n = _toInt(m[k]);
      if (n > 0) return n;
    }
    return null;
  }

  Future<int?> _resolveAniIdByTitle(String title) async {
    final q = title.trim();
    if (q.isEmpty) return null;

    const endpoint = 'https://graphql.anilist.co';
    const query = r'''
    query($q: String) {
      Page(perPage: 1) {
        media(search: $q, type: ANIME) { id }
      }
    }
  ''';

    try {
      final r = await http.post(
        Uri.parse(endpoint),
        headers: {'Content-Type': 'application/json','Accept':'application/json'},
        body: json.encode({'query': query, 'variables': {'q': q}}),
      );
      if (r.statusCode != 200 || r.body.isEmpty) return null;
      final data = json.decode(r.body);
      final list = (((data['data'] ?? {})['Page'] ?? {})['media'] ?? []) as List;
      if (list.isEmpty) return null;
      final id = (list.first as Map)['id'];
      return _toInt(id);
    } catch (_) {
      return null;
    }
  }

  /// Open from a recent-entry map, trying ID, then title lookup, then fallback.
  Future<void> _openAnimeDetailSmart(Map e) async {
    final initialId = _toInt(e['anime_id'] ?? e['anilist_id'] ?? e['anilistId'] ?? e['aniListId'] ?? e['animeId']);
    String title = _pickStr(e, ['anime_title','title','title_romaji','titleRomaji','title_english','titleEnglish']).trim();
    if (title.isEmpty) title = _extractAnimeTitleDeep(e).trim();

    int aniId = initialId;
    if (aniId <= 0 && title.isNotEmpty) {
      // show tiny loader while we resolve
      showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
      try {
        aniId = (await _resolveAniIdByTitle(title)) ?? 0;
      } finally {
        if (mounted) Navigator.of(context).pop();
      }
    }

    if (aniId > 0) {
      _openAnimeDetailFromId(aniId, fallbackTitle: title.isEmpty ? null : title);
      return;
    }

    // Last resort: open detail page with a title/cover only (no ID); still useful.
    final imgUrl = (e['image_url'] ?? '').toString().trim();
    final payload = {
      'anilist_id': 0,
      'title': title.isEmpty ? 'Anime' : title,
      'title_romaji': title,
      'title_native': title,
      'description': 'No description available.',
      'cover_url': imgUrl.isNotEmpty ? _absUrl(imgUrl) : '',
      'anime': <String, dynamic>{ // shape your detail page expects
        'anilist_id': 0,
        'title': title.isEmpty ? 'Anime' : title,
        'cover_url': imgUrl.isNotEmpty ? _absUrl(imgUrl) : '',
      },
    };

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AnimeMatchDetailPage(anime: payload),
        settings: const RouteSettings(name: 'anime-unknown'),
      ),
    );
  }

  int? _pickInt(Map m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) {
        final p = int.tryParse(v);
        if (p != null) return p;
      }
    }
    return null;
  }

  double? _pickDouble(Map m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v is double) return v;
      if (v is num) return v.toDouble();
      if (v is String) {
        final p = double.tryParse(v);
        if (p != null) return p;
      }
    }
    return null;
  }

  Map<String, String>? _headersForUrl(String url) {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    if (host.contains('anilist') || host.endsWith('anili.st') || host.endsWith('anilist.co') || host.endsWith('s4.anilist.co')) {
      return {
        'Referer': 'https://anilist.co/',
        'User-Agent': 'Mozilla/5.0 (Flutter; Mobile) AppleWebKit/537.36 (KHTML, like Gecko)',
      };
    }
    return null;
  }



  BoxDecoration _card() => BoxDecoration(
    color: kCard,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: kBorder),
    boxShadow: [
      BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 8, offset: const Offset(0, 4)),
    ],
  );

  Widget _title(String t) => Text(
    t,
    style: const TextStyle(color: kText, fontWeight: FontWeight.w700, fontSize: 16),
  );

  Widget _stat(String label, String value) => SizedBox(
    width: 100,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: const TextStyle(color: kText, fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: kSub, fontSize: 12)),
      ],
    ),
  );

  Widget _badgeChip(String text, Color color) {
    final max = MediaQuery.of(context).size.width - 64; // card padding slack
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: max),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.18),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star, size: 14, color: Colors.amber),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: kText, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pillButton(
  IconData icon,
  String label,
  Future<void> Function() onTap,
) =>
    OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: kText,
        side: const BorderSide(color: kAccent),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      onPressed: () {
        // fire-and-forget; button remains responsive
        unawaited(onTap());
      },
      icon: Icon(icon, size: 18, color: kAccent),
      label: Text(label),
    );

  String _pickStr(Map m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v != null && v.toString().trim().isNotEmpty) return v.toString();
    }
    return '';
  }

  int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  int _getAniId(Map m) {
    // Same rule: never use plain 'id' as an AniList media id
    for (final k in ['anilist_id', 'anilistId', 'aniListId', 'anime_id']) {
      final v = m[k];
      final asInt = _toInt(v);
      if (asInt > 0) return asInt;
    }
    return 0;
  }


  String _bestSceneImage(Map m) {
    final candidates = <String?>[
      m['frame']?.toString(),
      m['frame_url']?.toString(),
      m['image_url']?.toString(),
      m['screenshot']?.toString(),
      m['preview']?.toString(),
      m['thumbnail']?.toString(),
    ].whereType<String>().map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

    if (candidates.isEmpty) return '';
    final chosen = candidates.firstWhere((u) => !_isAniList(u), orElse: () => candidates.first);
    return _absUrl(chosen);
  }

  bool _isAniList(String url) => url.contains('anilist') || url.contains('img.anili.st');

// Use AniList's stable proxy (no extension -> no 404s)
  String _aniCover(int id) =>
      id > 0 ? 'https://img.anili.st/media/$id' : '';

  String _charImage(int id) =>
      id > 0 ? 'https://img.anili.st/character/$id' : '';



  String _absUrl(String u, {int? v}) {
    if (u.isEmpty) return u;
    final isAbs = Uri.tryParse(u)?.hasScheme ?? false;  // http/https/etc
    final full = isAbs ? u : 'https://anime-seek.com${u.startsWith('/') ? u : '/$u'}';
    if (v == null) return full;
    final uri = Uri.parse(full);
    return uri.replace(queryParameters: {...uri.queryParameters, 'v': '$v'}).toString();
  }


  String? _favoriteImageUrl(dynamic entry, {required int index, required bool isAnime}) {
    if (entry == null) return null;

    int? id;
    String? path;
    int? updatedAt;

    if (entry is num) {
      id = entry.toInt();
    } else if (entry is String) {
      final s = entry.trim();
      if (s.isEmpty) return null;
      if (RegExp(r'^\d+$').hasMatch(s)) {
        id = int.tryParse(s);
      } else {
        path = s;
      }
    } else if (entry is Map) {
      final m = Map<String, dynamic>.from(entry);
      // try explicit path first
      path = (m['image_url'] ?? m['image'] ?? m['url'] ?? m['path'] ?? m['src'] ?? '').toString().trim();
      final u = m['updated_at'];
      if (u is num) updatedAt = u.toInt();
      if (u is String) updatedAt = int.tryParse(u);

      // then try IDs commonly used by your backend
      for (final k in ['anilist_id', 'anilistId', 'anime_id', 'character_id', 'id']) {
        final n = _toInt(m[k]);
        if (n > 0) { id = n; break; }
      }
    } else {
      final s = entry.toString().trim();
      if (RegExp(r'^\d+$').hasMatch(s)) {
        id = int.tryParse(s);
      } else if (s.isNotEmpty) {
        path = s;
      }
    }

    // If we have an absolute/relative path, normalize
    if (path != null && path.isNotEmpty) {
      final abs = _absUrl(path);

      // ✅ Only add cache-buster if we have a stable updatedAt
      final host = (Uri.tryParse(abs)?.host ?? '').toLowerCase();
      if (host.endsWith('anime-seek.com')) {
        if (updatedAt != null) {
          final uri = Uri.parse(abs);
          final qp = Map<String, String>.from(uri.queryParameters)..['v'] = '$updatedAt';
          return uri.replace(queryParameters: qp).toString();
        }
        return abs;
      }
      return abs;
    }

    // Otherwise build AniList cover from ID
    if (id != null && id! > 0) {
      return isAnime ? _aniCover(id!) : _charImage(id!);
    }

    return null;
  }

}
