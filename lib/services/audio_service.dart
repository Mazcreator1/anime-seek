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
import 'package:flutter/foundation.dart'; // ChangeNotifier
import 'package:anime_finder/services/auth_service.dart';

class AudioService extends ChangeNotifier {
  // ─── Recorder & Players ────────────────────────────────────────────────────
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer   _player   = AudioPlayer();
  final AudioPlayer   _sfxPlayer= AudioPlayer();

  int? _asInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

  // ─── State fields ─────────────────────────────────────────────────────────
  bool _isRecording = false;
  bool get isRecording => _isRecording;

  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  String? _path;
  bool get hasRecording => _path != null;

  String? title, info, error;

  Duration _duration = Duration.zero;
  String get fmtDuration => _fmt(_duration);

  Timer? _timer;
  DateTime? _recordStartTime;

  String? _currentTier;
  int? _remainingSearches;
  String? get currentTier => _currentTier;
  int? get remainingSearches => _remainingSearches;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  // ─── Match history & metadata ─────────────────────────────────────────────
  static const int _maxHistory = 20;

  final List<Map<String, dynamic>> _matchHistory = [];
  List<Map<String, dynamic>> get matchHistory => List.unmodifiable(_matchHistory);

  // NEW: a monotonically increasing version to drive UI rebuilds via context.select
  int _mhVer = 0;
  int get matchHistoryVersion => _mhVer;

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

  void clearAnimeMetadata() {
    _animeMetadata = null;
    notifyListeners();
  }

  Future<void> _loadHistoryFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('matchHistory');
    if (jsonString != null) {
      final List decoded = json.decode(jsonString);
      _matchHistory
        ..clear()
        ..addAll(decoded.cast<Map<String, dynamic>>());
      _mhVer++;               // NEW: signal UI that history loaded
      notifyListeners();
    }
  }

  Future<void> _saveMatchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('matchHistory', json.encode(_matchHistory));
  }

  // NEW: centralized helpers to mutate history and bump version
  Future<void> addMatch(Map<String, dynamic> match) async {
    _matchHistory.insert(0, match);
    if (_matchHistory.length > _maxHistory) {
      _matchHistory.removeLast();
    }
    _mhVer++;
    await _saveMatchHistory();
    notifyListeners();
  }

  Future<void> removeMatchAt(int index) async {
    if (index < 0 || index >= _matchHistory.length) return;
    _matchHistory.removeAt(index);
    _mhVer++;
    await _saveMatchHistory();
    notifyListeners();
  }

  Future<void> clearMatches() async {
    _matchHistory.clear();
    _mhVer++;
    await _saveMatchHistory();
    notifyListeners();
  }

  Future<void> startRecording() async {
    if (_isRecording) return;

    if (!await _recorder.hasPermission()) {
      error = 'Microphone permission denied!';
      notifyListeners();
      return;
    }
    void setTierInfo(String? tier, int? searches) {
      _currentTier = tier;
      _remainingSearches = searches;
      notifyListeners();
    }
    // 1) Configure session for low-latency speech
    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration.speech());
    await session.setActive(true);

    // 2) Prepare output path
    final dir = await getTemporaryDirectory();
    final out = '${dir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.wav';
    _path = out;

    // 3) Start recording *directly* at 22050 Hz mono WAV
    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          bitRate: 128000,
          sampleRate: 22050,         // <-- match backend to avoid conversion
        ),
        path: out,
      );
      _recordStartTime = DateTime.now();
      _isRecording = true;
      title = info = error = null;
      _duration = Duration.zero;
      notifyListeners();

      // 4) Kick off your timer for the UI
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
    await _recorder.stop();
    _timer?.cancel();
    _isRecording = false;
    notifyListeners();
  }

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

  void resetUI() {
    title = info = error = null;
    _path = null;
    _duration = Duration.zero;
    _animeMetadata = null;
    notifyListeners();
    _sfxPlayer.setAsset('sounds/success.mp3').then((_) => _sfxPlayer.play());
  }
  // lib/services/audio_service.dart  (inside class AudioService)

  Future<void> reloadHistoryFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('matchHistory');
    _matchHistory
      ..clear()
      ..addAll(jsonString == null
          ? const <Map<String, dynamic>>[]
          : (json.decode(jsonString) as List).cast<Map<String, dynamic>>());
    _mhVer++;
    notifyListeners();
  }

  Future<void> wipeMatchHistoryPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('matchHistory');
    _matchHistory.clear();
    _mhVer++;
    notifyListeners();
  }

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
      final uri = Uri.parse('https://anime-seek.com/fastapi/recognize');
      final req = http.MultipartRequest('POST', uri)
        ..files.add(await http.MultipartFile.fromPath('file', _path!));

      // attach auth headers from AuthService
      final headers = await AuthService.authHeaders;
      debugPrint('sendAudio() – headers: $headers');
      req.headers.addAll(headers);

      final resp = await req.send();
      final body = await resp.stream.bytesToString();

      if (resp.statusCode == 200) {
        final data = json.decode(body) as Map<String, dynamic>;
        // --- Store tier and remaining searches from backend ---
        _currentTier = data['tier']?.toString();
        _remainingSearches = _asInt(data['remaining_searches']);
        notifyListeners();

        if (data['status'] == 'match') {
          result = data['result'] as Map<String, dynamic>?;
        } else {
          error = 'No match found';
        }
      } else if (resp.statusCode == 429) {
        // --- Show daily limit error and tier info ---
        final data = json.decode(body) as Map<String, dynamic>;
        error = data['error'] ?? 'Daily search limit reached.';
        _currentTier = data['tier'] as String?;
        _remainingSearches = 0;
        notifyListeners();
      } else if (resp.statusCode == 401) {
        error = 'Unauthorized – please log in again.';
      } else if (resp.statusCode == 404) {
        error = 'Our library is growing—stay tuned and thank you for your patience!';
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
      final fullMatch = <String, dynamic>{
        'matched_at': DateTime.now().toIso8601String(),
        // NEW: add a timestamp for better uniqueness in UI de-dupe
        'ts': DateTime.now().millisecondsSinceEpoch,
        ...result,
      };

      // OLD (kept behavior), but routed through the new helper to bump version and persist:
      await addMatch(fullMatch);

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

      try {
        await _sfxPlayer.setAsset('sounds/success.mp3');
        await _sfxPlayer.play();
      } catch (_) {}

      notifyListeners();
    }
  }
}
