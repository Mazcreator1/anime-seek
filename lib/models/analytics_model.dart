// lib/models/analytics_model.dart

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:anime_finder/services/auth_service.dart';

/// A single point in the confidence-over-time series.
class ConfidencePoint {
  final DateTime date;
  final double confidence;
  ConfidencePoint(this.date, this.confidence);
}

class AnalyticsModel extends ChangeNotifier {
  bool isLoading = false;

  // per-user stats
  int totalAudioSearches = 0;
  int successfulAudioMatches = 0;
  int totalSceneSearches = 0;
  int successfulSceneMatches = 0;
  int longestStreakDays = 0;
  double averageConfidence = 0.0;
  int playlistsCreated = 0;
  int userRank = 0;

  Map<String, int> topArtists = {};
  Map<DateTime, int> audioSearchesPerDay = {};
  Map<DateTime, int> sceneSearchesPerDay = {};
  Map<DateTime, int> matchesPerDay = {};
  List<ConfidencePoint> confidenceTrend = [];
  Map<String, int> genreDistribution = {};

  // global stats
  Map<String, int> topAnime = {};
  Map<String, int> topUsers = {};

  // hyperlinks from backend (title -> "/users/discover?q=123&page=1&per=24")
  Map<String, String> topAnimeLinks = {};

  // Use the shared Dio that already attaches tokens + refreshes on 401.
  final Dio _dio = AuthService.dio;

  // ---------------------------
  // Date handling (IMPORTANT)
  // ---------------------------
  //
  // Backend returns date strings like "YYYY-MM-DD".
  // DateTime.parse("YYYY-MM-DD") can lead to timezone/DST drift in charts
  // (e.g., showing the previous day) depending on how your chart library
  // interprets/normalizes DateTime.
  //
  // We parse date-only strings as LOCAL midnight with DateTime(y,m,d).
  //
  DateTime _parseLocalDateOnly(String s) {
    // Expecting "YYYY-MM-DD"
    final parts = s.split('-');
    if (parts.length != 3) {
      // Fallback: try DateTime.parse, but normalize to local date-only
      final dt = DateTime.tryParse(s);
      if (dt == null) return DateTime.now();
      return DateTime(dt.year, dt.month, dt.day);
    }
    final y = int.tryParse(parts[0]) ?? 1970;
    final m = int.tryParse(parts[1]) ?? 1;
    final d = int.tryParse(parts[2]) ?? 1;
    return DateTime(y, m, d); // LOCAL midnight (no UTC drift)
  }

  Map<DateTime, int> _parseDateSeries(dynamic raw) {
    if (raw is! List) return {};
    final out = <DateTime, int>{};
    for (final item in raw) {
      if (item is! Map) continue;
      final dateStr = item['date']?.toString();
      if (dateStr == null) continue;
      final count = (item['count'] as num?)?.toInt() ?? 0;
      out[_parseLocalDateOnly(dateStr)] = count;
    }
    return _sortedDateMap(out);
  }

  List<ConfidencePoint> _parseConfidenceSeries(dynamic raw) {
    if (raw is! List) return <ConfidencePoint>[];
    final out = <ConfidencePoint>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final dateStr = item['date']?.toString();
      if (dateStr == null) continue;
      final conf = ((item['confidence'] as num?) ?? 0).toDouble();
      out.add(ConfidencePoint(_parseLocalDateOnly(dateStr), conf));
    }
    out.sort((a, b) => a.date.compareTo(b.date));
    return out;
  }

  Map<DateTime, int> _sortedDateMap(Map<DateTime, int> input) {
    final entries = input.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return Map<DateTime, int>.fromEntries(entries);
  }

  // ---------------------------
  // Public helpers for charts/UI
  // ---------------------------

  /// Returns a contiguous daily series between [start] and [end] (inclusive),
  /// filling missing dates with 0 so charts look stable and user-friendly.
  Map<DateTime, int> filledSeries(Map<DateTime, int> series, DateTime start, DateTime end) {
    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(end.year, end.month, end.day);
    final out = <DateTime, int>{};

    var cur = s;
    while (!cur.isAfter(e)) {
      out[cur] = series[cur] ?? 0;
      cur = cur.add(const Duration(days: 1));
    }
    return _sortedDateMap(out);
  }

  /// Convenience: fill using the natural min/max range of the series.
  Map<DateTime, int> filledSeriesAuto(Map<DateTime, int> series) {
    if (series.isEmpty) return {};
    final keys = series.keys.toList()..sort();
    return filledSeries(series, keys.first, keys.last);
  }

  // ---------------------------
  // Fetch
  // ---------------------------

  /// Fetch from `/me/analytics` using AuthService.dio.
  /// IMPORTANT: AuthService.dio baseUrl is already ".../fastapi"
  Future<void> fetchStats() async {
    isLoading = true;
    notifyListeners();

    bool _disposed = false;

    @override
    void dispose() {
      _disposed = true;
      super.dispose();
    }

    try {
      final resp = await _dio.get<Map<String, dynamic>>('/me/analytics');
      final data = resp.data ?? <String, dynamic>{};

      // links
      final linksRaw = data['topAnimeLinks'];
      if (linksRaw is Map) {
        topAnimeLinks = linksRaw.map((k, v) => MapEntry(k.toString(), v.toString()));
      } else {
        topAnimeLinks = {};
      }

      // per-user stats
      totalAudioSearches = (data['totalAudioSearches'] as int?) ?? 0;
      successfulAudioMatches = (data['successfulAudioMatches'] as int?) ?? 0;
      totalSceneSearches = (data['totalSceneSearches'] as int?) ?? 0;
      successfulSceneMatches = (data['successfulSceneMatches'] as int?) ?? 0;
      longestStreakDays = (data['longestStreakDays'] as int?) ?? 0;
      averageConfidence = ((data['averageConfidence'] as num?) ?? 0).toDouble();

      playlistsCreated = (data['playlistsCreated'] as int?) ?? 0;
      userRank = (data['userRank'] as int?) ?? 0;

      // maps (defensive parsing)
      topArtists = Map<String, int>.from((data['topArtists'] as Map?) ?? const {});
      genreDistribution = Map<String, int>.from((data['genreDistribution'] as Map?) ?? const {});
      topAnime = Map<String, int>.from((data['topAnime'] as Map?) ?? const {});
      topUsers = Map<String, int>.from((data['topUsers'] as Map?) ?? const {});

      // date-series (LOCAL date-only parsing + sorting)
      sceneSearchesPerDay = _parseDateSeries(data['sceneSearchesPerDay']);
      audioSearchesPerDay = _parseDateSeries(data['audioSearchesPerDay']);
      matchesPerDay = _parseDateSeries(data['matchesPerDay']);

      // confidence trend (LOCAL date-only parsing + sorting)
      confidenceTrend = _parseConfidenceSeries(data['confidenceTrend']);
    } on DioException catch (err) {
      debugPrint(
        'Analytics fetch failed: status=${err.response?.statusCode} body=${err.response?.data}',
      );
    } catch (e) {
      debugPrint('Analytics fetch failed: $e');
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}