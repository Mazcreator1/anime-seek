// lib/services/audio_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';    // ← for file paths

class AudioService extends ChangeNotifier {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  final AudioPlayer _sfxPlayer = AudioPlayer();

  bool _isRecording = false;
  bool get isRecording => _isRecording;

  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  String? _path;
  String? title, info, error;
  bool get hasRecording => _path != null;

  Duration _duration = Duration.zero;
  String get fmtDuration => _fmt(_duration);
  Timer? _timer;
  DateTime? _recordStartTime;

  // ─── UI state ─────────────────────────────────────────────────────────────
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  // ─── Match history ────────────────────────────────────────────────────────
  final List<Map<String, dynamic>> _matchHistory = [];
  List<Map<String, dynamic>> get matchHistory => List.unmodifiable(_matchHistory);

  // ─── Currently displayed anime metadata ───────────────────────────────────
  Map<String, dynamic>? _animeMetadata;
  Map<String, dynamic>? get animeMetadata => _animeMetadata;

  AudioService() {
    _initAudioSession();
    _loadHistoryFromPrefs();
  }

  Future<void> _initAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration.music());
  }

  String _fmt(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

    /// Clears out any currently stored match metadata.
    void clearAnimeMetadata() {
        // TODO: if you keep current-match in a field, reset it here.
        // Stubbed as a no-op so it compiles:
        notifyListeners();
      }
  // ─── Persisted history ────────────────────────────────────────────────────
  Future<void> _loadHistoryFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('matchHistory');
    if (jsonString != null) {
      final List decoded = json.decode(jsonString);
      _matchHistory
        ..clear()
        ..addAll(decoded.cast<Map<String, dynamic>>());
      notifyListeners();
    }
  }

  Future<void> _saveMatchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('matchHistory', json.encode(_matchHistory));
  }

  // ─── Recording ─────────────────────────────────────────────────────────────
  Future<void> startRecording() async {
    if (_isRecording) return;

    if (!await _recorder.hasPermission()) {
      error = 'Microphone permission denied!';
      notifyListeners();
      return;
    }

    final dir = await getTemporaryDirectory();
    final out = '${dir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.wav';

    // warm-up
    await Future.delayed(const Duration(milliseconds: 300));

    try {
      await _recorder.start(
        path: out,                     // ← REQUIRED named parameter
        encoder: AudioEncoder.wav,
        bitRate: 128000,
        samplingRate: 44100,
      );

      _recordStartTime = DateTime.now();
      _isRecording = true;
      _path = out;
      title = info = error = null;
      _duration = Duration.zero;
      notifyListeners();

      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_recordStartTime != null) {
          _duration = DateTime.now().difference(_recordStartTime!);
          notifyListeners();
        }
      });
    } catch (e) {
      error = 'Failed to start recording: $e';
      notifyListeners();
    }
  }

  Future<void> stopRecording() async {
    if (!_isRecording) return;
    await _recorder.stop();             // no path here
    _timer?.cancel();
    _isRecording = false;
    notifyListeners();
  }

  // ─── Playback ──────────────────────────────────────────────────────────────
  Future<void> playRecording() async {
    if (_path == null || !File(_path!).existsSync()) {
      error = 'No recording to play.';
      notifyListeners();
      return;
    }
    if (_isPlaying) return;

    _isPlaying = true;
    notifyListeners();

    _player.playerStateStream.listen((ps) {
      if (ps.processingState == ProcessingState.completed) {
        _isPlaying = false;
        notifyListeners();
      }
    });

    try {
      await _player.setFilePath(_path!);
      await _player.play();
    } catch (e) {
      error = 'Playback failed: $e';
      _isPlaying = false;
      notifyListeners();
    }
  }

  // ─── Send to backend & match ──────────────────────────────────────────────
  Future<void> sendAudio() async {
    if (_path == null) {
      error = 'No recording yet.';
      notifyListeners();
      return;
    }

    _isLoading = true;
    title = info = error = null;
    notifyListeners();

    Map<String, dynamic>? result;
    try {
      final uri = Uri.parse('http://10.0.2.2:8043/recognize');
      final req = http.MultipartRequest('POST', uri)
        ..files.add(await http.MultipartFile.fromPath('file', _path!));
      final resp = await req.send();
      final body = await resp.stream.bytesToString();

      if (resp.statusCode == 200) {
        final data = json.decode(body) as Map<String, dynamic>;
        if (data['status'] == 'match') {
          result = data['result'] as Map<String, dynamic>?;
        } else {
          error = 'No match found';
        }
      } else {
        error = 'Server error ${resp.statusCode}';
      }
    } catch (e) {
      error = 'Network error: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }

    if (result != null) {
      // record to history  persist
      final fullMatch = <String, dynamic>{
        'matched_at': DateTime.now().toIso8601String(),
        ...result,
      };
      _matchHistory.insert(0, fullMatch);
      if (_matchHistory.length > 20) _matchHistory.removeLast();
      await _saveMatchHistory();

      final rawAnime = result['anime'] as Map<String, dynamic>?;

      if (rawAnime != null) {
        _animeMetadata = {
          'title': rawAnime['title'],
          'title_romaji': rawAnime['title_romaji'],
          'title_native': rawAnime['title_native'],
          'description': rawAnime['description'],
          'cover_url': rawAnime['cover_url'],
          'season': rawAnime['season'],
          'year': rawAnime['year'],
          'type': rawAnime['type'],
          'genres': List<String>.from(rawAnime['genres'] ?? []),
          'tags': List<String>.from(rawAnime['tags'] ?? []),
          'artist': result['artist'],
          'song_name': result['anime_song'],
          'op_ed_type': result['op_ed_type'],
          'preview_url': result['preview_url'],
          'youtube_url': result['youtube_url'],
          'spotify_url': result['spotify_url'],
          'video_url': result['video_url'],
        };
      } else {
        _animeMetadata = {
          'title': result['anime_title'],
          'description': null,
          'cover_url': null,
        };
      }

      // success SFX
      try {
        await _sfxPlayer.setAsset('sounds/success.mp3');
        await _sfxPlayer.play();
      } catch (_) {}

      notifyListeners();
    }
  }

  // ─── Reset UI ──────────────────────────────────────────────────────────────
  void resetUI() {
    title = info = error = null;
    _path = null;
    _duration = Duration.zero;
    _animeMetadata = null;
    notifyListeners();

    _sfxPlayer.setAsset('sounds/katana_slash.mp3').then((_) => _sfxPlayer.play());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _player.dispose();
    _sfxPlayer.dispose();
    super.dispose();
  }
}
