import 'dart:convert';
import 'package:http/http.dart' as http;

Future<Map<String, dynamic>> fetchAniListMetadata(String anilistId) async {
  final query = '''
    query (\$id: Int) {
      Media(id: \$id, type: ANIME) {
        id
        title {
          romaji
          english
          native
        }
        coverImage {
          large
        }
        description(asHtml: false)
        episodes
        season
        seasonYear
        genres
        averageScore
      }
    }
  ''';

  final response = await http.post(
    Uri.parse('https://graphql.anilist.co'),
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    },
    body: json.encode({
      'query': query,
      'variables': {'id': int.tryParse(anilistId)},
    }),
  );

  if (response.statusCode == 200) {
    final Map<String, dynamic> data = json.decode(response.body);
    return data['data']['Media'] ?? {};
  } else {
    throw Exception('Failed to load AniList metadata');
  }
}
