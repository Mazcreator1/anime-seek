import 'dart:convert';
import 'package:http/http.dart' as http;

class PlaylistService {
  static const String baseUrl = 'http://10.0.2.2:8015'; // Update IP if needed

  static Future<List<String>> getPlaylists() async {
    final resp = await http.get(Uri.parse('$baseUrl/playlists'));
    if (resp.statusCode == 200) {
      return List<String>.from(json.decode(resp.body));
    } else {
      throw Exception('Failed to fetch playlists');
    }
  }

  static Future<void> createPlaylist(String name) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/playlists'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'name': name}),
    );
    if (resp.statusCode != 200) throw Exception('Failed to create playlist');
  }

  static Future<void> addToPlaylist(String playlist, String songName, double duration) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/playlists/$playlist/add'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'song_name': songName, 'duration': duration}),
    );
    if (resp.statusCode != 200) throw Exception('Failed to add song to playlist');
  }

  static Future<void> removeFromPlaylist(String playlist, String songName) async {
    final resp = await http.delete(
      Uri.parse('$baseUrl/playlists/$playlist/remove'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'song_name': songName}),
    );
    if (resp.statusCode != 200) throw Exception('Failed to remove song from playlist');
  }
}
