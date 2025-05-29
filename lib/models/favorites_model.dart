// lib/models/favorites_model.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks both matched‑song favorites and AniList anime favorites by ID,
/// with local persistence across app restarts.
class FavoritesModel extends ChangeNotifier {
  FavoritesModel() {
    _loadFromPrefs();
  }

  // --- SONG favorites storage ---
  final List<Map<String, dynamic>> _songFavorites = [];

  /// Read‑only view of your song favorites.
  List<Map<String, dynamic>> get songFavoritesList => List.unmodifiable(_songFavorites);

  /// True if the Map song is favorited.
  bool isSongFavorite(Map<String, dynamic> item) => _songFavorites.contains(item);

  /// Toggles a song favorite on/off.
  void toggleFavorite(Map<String, dynamic> item) {
    if (_songFavorites.contains(item)) {
      _songFavorites.remove(item);
    } else {
      _songFavorites.add(item);
    }
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

  /// Read‑only view of your AniList anime favorite IDs.
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
    // load songs
    final songJson = prefs.getString(_songKey);
    if (songJson != null) {
      try {
        final List decoded = jsonDecode(songJson);
        _songFavorites
          ..clear()
          ..addAll(decoded.cast<Map<String, dynamic>>());
      } catch (_) {}
    }
    // load anime IDs
    final List<String>? animeList = prefs.getStringList(_animeKey);
    if (animeList != null) {
      _animeFavoriteIds
        ..clear()
        ..addAll(animeList);
    }
    notifyListeners();
  }

  Future<void> _saveSongPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString(_songKey, jsonEncode(_songFavorites));
  }

  Future<void> _saveAnimePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setStringList(_animeKey, _animeFavoriteIds);
  }
}
