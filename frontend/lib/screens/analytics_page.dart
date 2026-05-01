// lib/screens/analytics_page.dart

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math; // at top
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'; // for RenderRepaintBoundary
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'discover_page.dart';
import 'package:anime_finder/screens/anime_detail_page.dart';

import '../models/analytics_model.dart';

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({Key? key}) : super(key: key);

  @override
  _AnalyticsPageState createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  final GlobalKey _boundaryKey = GlobalKey();
  bool _showTop50Users = false;
  bool _showTop50Anime = false;
  

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AnalyticsModel>().fetchStats();
    });
  }
  Map<DateTime,int> _listToDayMap(List<dynamic> rows) {
    final m = <DateTime,int>{};
    for (final r in rows) {
      final d = DateTime.parse(r['date'] as String);
      m[d] = (r['count'] as num).toInt();
    }
    return m;
  }

  Future<void> _exportDashboard() async {
    try {
      final boundary = _boundaryKey.currentContext!
          .findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final byteData =
      await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();

      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/analytics_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes);

      await Share.shareFiles(
        [file.path],
        text: 'My Analytics',
      );
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error exporting: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = context.watch<AnalyticsModel>();
    final theme = Theme.of(context);

    // modern chart palette
    final chartColors = [
      Colors.tealAccent.shade700,
      Colors.deepPurpleAccent.shade200,
      Colors.orangeAccent.shade700,
      Colors.pinkAccent.shade200,
    ];

    if (m.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final audioRate = m.totalAudioSearches == 0
        ? 0
        : m.successfulAudioMatches * 100 ~/ m.totalAudioSearches;
    final sceneRate = m.totalSceneSearches == 0
        ? 0
        : m.successfulSceneMatches * 100 ~/ m.totalSceneSearches;

    List<DateTime> daysFor(Map<DateTime, int> counts) {
      final days = counts.keys.toList()..sort();
      return days;
    }

    // ---- Toggles & data prep ----
    final totalForPie = m.totalAudioSearches + m.totalSceneSearches;

    final animeEntries = m.topAnime.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final visibleAnimeEntries =
    animeEntries.take(_showTop50Anime ? 50 : 10).toList();

    final userEntries = m.topUsers.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final visibleUserEntries =
    userEntries.take(_showTop50Users ? 50 : 10).toList();

    final totalAnime = animeEntries.length;
    final totalUsers = userEntries.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics Overview'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _exportDashboard,
          ),
        ],
      ),
      body: RepaintBoundary(
        key: _boundaryKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Mini-Stats
              Text('Mini-Stats Dashboard', style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(children: [
                        _buildStat(Icons.music_note, 'Audio Searches', m.totalAudioSearches.toString()),
                        _buildStat(Icons.music_video, 'Audio Matches', m.successfulAudioMatches.toString()),
                      ]),
                      const SizedBox(height: 12),
                      Row(children: [
                        _buildStat(Icons.image, 'Scene Searches', m.totalSceneSearches.toString()),
                        _buildStat(Icons.image_search, 'Scene Matches', m.successfulSceneMatches.toString()),
                      ]),
                      const SizedBox(height: 12),
                      Row(children: [
                        _buildStat(Icons.bar_chart, 'Audio Success', '$audioRate%'),
                        _buildStat(Icons.bar_chart, 'Scene Success', '$sceneRate%'),
                      ]),
                      const SizedBox(height: 12),
                      Row(children: [
                        _buildStat(Icons.emoji_events, 'Best Streak', '${m.longestStreakDays}d'),
                        _buildStat(Icons.insights, 'Avg Confidence', _fmtPct(m.averageConfidence)),
                      ]),
                      const SizedBox(height: 12),
                      Row(children: [
                        _buildStat(Icons.playlist_add, 'Playlists Created', m.playlistsCreated.toString()),
                        _buildStat(Icons.leaderboard, 'Your Rank', '#${m.userRank}'),
                      ]),
                      const SizedBox(height: 12),
                      Row(children: [
                        const Icon(Icons.person),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Top 3 artists: ' +
                                m.topArtists.entries.take(3).map((e) => '${e.key} (${e.value})').join(', ') +
                                '.',
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),

              // daily bars & pie charts...
              const SizedBox(height: 32),
              _buildBar(
                title: 'Audio Searches Per Day',
                theme: theme,
                days: daysFor(m.audioSearchesPerDay),
                counts: m.audioSearchesPerDay,
                barColor: chartColors[2],
              ),

              const SizedBox(height: 32),
              _buildBar(
                title: 'Scene Searches Per Day',
                theme: theme,
                days: daysFor(m.sceneSearchesPerDay),
                counts: m.sceneSearchesPerDay,
                barColor: chartColors[1],
              ),

              const SizedBox(height: 32),
              Text('Audio vs Scene Ratio', style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              SizedBox(
                height: 200,
                child: (totalForPie == 0)
                    ? const Center(child: Text('No searches yet'))
                    : PieChart(
                  PieChartData(
                    sections: [
                      PieChartSectionData(
                        color: chartColors[0],
                        value: m.totalAudioSearches.toDouble(),
                        title: 'Audio\n${m.totalAudioSearches}',
                        radius: 60,
                      ),
                      PieChartSectionData(
                        color: chartColors[2],
                        value: m.totalSceneSearches.toDouble(),
                        title: 'Scene\n${m.totalSceneSearches}',
                        radius: 60,
                      ),
                    ],
                    centerSpaceRadius: 40,
                    sectionsSpace: 6,
                  ),
                ),
              ),

              const SizedBox(height: 32),
              _buildBar(
                title: 'Total Matches Per Day',
                theme: theme,
                days: daysFor(m.matchesPerDay),
                counts: m.matchesPerDay,
                barColor: chartColors[3],
              ),

              const SizedBox(height: 32),
              Text('Match Confidence Trend', style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              SizedBox(
                height: 200,
                child: (m.confidenceTrend.isEmpty)
                    ? const Center(child: Text('No confidence data yet'))
                    : LineChart(
                  LineChartData(
                    minY: 0,
                    maxY: 100,
                    gridData: FlGridData(show: true, drawVerticalLine: false),
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 36,
                          getTitlesWidget: (v, meta) {
                            if (v % 25 != 0) return const SizedBox.shrink();
                            return Text(v.toInt().toString(), style: const TextStyle(fontSize: 10));
                          },
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (v, meta) {
                            final idx = v.toInt();
                            if (idx < 0 || idx >= m.confidenceTrend.length) {
                              return const SizedBox.shrink();
                            }
                            return SideTitleWidget(
                              axisSide: meta.axisSide,
                              child: Text('#${idx + 1}', style: const TextStyle(fontSize: 10)),
                            );
                          },
                        ),
                      ),
                    ),
                    borderData: FlBorderData(
                      border: const Border(bottom: BorderSide(), left: BorderSide()),
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        isCurved: true,
                        spots: m.confidenceTrend.asMap().entries.map((e) {
                          final idx = e.key.toDouble();
                          final conf = _toPct(e.value.confidence);
                          return FlSpot(idx, conf);
                        }).toList(),
                        dotData: FlDotData(show: true),
                        belowBarData: BarAreaData(show: true, color: Colors.pinkAccent.withOpacity(0.3)),
                        color: Colors.pinkAccent,
                        barWidth: 3,
                      ),
                    ],
                  ),
                ),
              ),

              // ——— Global lists with 10/50 toggles ———
              const SizedBox(height: 32),
              Text('Global Top Anime Searches of the Month', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              if (visibleAnimeEntries.isEmpty)
                const Text('No data yet')
              else
                ...List.generate(visibleAnimeEntries.length, (i) {
                  final e = visibleAnimeEntries[i];
                  final title = e.key;
                  final hits = e.value;
                  final link = m.topAnimeLinks[title]; // "/users/discover?q=123&page=1&per=24"

                  return InkWell(
                    onTap: link == null
                        ? null
                        : () {
                            final uri = Uri.parse(link);
                            final q = uri.queryParameters['q'];
                            final id = int.tryParse(q ?? '');
                            if (id == null) return;

                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => AnimeDetailPage(id: id)),
                            );
                          },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Text('${i + 1}. '),
                          Expanded(
                            child: Text(
                              '$title — $hits hits',
                              style: TextStyle(
                                decoration: link == null ? TextDecoration.none : TextDecoration.underline,
                                color: link == null ? null : Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                          if (link != null) const Icon(Icons.open_in_new, size: 16),
                        ],
                      ),
                    ),
                  );
                }),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: totalAnime <= 10
                      ? null
                      : () => setState(() => _showTop50Anime = !_showTop50Anime),
                  child: Text(
                    totalAnime <= 10
                        ? 'Showing all $totalAnime'
                        : _showTop50Anime ? 'Show top 10' : 'Show top 50 ($totalAnime total)',
                  ),
                ),
              ),

              const SizedBox(height: 32),
              Text('Global Leaderboard For Searches', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              if (visibleUserEntries.isEmpty)
                const Text('No data yet')
              else
                ...List.generate(visibleUserEntries.length, (i) {
                  final e = visibleUserEntries[i];
                  return Text('${i + 1}. ${e.key} — ${e.value} searches');
                }),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: totalUsers <= 10
                      ? null
                      : () => setState(() => _showTop50Users = !_showTop50Users),
                  child: Text(
                    totalUsers <= 10
                        ? 'Showing all $totalUsers'
                        : _showTop50Users ? 'Show top 10' : 'Show top 50 ($totalUsers total)',
                  ),
                ),
              ),

              const SizedBox(height: 24),
              Text(
                'Tip: tap the share icon to export this dashboard.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _toPct(num? v) {
    final d = (v ?? 0).toDouble();
    return d > 1.0 ? d.clamp(0.0, 100.0) : (d * 100.0).clamp(0.0, 100.0);
  }

  String _fmtPct(num? v) => '${_toPct(v).round()}%';

  Widget _buildStat(IconData icon, String label, String val) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(val, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(label, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBar({
    required String title,
    required ThemeData theme,
    required List<DateTime> days,
    required Map<DateTime, int> counts,
    required Color barColor,
  }) {
    if (days.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          Container(
            height: 160,
            alignment: Alignment.center,
            child: const Text('No data yet'),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        SizedBox(
          height: 200,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceBetween,
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (v, meta) {
                      final idx = v.toInt();
                      if (idx < 0 || idx >= days.length) {
                        return const SizedBox.shrink();
                      }
                      final date = days[idx];
                      return SideTitleWidget(
                        axisSide: meta.axisSide,
                        child: Text(
                          '${date.month}/${date.day}',
                          style: const TextStyle(fontSize: 10),
                        ),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: true),
                ),
              ),
              borderData: FlBorderData(show: false),
              barGroups: List.generate(days.length, (i) {
                return BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: (counts[days[i]] ?? 0).toDouble(),
                      color: barColor,
                    ),
                  ],
                );
              }),
            ),
          ),
        ),
      ],
    );
  }
}
