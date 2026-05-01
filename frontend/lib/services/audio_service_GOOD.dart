// lib/services/audio_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';               // ← ensure this import
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart';

class AudioService extends ChangeNotifier {
  // ─── Recorder & Players ────────────────────────────────────────────────────
  final AudioRecorder _recorder = AudioRecorder();   // ← use AudioRecorder()
  final AudioPlayer   _player   = AudioPlayer();
  final AudioPlayer   _sfxPlayer= AudioPlayer();

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

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  // ─── Match history & metadata ─────────────────────────────────────────────
  final List<Map<String, dynamic>> _matchHistory = [];
  List<Map<String, dynamic>> get matchHistory => List.unmodifiable(_matchHistory);

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
    _animeMetadata = null;
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

    // request/check permission
    if (!await _recorder.hasPermission()) {
      error = 'Microphone permission denied!';
      notifyListeners();
      return;
    }

    // build output path
    final dir = await getTemporaryDirectory();
    final out = '${dir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.wav';
    _path = out;

    // warm-up
    await Future.delayed(const Duration(milliseconds: 300));

    try {
      await _recorder.start(
        const RecordConfig(                             // ← first positional arg
          encoder: AudioEncoder.wav,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: out,                                      // ← named path
      );

      _recordStartTime = DateTime.now();
      _isRecording = true;
      title = info = error = null;
      _duration = Duration.zero;
      notifyListeners();

      // update duration every second
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
    await _recorder.stop();                            // ← instance stop()
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
    // …existing send & match logic unchanged…
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
    _recorder.dispose();                               // ← clean up recorder
    super.dispose();
  }
}
