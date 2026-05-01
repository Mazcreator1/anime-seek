import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/scene_challenge.dart';
import 'auth_service.dart';

class SceneChallengeApi {
  static const String baseUrl = 'https://anime-seek.com/fastapi';

  static Future<Map<String, String>> _headers() async {
    final headers = await AuthService.authHeaders;
    return {
      'Content-Type': 'application/json',
      ...headers,
    };
  }

  static Future<SceneChallenge> getRandomChallenge() async {
    final response = await http.get(
      Uri.parse('$baseUrl/scene-challenge/random'),
      headers: await _headers(),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to load challenge: ${response.body}');
    }

    return SceneChallenge.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static Future<SceneChallengeSubmitResult> submitGuess({
    required int challengeId,
    required String guessedTitle,
    required int hintsUsed,
    required int? timeTakenMs,
    String mode = 'endless',
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/scene-challenge/$challengeId/submit'),
      headers: await _headers(),
      body: jsonEncode({
        'guessed_title': guessedTitle,
        'hints_used': hintsUsed,
        'time_taken_ms': timeTakenMs,
        'mode': mode,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to submit guess: ${response.body}');
    }

    return SceneChallengeSubmitResult.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }
}