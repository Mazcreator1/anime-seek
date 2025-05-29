// lib/models/analytics_model.dart

import 'package:flutter/material.dart';

/// A single match’s record.
class MatchRecord {
  final DateTime date;
  final double confidence;    // 0–100
  final String artist;
  final List<String> genres;

  MatchRecord({
    required this.date,
    required this.confidence,
    required this.artist,
    required this.genres,
  });
}

/// A data point for the confidence‐trend chart.
class ConfidencePoint {
  final DateTime date;
  final double confidence;

  ConfidencePoint({required this.date, required this.confidence});
}

/// Provides all the analytics stats for a given DateTimeRange.
class AnalyticsModel extends ChangeNotifier {
  bool isLoading = false;
  int totalMatches = 0;
  int longestStreakDays = 0;
  double averageConfidence = 0.0;
  Map<String, int> topArtists = {};
  Map<String, int> genreDistribution = {};
  Map<DateTime, int> matchesPerDay = {};
  List<ConfidencePoint> confidenceTrend = [];

  /// Loads and computes all stats for [range], then notifies listeners.
  Future<void> fetchStats(DateTimeRange range) async {
    isLoading = true;
    notifyListeners();

    // 1) Load your real match‐history records in this date range:
    final List<MatchRecord> records = await _loadMatchRecords(range);

    // 2) Total matches
    totalMatches = records.length;

    // 3) Longest daily streak
    longestStreakDays = _computeLongestStreak(records);

    // 4) Average confidence
    averageConfidence = records.isEmpty
        ? 0.0
        : records.map((r) => r.confidence).reduce((a, b) => a + b) /
        records.length;

    // 5) Top artists
    topArtists = {};
    for (final r in records) {
      topArtists[r.artist] = (topArtists[r.artist] ?? 0) + 1;
    }

    // 6) Genre distribution
    genreDistribution = {};
    for (final r in records) {
      for (final g in r.genres) {
        genreDistribution[g] = (genreDistribution[g] ?? 0) + 1;
      }
    }

    // 7) Matches per day
    final Map<DateTime, int> perDay = {};
    for (final r in records) {
      final day = DateTime(r.date.year, r.date.month, r.date.day);
      perDay[day] = (perDay[day] ?? 0) + 1;
    }
    // ensure zero‐entry days
    for (var i = 0; i <= range.end.difference(range.start).inDays; i++) {
      final d = DateTime(range.start.year, range.start.month, range.start.day + i);
      perDay.putIfAbsent(d, () => 0);
    }
    // sort by date
    final sortedEntries = perDay.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    matchesPerDay = Map.fromEntries(sortedEntries);

    // 8) Confidence trend (average per day)
    final Map<DateTime, List<double>> confByDay = {};
    for (final r in records) {
      final day = DateTime(r.date.year, r.date.month, r.date.day);
      confByDay.putIfAbsent(day, () => []).add(r.confidence);
    }
    confidenceTrend = matchesPerDay.keys.map((day) {
      final list = confByDay[day] ?? [];
      final avg = list.isEmpty ? 0.0 : list.reduce((a, b) => a + b) / list.length;
      return ConfidencePoint(date: day, confidence: avg);
    }).toList();

    isLoading = false;
    notifyListeners();
  }

  /// Stub: replace with your data‐source fetch (DB, API, etc.).
  Future<List<MatchRecord>> _loadMatchRecords(DateTimeRange range) async {
    await Future.delayed(const Duration(milliseconds: 300)); // simulate
    return []; // TODO: return your actual list of MatchRecord
  }

  /// Computes the longest consecutive‐day streak in [records].
  int _computeLongestStreak(List<MatchRecord> records) {
    if (records.isEmpty) return 0;
    final sorted = [...records]..sort((a, b) => a.date.compareTo(b.date));
    int maxStreak = 1, curr = 1;
    for (var i = 1; i < sorted.length; i++) {
      final prevDay = DateTime(sorted[i - 1].date.year, sorted[i - 1].date.month, sorted[i - 1].date.day);
      final thisDay = DateTime(sorted[i].date.year, sorted[i].date.month, sorted[i].date.day);
      if (thisDay.difference(prevDay).inDays == 1) {
        curr++;
        maxStreak = curr > maxStreak ? curr : maxStreak;
      } else if (thisDay != prevDay) {
        curr = 1;
      }
    }
    return maxStreak;
  }
}
