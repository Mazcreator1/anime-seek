
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => AudioService(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Anime Finder',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.light(),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<AudioService>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Anime OP Finder'),
        centerTitle: true,
      ),
      body: GestureDetector(
        onVerticalDragEnd: (_) => svc.resetUI(),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  key: ValueKey<bool>(svc.isRecording),
                  onPressed: svc.isRecording ? svc.stopRecording : svc.startRecording,
                  icon: Icon(svc.isRecording ? Icons.stop : Icons.mic),
                  label: Text(svc.isRecording ? 'Stop Recording' : 'Start Recording'),
                ),
                const SizedBox(height: 16),
                AnimatedOpacity(
                  opacity: svc.isRecording ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    "⏺️ Recording: ${svc.fmtDuration}",
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
                const SizedBox(height: 24),
                if (svc.hasRecording) ...[
                  ElevatedButton(
                    onPressed: svc.isRecording || svc.isLoading ? null : svc.sendAudio,
                    child: svc.isLoading
                        ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : const Text('Send to Backend'),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: svc.isRecording || svc.isLoading ? null : svc.playRecording,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Play Recording'),
                  ),
                ],
                const SizedBox(height: 32),
                if (svc.title != null)
                  Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "🎬 Title: ${svc.title}",
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          if (svc.info != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                svc.info!,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: svc.confidencePercent >= 70
                                      ? Colors.green
                                      : svc.confidencePercent >= 40
                                      ? Colors.orange
                                      : Colors.red,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                if (svc.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: Text(
                      "⚠️ ${svc.error}",
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AudioService extends ChangeNotifier {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  final AudioPlayer _sfxPlayer = AudioPlayer();

  bool _isRecording = false;
  bool get isRecording => _isRecording;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _path;
  bool get hasRecording => _path != null;

  String? title;
  String? info;
  String? error;
  double confidencePercent = 0;

  Timer? _timer;
  Duration _duration = Duration.zero;
  String get fmtDuration => _fmt(_duration);
  DateTime? _startTime;

  Future<void> startRecording() async {
    if (await _recorder.hasPermission()) {
      final tmpPath = '${Directory.systemTemp.path}/recorded.wav';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 44100, bitRate: 128000),
        path: tmpPath,
      );

      _isRecording = true;
      _path = tmpPath;
      title = info = error = null;
      _duration = Duration.zero;
      _startTime = DateTime.now();
      notifyListeners();

      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        _duration = DateTime.now().difference(_startTime!);
        notifyListeners();
      });
    } else {
      error = "Microphone permission denied!";
      notifyListeners();
    }
  }

  Future<void> stopRecording() async {
    _timer?.cancel();
    if (!await _recorder.isRecording()) return;
    try {
      final resultPath = await _recorder.stop();
      _path = resultPath;
      _isRecording = false;
    } catch (e) {
      error = "Stopping recording failed: $e";
    }
    notifyListeners();
  }

  Future<void> sendAudio() async {
    if (_path == null) {
      error = 'No recording yet.';
      notifyListeners();
      return;
    }

    final file = File(_path!);
    if (!file.existsSync()) {
      error = 'File not found.';
      notifyListeners();
      return;
    }

    _isLoading = true;
    title = info = error = null;
    notifyListeners();

    final uri = Uri.parse('http://10.0.2.2:8015/recognize');
    try {
      final req = http.MultipartRequest('POST', uri)
        ..files.add(await http.MultipartFile.fromPath('file', _path!));
      final resp = await req.send();
      final body = await resp.stream.bytesToString();

      if (resp.statusCode == 200) {
        final data = json.decode(body);

        if (data['error'] != null) {
          title = 'No match found';
          info = "Reason: ${data['error']}";
        } else if (data['match'] != null && data['match'] != 'No match found') {
          title = data['match'];

          double matchScore = (data['match_score'] ?? 0.0);
          confidencePercent = matchScore;

          String uploadedDuration = data['uploaded_duration']?.toString() ?? 'N/A';
          String author = data['author'] ?? 'Unknown Artist';
          String streamingService = data['streaming_service'] ?? 'Unknown Platform';

          info = "🎯 Match Score: ${matchScore.toStringAsFixed(1)}%\n"
                 "📀 Duration: ${uploadedDuration}s\n"
                 "🎤 Artist: $author\n"
                 "🎧 Platform: $streamingService";

          await _sfxPlayer.play(AssetSource('sounds/success.mp3'));
        } else {
          title = 'No match found';
        }
      } else {
        error = 'Error ${resp.statusCode}: $body';
      }
    } catch (e) {
      error = 'Network error: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> playRecording() async {
    if (_path == null) return;
    try {
      await _player.play(DeviceFileSource(_path!));
    } catch (e) {
      error = 'Playback failed: $e';
      notifyListeners();
    }
  }

  void resetUI() {
    title = info = error = null;
    _path = null;
    _duration = Duration.zero;
    confidencePercent = 0;
    _sfxPlayer.play(AssetSource('sounds/katana_slash.mp3'));
    notifyListeners();
  }

  String _fmt(Duration d) => '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _timer?.cancel();
    _player.dispose();
    _sfxPlayer.dispose();
    super.dispose();
  }
}
