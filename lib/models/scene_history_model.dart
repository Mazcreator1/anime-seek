import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Represents a single scene-seeking history entry.
class SceneHistoryEntry {
  final int aniListId;
  final String title;
  final String coverUrl;
  final String episode;
  final String timeRange;
  final DateTime dateAdded;
  final int? updatedAt;

  SceneHistoryEntry({
    required this.aniListId,
    required this.title,
    required this.coverUrl,
    required this.episode,
    required this.timeRange,
    this.updatedAt,
    DateTime? dateAdded,
  }) : dateAdded = dateAdded ?? DateTime.now();

  factory SceneHistoryEntry.fromJson(Map<String, dynamic> json) =>
      SceneHistoryEntry(
        aniListId: json['aniListId'] as int,
        title: json['title'] as String,
        coverUrl: json['coverUrl'] as String,
        episode: json['episode'] as String,
        timeRange: json['timeRange'] as String,
        updatedAt: json['updatedAt'] is num ? (json['updatedAt'] as num).toInt() : null,
        dateAdded: DateTime.tryParse(json['dateAdded'] as String? ?? '') ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
    'aniListId': aniListId,
    'title': title,
    'coverUrl': coverUrl,
    'episode': episode,
    'timeRange': timeRange,
    'updatedAt': updatedAt,
    'dateAdded': dateAdded.toIso8601String(),
  };
}

/// Manages the list of scene-seeking history entries.
class SceneHistoryModel extends ChangeNotifier {
  String _apiScope = 'guest';
  final List<SceneHistoryEntry> _history = [];

  List<SceneHistoryEntry> get entries => List.unmodifiable(_history);

  void addEntry(SceneHistoryEntry e) => add(e);

  int _version = 0;
  int get version => _version;

  static const _defaultScope = 'guest';

  SceneHistoryModel() {
    _loadHistory();
  }

  Future<void> setActiveApiKeyScope(String? apiKey) async {
    final next = (apiKey == null || apiKey.isEmpty) ? _defaultScope : apiKey;
    if (_apiScope == next) return;

    _apiScope = next;
    await _loadHistory();
    notifyListeners();
  }

  String get _prefsKey => 'scene_history:$_apiScope';

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_prefsKey);
    _history.clear();

    if (jsonString != null) {
      try {
        final List<dynamic> decoded = json.decode(jsonString) as List<dynamic>;
        _history.addAll(
          decoded.map((e) => SceneHistoryEntry.fromJson(e as Map<String, dynamic>)),
        );
      } catch (err) {
        debugPrint("⚠️ Failed to load cached history: $err");
      }
    }

    // Keep most-recent interaction first (updatedAt falls back to dateAdded).
    _history.sort((a, b) {
      final an = a.updatedAt ?? a.dateAdded.millisecondsSinceEpoch;
      final bn = b.updatedAt ?? b.dateAdded.millisecondsSinceEpoch;
      return bn.compareTo(an);
    });

    _version++;
    notifyListeners();
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = json.encode(_history.map((e) => e.toJson()).toList());
    await prefs.setString(_prefsKey, jsonString);
  }

  Future<void> add(SceneHistoryEntry entry) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    // Upsert by (aniListId + episode + timeRange): update & move to top if exists.
    final idx = _history.indexWhere((e) =>
    e.aniListId == entry.aniListId &&
        e.episode == entry.episode &&
        e.timeRange == entry.timeRange);

    if (idx >= 0) {
      final existing = _history.removeAt(idx);
      _history.insert(
        0,
        SceneHistoryEntry(
          aniListId: existing.aniListId,
          title: entry.title.isNotEmpty ? entry.title : existing.title,
          coverUrl: entry.coverUrl.isNotEmpty ? entry.coverUrl : existing.coverUrl,
          episode: existing.episode,
          timeRange: existing.timeRange,
          dateAdded: existing.dateAdded, // preserve original add time
          updatedAt: now,                // bump recency
        ),
      );
    } else {
      _history.insert(
        0,
        SceneHistoryEntry(
          aniListId: entry.aniListId,
          title: entry.title,
          coverUrl: entry.coverUrl,
          episode: entry.episode,
          timeRange: entry.timeRange,
          dateAdded: entry.dateAdded,
          updatedAt: now,
        ),
      );
    }

    _version++;
    await _saveHistory();
    notifyListeners();
  }

  Future<void> clear() async {
    _history.clear();
    _version++;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    notifyListeners();
  }
}
