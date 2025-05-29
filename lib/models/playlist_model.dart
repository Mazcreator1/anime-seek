import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:collection/collection.dart';

const _kSongPlaylistsKey = 'song_playlists';
const _kAnimePlaylistsKey = 'anime_playlists';

class PlaylistsModel extends ChangeNotifier {
  final Map<String, List<Map<String, dynamic>>> _songPlaylists = {};
  final Map<String, List<Map<String, dynamic>>> _animePlaylists = {};

  // SONGS
  List<String> get songNames => _songPlaylists.keys.toList();
  List<Map<String, dynamic>> getSongsInPlaylist(String name) =>
      _songPlaylists[name] ?? [];

  Future<bool> createSongPlaylist(String name, List<Map<String, dynamic>> items) async {
    if (name.isEmpty || _songPlaylists.containsKey(name)) return false;
    _songPlaylists[name] = List.from(items);
    notifyListeners();
    await _save();
    return true;
  }

  Future<void> addSongs(String name, List<Map<String, dynamic>> items) async {
    if (!_songPlaylists.containsKey(name)) return;
    final existing = _songPlaylists[name]!;
    for (var item in items) {
      if (!existing.any((e) => const DeepCollectionEquality().equals(e, item))) {
        existing.add(item);
      }
    }
    notifyListeners();
    await _save();
  }

  /// **NEW**: remove one song from a given playlist
  Future<void> removeSongFromPlaylist(String name, Map<String, dynamic> item) async {
    if (!_songPlaylists.containsKey(name)) return;
    _songPlaylists[name]!
        .removeWhere((e) => const DeepCollectionEquality().equals(e, item));
    notifyListeners();
    await _save();
  }

  Future<void> deleteSongPlaylist(String name) async {
    _songPlaylists.remove(name);
    notifyListeners();
    await _save();
  }

  // ANIMES
  List<String> get animeNames => _animePlaylists.keys.toList();
  List<String> getAnimesInPlaylist(String name) {
    final raw = _animePlaylists[name];
    if (raw == null) return [];
    return raw
        .map((e) => e['id']?.toString())
        .whereType<String>()
        .toList();
  }

  Future<bool> createAnimePlaylist(String name, List<Map<String, dynamic>> items) async {
    if (name.isEmpty || _animePlaylists.containsKey(name)) return false;
    _animePlaylists[name] = List.from(items);
    notifyListeners();
    await _save();
    return true;
  }

  Future<void> addAnimes(String name, List<Map<String, dynamic>> items) async {
    if (!_animePlaylists.containsKey(name)) return;
    final existing = _animePlaylists[name]!;
    for (var item in items) {
      if (!existing.any((e) => const DeepCollectionEquality().equals(e, item))) {
        existing.add(item);
      }
    }
    notifyListeners();
    await _save();
  }

  /// **NEW**: remove one anime from a given playlist
  Future<void> removeAnimeFromPlaylist(String name, String id) async {
    if (!_animePlaylists.containsKey(name)) return;
    _animePlaylists[name]!
        .removeWhere((e) => e['id']?.toString() == id);
    notifyListeners();
    await _save();
  }

  Future<void> deleteAnimePlaylist(String name) async {
    _animePlaylists.remove(name);
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSongPlaylistsKey, json.encode(_songPlaylists));
    await prefs.setString(_kAnimePlaylistsKey, json.encode(_animePlaylists));
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final songData = prefs.getString(_kSongPlaylistsKey);
    final animeData = prefs.getString(_kAnimePlaylistsKey);
    if (songData != null) {
      final parsed = json.decode(songData) as Map<String, dynamic>;
      _songPlaylists
        ..clear()
        ..addEntries(parsed.entries.map((e) =>
            MapEntry(e.key, List<Map<String, dynamic>>.from(e.value))));
    }
    if (animeData != null) {
      final parsed = json.decode(animeData) as Map<String, dynamic>;
      _animePlaylists
        ..clear()
        ..addEntries(parsed.entries.map((e) =>
            MapEntry(e.key, List<Map<String, dynamic>>.from(e.value))));
    }
    notifyListeners();
  }
}
