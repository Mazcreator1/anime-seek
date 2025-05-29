// lib/screens/analytics_page.dart

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'package:anime_finder/models/analytics_model.dart';

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({Key? key}) : super(key: key);

  @override
  _AnalyticsPageState createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  late DateTimeRange _range;
  final GlobalKey _boundaryKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _range = DateTimeRange(
      start: now.subtract(const Duration(days: 30)),
      end: now,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AnalyticsModel>().fetchStats(_range);
    });
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _range,
    );
    if (picked != null) {
      setState(() => _range = picked);
      await context.read<AnalyticsModel>().fetchStats(_range);
    }
  }

  Future<void> _exportDashboard() async {
    try {
      final boundary = _boundaryKey.currentContext!
          .findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final byteData = await image.toByteData(
          format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();

      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/analytics_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes);

      await Share.shareFiles(
        [file.path],
        text:
        'My Analytics (${DateFormat.yMMMd().format(_range.start)} – ${DateFormat.yMMMd().format(_range.end)})',
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error exporting: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AnalyticsModel>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics Overview'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: model.isLoading ? null : _exportDashboard,
          ),
        ],
      ),
      body: model.isLoading
          ? const Center(child: CircularProgressIndicator())
          : RepaintBoundary(
        key: _boundaryKey,
        child: SingleChildScrollView(
          padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Date range
              OutlinedButton.icon(
                icon: const Icon(Icons.date_range),
                label: Text(
                  '${DateFormat.yMMMd().format(_range.start)} – '
                      '${DateFormat.yMMMd().format(_range.end)}',
                ),
                onPressed: _pickDateRange,
              ),
              const SizedBox(height: 24),

              // Mini-Stats Dashboard
              Text('Mini-Stats Dashboard',
                  style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          _buildStatItem(
                              Icons.music_note,
                              'Matches',
                              model.totalMatches.toString()),
                          _buildStatItem(Icons.emoji_events,
                              'Best Streak', '${model.longestStreakDays}d'),
                          _buildStatItem(Icons.insights,
                              'Avg Confidence', '${model.averageConfidence.toStringAsFixed(0)}%'),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.person),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Top 3 artists: ' +
                                  model.topArtists.entries
                                      .take(3)
                                      .map((e) => '${e.key} (${e.value})')
                                      .join(', ') +
                                  '.',
                              style: const TextStyle(fontSize: 16),
                            ),
                          )
                        ],
                      )
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Genre pie chart
              Text('Genre Distribution',
                  style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              SizedBox(
                height: 200,
                child: PieChart(
                  PieChartData(
                    sections: model.genreDistribution.entries
                        .map((e) => PieChartSectionData(
                      value: e.value.toDouble(),
                      title: e.key,
                      radius: 50,
                    ))
                        .toList(),
                    centerSpaceRadius: 40,
                    sectionsSpace: 2,
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Matches per day (bar chart)
              Text('Matches Per Day',
                  style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              SizedBox(
                height: 200,
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceBetween,
                    barTouchData: BarTouchData(enabled: false),
                    titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget:
                              (value, meta) {
                            final date = _range.start
                                .add(Duration(days: value.toInt()));
                            return SideTitleWidget(
                              axisSide: meta.axisSide,
                              child: Text(
                                DateFormat.Md().format(date),
                                style: const TextStyle(fontSize: 10),
                              ),
                            );
                          },
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles:
                        SideTitles(showTitles: true),
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    barGroups: model.matchesPerDay.entries
                        .map((e) => BarChartGroupData(
                      x: e.key
                          .difference(_range.start)
                          .inDays,
                      barRods: [
                        BarChartRodData(
                            toY: e.value.toDouble())
                      ],
                    ))
                        .toList(),
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Confidence trend (line chart)
              Text('Match Confidence Trend',
                  style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              SizedBox(
                height: 200,
                child: LineChart(
                  LineChartData(
                    gridData: FlGridData(
                        show: true, drawVerticalLine: false),
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(
                        sideTitles:
                        SideTitles(showTitles: true),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            final date = _range.start
                                .add(Duration(days: value.toInt()));
                            return SideTitleWidget(
                              axisSide: meta.axisSide,
                              child: Text(
                                DateFormat.Md().format(date),
                                style:
                                const TextStyle(fontSize: 10),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    borderData: FlBorderData(
                      border: const Border(
                        bottom: BorderSide(),
                        left: BorderSide(),
                      ),
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        isCurved: true,
                        spots: model.confidenceTrend
                            .map((p) => FlSpot(
                          p.date
                              .difference(_range.start)
                              .inDays
                              .toDouble(),
                          p.confidence,
                        ))
                            .toList(),
                        dotData: FlDotData(show: true),
                        belowBarData: BarAreaData(
                            show: true,
                            color: theme.colorScheme.primary
                                .withOpacity(0.2)),
                        color: theme.colorScheme.primary,
                        barWidth: 3,
                      )
                    ],
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

  Widget _buildStatItem(
      IconData icon, String label, String value) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              Text(value,
                  style:
                  const TextStyle(fontWeight: FontWeight.bold)),
              Text(label,
                  style: const TextStyle(fontSize: 12)),
            ],
          )
        ],
      ),
    );
  }
}
