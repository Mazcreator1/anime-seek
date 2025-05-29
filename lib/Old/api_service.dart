import 'dart:convert';
import 'package:http/http.dart' as http;

const String baseUrl = 'http://10.0.2.2:8015'; // Adjust for your environment

class ApiService {
  static Future<List<dynamic>> fetchPlaylists() async {
    final res = await http.get(Uri.parse('$baseUrl/playlists'));
    if (res.statusCode == 200) {
      return json.decode(res.body);
    }
    throw Exception('Failed to load playlists');
  }

  static Future<List<dynamic>> fetchPlaylistSongs(int playlistId) async {
    final res = await http.get(Uri.parse('$baseUrl/playlists/$playlistId/songs'));
    if (res.statusCode == 200) {
      return json.decode(res.body);
    }
    throw Exception('Failed to load songs');
  }

  static Future<void> createPlaylist(String name) async {
    final res = await http.post(
      Uri.parse('$baseUrl/playlists'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'name': name}),
    );
    if (res.statusCode != 200) throw Exception('Failed to create playlist');
  }

  static Future<void> addSongToPlaylist(int playlistId, int songId) async {
    final res = await http.post(
      Uri.parse('$baseUrl/playlists/$playlistId/songs'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'song_id': songId}),
    );
    if (res.statusCode != 200) throw Exception('Failed to add song');
  }

  static Future<void> removeSongFromPlaylist(int playlistId, int songId) async {
    final res = await http.delete(
      Uri.parse('$baseUrl/playlists/$playlistId/songs/$songId'),
    );
    if (res.statusCode != 200) throw Exception('Failed to remove song');
  }
}
