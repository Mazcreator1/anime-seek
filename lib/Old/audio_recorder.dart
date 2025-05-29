import 'dart:io';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart';

class AudioRecorderWidget extends StatefulWidget {
  final Function(String title, String meta) onResult;

  const AudioRecorderWidget({Key? key, required this.onResult}) : super(key: key);

  @override
  _AudioRecorderWidgetState createState() => _AudioRecorderWidgetState();
}

class _AudioRecorderWidgetState extends State<AudioRecorderWidget> {
  final _record = AudioRecorder();
  String? _filePath;
  bool _isRecording = false;

  Future<void> startRecording() async {
    if (await _record.hasPermission()) {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/recording.m4a';

      await _record.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );

      setState(() {
        _filePath = path;
        _isRecording = true;
      });
    }
  }

  Future<void> stopRecordingAndSend() async {
    final path = await _record.stop();

    setState(() {
      _isRecording = false;
    });

    if (path != null) {
      await sendToBackend(File(path));
    }
  }

  Future<void> sendToBackend(File audioFile) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('http://10.0.2.2:8000/identify'), // Use 10.0.2.2 for Android emulator
    );
    request.files.add(await http.MultipartFile.fromPath('file', audioFile.path));

    final response = await request.send();
    if (response.statusCode == 200) {
      final resBody = await response.stream.bytesToString();
      final result = resBody.contains("anime_title") ? resBody : '{"anime_title":"Unknown","meta":"No match"}';

      final match = RegExp(r'"anime_title"\s*:\s*"([^"]+)"').firstMatch(result);
      final metaMatch = RegExp(r'"meta"\s*:\s*"([^"]+)"').firstMatch(result);

      widget.onResult(
        match?.group(1) ?? "Unknown",
        metaMatch?.group(1) ?? "No metadata",
      );
    } else {
      widget.onResult("Error", "Could not identify");
    }
  }

  @override
  void dispose() {
    _record.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ElevatedButton(
          onPressed: _isRecording ? stopRecordingAndSend : startRecording,
          child: Text(_isRecording ? "Stop & Identify" : "Record Audio"),
        ),
      ],
    );
  }
}
