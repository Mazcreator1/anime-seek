// lib/models/favorites_model.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks both matched-song favorites and AniList anime favorites by ID,
/// with local persistence across app restarts.
class FavoritesModel extends ChangeNotifier {
  FavoritesModel() {
    _loadFromPrefs();
  }

  // --- SONG favorites storage ---
  final List<Map<String, dynamic>> _songFavorites = [];

  /// Read-only view of your song favorites.
  List<Map<String, dynamic>> get songFavoritesList =>
      List.unmodifiable(_songFavorites);

  /// Stable key for a song favorite: "<song_name>::<anime_id?>"
  String _songKeyOf(Map<String, dynamic> item) {
    final songName = (item['song_name'] ?? '').toString();
    final anime = (item['anime'] as Map<String, dynamic>?) ?? const {};
    final dynamic rawId = anime['id'];
    final animeId = rawId == null ? '' : rawId.toString();
    return '$songName::$animeId';
  }

  /// Returns true if a song (by stable key) is already favorited.
  bool isSongFavorite(Map<String, dynamic> item) {
    final key = _songKeyOf(item);
    return _songFavorites.any((m) => _songKeyOf(m) == key);
  }

  /// Returns true if (songName + animeId) is already favorited.
  bool isSongFavoriteByKey(String songName, String? animeId) {
    final want = '${songName}::${animeId ?? ''}';
    return _songFavorites.any((m) => _songKeyOf(m) == want);
  }

  /// Toggle a song favorite on/off (by stable key).
  void toggleSongFavorite(Map<String, dynamic> item) {
    final key = _songKeyOf(item);
    final idx = _songFavorites.indexWhere((m) => _songKeyOf(m) == key);
    if (idx >= 0) {
      _songFavorites.removeAt(idx);
    } else {
      _songFavorites.add(item);
    }
    _saveSongPrefs();
    notifyListeners();
  }

  /// Backward-compat: calls toggleSongFavorite.
  void toggleFavorite(Map<String, dynamic> item) => toggleSongFavorite(item);

  /// Remove a song by key parts.
  void removeSongByKey(String songName, String? animeId) {
    final want = '${songName}::${animeId ?? ''}';
    _songFavorites.removeWhere((m) => _songKeyOf(m) == want);
    _saveSongPrefs();
    notifyListeners();
  }

  /// Clears all song favorites.
  void clearSongFavorites() {
    _songFavorites.clear();
    _saveSongPrefs();
    notifyListeners();
  }

  // --- ANIME favorites storage by ID only ---
  final List<String> _animeFavoriteIds = [];

  /// Read-only view of your AniList anime favorite IDs.
  List<String> get animeFavoritesList => List.unmodifiable(_animeFavoriteIds);

  /// True if the given anime id is favorited.
  bool isAnimeFavorite(String id) => _animeFavoriteIds.contains(id);

  /// Toggles an anime favorite on/off by id.
  void toggleAnimeFavoriteById(String id) {
    if (_animeFavoriteIds.contains(id)) {
      _animeFavoriteIds.remove(id);
    } else {
      _animeFavoriteIds.add(id);
    }
    _saveAnimePrefs();
    notifyListeners();
  }

  /// Clears all anime favorites.
  void clearAnimeFavorites() {
    _animeFavoriteIds.clear();
    _saveAnimePrefs();
    notifyListeners();
  }

  /// General check: given a key (song name or anime ID), is it favorited?
  bool isFavorite(String key) {
    if (_songFavorites.any((m) => m['song_name']?.toString() == key)) return true;
    if (_animeFavoriteIds.contains(key)) return true;
    return false;
  }

  // --- Persistence ---
  static const _songKey = 'favorites_song_list';
  static const _animeKey = 'favorites_anime_ids';

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();

    // Load songs + dedupe by stable key
    final songJson = prefs.getString(_songKey);
    if (songJson != null) {
      try {
        final List decoded = jsonDecode(songJson);
        final List<Map<String, dynamic>> loaded =
        decoded.cast<Map<String, dynamic>>();
        final seen = <String>{};
        _songFavorites
          ..clear()
          ..addAll(loaded.where((m) {
            final k = _songKeyOf(m);
            if (seen.contains(k)) return false;
            seen.add(k);
            return true;
          }));
      } catch (_) {
        // ignore corrupt data
      }
    }

    // Load anime IDs + dedupe
    final List<String>? animeList = prefs.getStringList(_animeKey);
    if (animeList != null) {
      final deduped = animeList.toSet().toList();
      _animeFavoriteIds
        ..clear()
        ..addAll(deduped);
    }

    notifyListeners();
  }

  Future<void> _saveSongPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    // Deduplicate before saving (defensive)
    final seen = <String>{};
    final deduped = <Map<String, dynamic>>[];
    for (final m in _songFavorites) {
      final k = _songKeyOf(m);
      if (seen.add(k)) deduped.add(m);
    }
    prefs.setString(_songKey, jsonEncode(deduped));
  }

  Future<void> _saveAnimePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setStringList(_animeKey, _animeFavoriteIds.toSet().toList());
  }
}
