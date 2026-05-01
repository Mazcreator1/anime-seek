// lib/widgets/post_composer_sheet.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

import '../models/post_draft.dart';
import '../services/auth_service.dart';

const String _backendBase = 'https://anime-seek.com/fastapi';
Uri _postsUri() => Uri.parse('$_backendBase/posts');

// Lightweight ext->MIME map so Discord/FastAPI get a proper content-type
String _mimeForFilename(String name) {
  final n = name.toLowerCase();
  if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'image/jpeg';
  if (n.endsWith('.png')) return 'image/png';
  if (n.endsWith('.gif')) return 'image/gif';
  if (n.endsWith('.webp')) return 'image/webp';
  if (n.endsWith('.heic') || n.endsWith('.heif')) return 'image/jpeg'; // normalize
  return 'image/jpeg';
}

Future<void> openPostComposer(BuildContext context, PostDraft draft) async {
  final controller = TextEditingController(text: draft.text ?? "");
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (_) {
      return Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: _ComposerBody(draft: draft, controller: controller),
      );
    },
  );
}

class _ComposerBody extends StatefulWidget {
  final PostDraft draft;
  final TextEditingController controller;
  const _ComposerBody({required this.draft, required this.controller});
  @override
  State<_ComposerBody> createState() => _ComposerBodyState();
}

class _ComposerBodyState extends State<_ComposerBody> {
  bool posting = false;
  String? error;

  // Customization state
  Color? _bg;
  File? _pickedImage;
  bool _spoiler = false;
  bool _canColor = false; // gated by tier
  String? _tierDebug;     // shows why disabled
  static const int _charLimit = 2000;

  @override
  void initState() {
    super.initState();
    _refreshTier();
  }

  bool _isColorAllowed(Map<String, dynamic> me) {
    final dynamicId = me['tier_id'] ?? me['subscription_tier_id'] ?? me['plan_id'];
    final int? tierId = (dynamicId is int) ? dynamicId : int.tryParse('${dynamicId ?? ''}');
    final tierName = (me['tier'] ?? me['subscription_tier'] ?? me['plan'] ?? '')
        .toString()
        .toLowerCase();

    final roles = (me['roles'] is List)
        ? (me['roles'] as List).map((e) => '$e'.toLowerCase()).toList()
        : const <String>[];

    final flags = <bool>[
      me['is_pro'] == true,
      me['is_premium'] == true,
      me['is_subscribed'] == true,
      (me['subscription'] is Map && (me['subscription']['active'] == true)),
      (me['entitlements'] is List &&
          (me['entitlements'] as List).any((e) =>
          '$e'.toLowerCase().contains('premium') || '$e'.toLowerCase().contains('pro'))),
      roles.any((r) => r.contains('pro') || r.contains('premium')),
      if (tierId != null) tierId >= 2,
      tierName.contains('pro') || tierName.contains('premium'),
    ];
    return flags.any((v) => v == true);
  }

  Future<void> _refreshTier() async {
    try {
      final resp = await AuthService.me(); // must carry auth
      if (resp.statusCode == 200) {
        final me = jsonDecode(resp.body) as Map<String, dynamic>;
        final allowed = _isColorAllowed(me);
        if (mounted) {
          setState(() {
            _canColor = allowed;
            _tierDebug = allowed
                ? "Color customization enabled"
                : "Requires Premium/Pro tier to change background color";
          });
        }
      } else if (resp.statusCode == 401) {
        if (mounted) {
          setState(() {
            _canColor = false;
            _tierDebug = "Sign in to use color customization";
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _canColor = false;
            _tierDebug = "Color option unavailable (auth/me ${resp.statusCode})";
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _canColor = false;
          _tierDebug = "Color option unavailable (network/auth issue)";
        });
      }
    }
  }

  // Bigger, varied palette (32 colors): dark neutrals + hues across the wheel
  static final List<Color> _palette = <Color>[
    const Color(0xFF111214), const Color(0xFF16181A), const Color(0xFF1E1F22), const Color(0xFF26282B),
    const Color(0xFF2F3136), const Color(0xFF383B40), const Color(0xFF40444B), const Color(0xFF4A4F57),
    // deep hues
    const Color(0xFF2D1B1E), const Color(0xFF331A23), const Color(0xFF311B2C), const Color(0xFF281F38),
    const Color(0xFF1F2442), const Color(0xFF182C46), const Color(0xFF12333F), const Color(0xFF10372E),
    // richer hues
    const Color(0xFF4B1E22), const Color(0xFF5A1F2C), const Color(0xFF5A1E46), const Color(0xFF4B225E),
    const Color(0xFF2C2F6B), const Color(0xFF1C3C71), const Color(0xFF11475F), const Color(0xFF0F4C3A),
    // accents (still darkish)
    const Color(0xFF5A3A22), const Color(0xFF60441F), const Color(0xFF56512A), const Color(0xFF2E5531),
    const Color(0xFF27554E), const Color(0xFF2A4E62), const Color(0xFF37445E), const Color(0xFF3E3E3E),
  ];

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final x = await picker.pickImage(source: ImageSource.gallery, maxWidth: 2000);
    if (x != null) setState(() => _pickedImage = File(x.path));
  }

  Future<void> _pickColor() async {
    if (!_canColor) return;
    Color chosen = _bg ?? _palette.first;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Background color'),
        content: SizedBox(
          width: 340,
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _palette.map((c) {
              final selected = (chosen.value == c.value);
              return InkWell(
                onTap: () => setState(() => chosen = c),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? Colors.white : Colors.white24,
                      width: selected ? 2 : 1,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () { setState(() => _bg = chosen); Navigator.pop(context); },
            child: const Text('Use color'),
          ),
        ],
      ),
    );
  }

  String? _bgAsHex() {
    if (_bg == null || !_canColor) return null;
    final rgb = _bg!.value.toRadixString(16).padLeft(8, '0').substring(2); // RRGGBB
    return '#$rgb';
  }

  // choose text color based on bg brightness
  Color _onBg(Color? c) {
    final bg = c ?? const Color(0xFF161617);
    final lum = bg.computeLuminance(); // 0=dark, 1=light
    return (lum < 0.5) ? Colors.white : Colors.black;
  }

  // ---------- image resolution helpers ----------
  Future<File?> _resolveLocalImageFile(PostDraft d) async {
    // 1) picked this session
    if (_pickedImage != null && await _pickedImage!.exists()) {
      return _pickedImage!;
    }

    // 2) draft.localImagePath (if your model has it)
    final local = (d.localImagePath ?? '').trim();
    if (local.isNotEmpty) {
      final path = local.startsWith('file://') ? Uri.parse(local).toFilePath() : local;
      final f = File(path);
      if (await f.exists()) return f;
    }

    // 3) draft.imageUrl could be a local path or file://
    final url = (d.imageUrl ?? '').trim();
    if (url.isNotEmpty) {
      if (url.startsWith('file://')) {
        final f = File(Uri.parse(url).toFilePath());
        if (await f.exists()) return f;
      }
      if (url.startsWith('/')) {
        final f = File(url);
        if (await f.exists()) return f;
      }
    }

    // 4) Remote http(s): download once to temp so backend/Discord get a real attachment
    if (url.startsWith('http://') || url.startsWith('https://')) {
      try {
        final resp = await http.get(Uri.parse(url));
        if (resp.statusCode >= 200 && resp.statusCode < 300 && resp.bodyBytes.isNotEmpty) {
          final tmpDir = await Directory.systemTemp.createTemp('postimg_');
          final guessMime = lookupMimeType(url) ?? 'image/jpeg';
          final ext = _extFromMime(guessMime);
          final fname = 'remote_${DateTime.now().millisecondsSinceEpoch}.$ext';
          final f = File(p.join(tmpDir.path, fname));
          await f.writeAsBytes(resp.bodyBytes);
          return f;
        }
      } catch (_) {/* ignore */}
    }

    return null;
  }

  String _extFromMime(String mime) {
    if (mime.contains('png')) return 'png';
    if (mime.contains('gif')) return 'gif';
    if (mime.contains('webp')) return 'webp';
    return 'jpg';
  }

  File? _draftLocalForPreview(PostDraft d) {
    // Mirror the resolver for preview without async
    if (_pickedImage != null && _pickedImage!.existsSync()) return _pickedImage!;
    final local = (d.localImagePath ?? '').trim();
    if (local.isNotEmpty) {
      final path = local.startsWith('file://') ? Uri.parse(local).toFilePath() : local;
      final f = File(path);
      if (f.existsSync()) return f;
    }
    final url = (d.imageUrl ?? '').trim();
    if (url.startsWith('file://')) {
      final f = File(Uri.parse(url).toFilePath());
      if (f.existsSync()) return f;
    }
    if (url.startsWith('/')) {
      final f = File(url);
      if (f.existsSync()) return f;
    }
    return null;
  }
  // ---------- end helpers ----------

  Future<void> _submit() async {
    setState(() {
      posting = true;
      error = null;
    });
    try {
      final uri = _postsUri();
      final req = http.MultipartRequest("POST", uri)
        ..followRedirects = true
        ..headers['Accept'] = 'application/json';

      final token = await AuthService.getToken();
      if (token == null || token.isEmpty) {
        setState(() => error = 'Not signed in.');
        return;
      }
      req.headers['Authorization'] = 'Bearer $token';

      // Required text
      final text = widget.controller.text.trim();
      req.fields['text'] = text;

      // Optional (color gated)
      final bg = _bgAsHex();
      if (bg != null && bg.isNotEmpty) req.fields['bg_color'] = bg;
      if (_spoiler) req.fields['is_spoiler'] = 'true';

      // ---------- attach image if present (picked OR existing local OR remote fetched) ----------
      final attach = await _resolveLocalImageFile(widget.draft);
      if (attach != null && await attach.exists()) {
        final path = attach.path;
        final mime = lookupMimeType(path) ?? _mimeForFilename(path);
        final filename = p.basename(path);

        req.files.add(
          await http.MultipartFile.fromPath(
            'image',         // FastAPI expects 'image'
            path,
            filename: filename,
            contentType: MediaType.parse(mime),
          ),
        );
      }

      final res = await req.send();
      final body = await res.stream.bytesToString();

      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (mounted) Navigator.of(context).pop();
        return;
      }

      final www = res.headers['www-authenticate'];
      String msg;
      try {
        final j = jsonDecode(body);
        msg = j is Map && j['detail'] != null ? j['detail'].toString() : body;
      } catch (_) {
        msg = body.isNotEmpty ? body : 'HTTP ${res.statusCode}';
      }
      if (res.statusCode == 401 || res.statusCode == 403) {
        msg = 'Auth failed (${res.statusCode}). ${www != null ? "WWW-Authenticate: $www. " : ""}$msg';
      }
      setState(() => error = 'Failed @ ${uri.toString()} → ${res.statusCode}\n$msg');
    } on SocketException {
      setState(() => error = 'Network error: could not reach ${_postsUri()}');
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.draft;
    final textLen = widget.controller.text.length;
    final previewBg = _bg ?? const Color(0xFF161617); // dark default
    final onBg = _onBg(previewBg); // auto light-on-dark

    final localPreviewFile = _draftLocalForPreview(d);

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text("New Post", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Spacer(),
              if (!posting) IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const SizedBox(height: 12),

          // Preview (auto text color)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: previewBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: onBg.withOpacity(0.1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (localPreviewFile != null || (d.imageUrl != null && d.imageUrl!.trim().isNotEmpty))
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: localPreviewFile != null
                        ? Image.file(localPreviewFile, height: 180, width: double.infinity, fit: BoxFit.cover)
                        : Image.network(
                      d.imageUrl!.trim(),
                      height: 180, width: double.infinity, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        height: 120,
                        alignment: Alignment.center,
                        color: Theme.of(context).colorScheme.surfaceVariant,
                        child: const Text('Image failed to load'),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                if (d.animeTitle != null || d.characterName != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      [
                        if (d.animeTitle != null) d.animeTitle,
                        if (d.characterName != null) "• ${d.characterName}",
                      ].whereType<String>().join(' '),
                      style: TextStyle(fontWeight: FontWeight.w600, color: onBg),
                    ),
                  ),
                Text(
                  widget.controller.text.isEmpty ? "Your text preview…" : widget.controller.text,
                  style: TextStyle(fontSize: 16, color: onBg),
                ),
                if (_spoiler)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('⚠️ Marked as spoiler', style: TextStyle(fontSize: 12, color: onBg)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Controls (color button gated)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Tooltip(
                message: _canColor ? 'Pick a background color' : (_tierDebug ?? 'Requires Premium/Pro'),
                child: ElevatedButton.icon(
                  icon: Icon(_canColor ? Icons.palette : Icons.lock),
                  label: Text(_canColor ? 'Color' : 'Color (Pro)'),
                  onPressed: _canColor ? _pickColor : null,
                ),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.image),
                label: Text(_pickedImage == null ? 'Add image' : 'Replace image'),
                onPressed: _pickImage,
              ),
              if (_pickedImage != null)
                OutlinedButton.icon(
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remove image'),
                  onPressed: () => setState(() => _pickedImage = null),
                ),
              FilterChip(
                label: const Text('Spoiler'),
                selected: _spoiler,
                onSelected: (v) => setState(() => _spoiler = v),
              ),
            ],
          ),
          if (!_canColor && _tierDebug != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.info_outline, size: 16),
                const SizedBox(width: 6),
                Flexible(child: Text(_tierDebug!, style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
              ],
            ),
          ],
          const SizedBox(height: 12),

          // Text entry (system theme colors; preview handles contrast)
          TextField(
            controller: widget.controller,
            maxLines: null,
            minLines: 3,
            onChanged: (_) => setState(() {}),
            maxLength: _charLimit,
            decoration: const InputDecoration(
              hintText: "Say something about this…",
              border: OutlineInputBorder(),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Text('$textLen/$_charLimit', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          ),

          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 12),

          // Post button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: posting ? null : _submit,
              child: Text(posting ? "Posting…" : "Post"),
            ),
          ),
        ],
      ),
    );
  }
}
