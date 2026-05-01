import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/generated_character.dart';
import '../services/auth_service.dart';

class CharacterService {
  static const String baseUrl = 'https://anime-seek.com/fastapi';

  final http.Client _client;

  CharacterService({http.Client? client}) : _client = client ?? http.Client();

  Future<GeneratedCharacter> generateCharacter({
  required String prompt,
  required String style,
  required String artStyle,
  required String gender,
  required String hair,
  required String eyes,
  required String outfit,
  required String mood,
  }) async {
    final uri = Uri.parse('$baseUrl/character/generate');
    final headers = await AuthService.authHeaders;

    final body = {
      'prompt': prompt,
      'style': style,
      'gender': gender,
      'hair': hair,
      'eyes': eyes,
      'outfit': outfit,
      'mood': mood,
      'art_style': artStyle,
      'artStyle': artStyle,
    };

    final response = await _client.post(
      uri,
      headers: {
        ...headers,
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return GeneratedCharacter.fromJson(data);
    }

    throw Exception(
      'Failed to generate character (${response.statusCode}): ${response.body}',
    );
  }

  Future<List<GeneratedCharacter>> getHistory() async {
    final headers = await AuthService.authHeaders;

    final response = await _client.get(
      Uri.parse('$baseUrl/character/history'),
      headers: {
        ...headers,
        'Accept': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to load history (${response.statusCode}): ${response.body}',
      );
    }

    final List<dynamic> data = jsonDecode(response.body);
    return data
        .map((item) => GeneratedCharacter.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<GeneratedCharacter> updateFavorite({
    required int characterId,
    required bool isFavorite,
  }) async {
    final uri = Uri.parse('$baseUrl/character/$characterId/favorite');
    final headers = await AuthService.authHeaders;

    final response = await _client.patch(
      uri,
      headers: {
        ...headers,
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'is_favorite': isFavorite,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return GeneratedCharacter.fromJson(data);
    }

    throw Exception(
      'Failed to update favorite (${response.statusCode}): ${response.body}',
    );
  }

  void dispose() {
    _client.close();
  }
}