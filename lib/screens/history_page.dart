// lib/screens/history_page.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:anime_finder/services/audio_service.dart';
import 'package:anime_finder/models/favorites_model.dart';
import 'package:anime_finder/screens/anime_match_detail_page.dart';
import 'package:anime_finder/screens/main_recognition_page.dart';

const _kHistoryNotesKey = 'history_notes';
const _kHistoryTagsKey  = 'history_custom_tags';

class HistoryPage extends StatefulWidget {
  const HistoryPage({Key? key}) : super(key: key);

  @override
  _HistoryPageState createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  // Filter criteria
  String? _filterAnime;
  String? _filterArtist;
  String? _filterType;
  String? _filterSeason;
  String? _filterGenre;
  String? _filterTag;

  // Custom notes and tags
  final Map<String, String> _customNotes = {};
  final Map<String, List<String>> _customTags = {};

  @override
  void initState() {
    super.initState();
    _loadCustomData();
  }

  Future<void> _loadCustomData() async {
    final prefs = await SharedPreferences.getInstance();
    final notesJson = prefs.getString(_kHistoryNotesKey);
    if (notesJson != null) {
      try {
        final Map<String, dynamic> decoded = json.decode(notesJson);
        decoded.forEach((song, note) {
          _customNotes[song] = note as String;
        });
      } catch (_) {}
    }
    final tagsJson = prefs.getString(_kHistoryTagsKey);
    if (tagsJson != null) {
      try {
        final Map<String, dynamic> decoded = json.decode(tagsJson);
        decoded.forEach((song, tagList) {
          _customTags[song] = List<String>.from(tagList as List);
        });
      } catch (_) {}
    }
    setState(() {});
  }

  Future<void> _saveCustomData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kHistoryNotesKey, json.encode(_customNotes));
    await prefs.setString(_kHistoryTagsKey, json.encode(_customTags));
  }

  @override
  Widget build(BuildContext context) {
    final history = context.watch<AudioService>().matchHistory;
    final favModel = context.watch<FavoritesModel>();
    final animeFaves = favModel.animeFavoritesList;

    if (history.isEmpty) {
      return const Center(child: Text('No matches yet.'));
    }

    // Unique by song_name
    final seen = <String>{};
    final unique = <Map<String, dynamic>>[];
    for (var m in history) {
      final name = (m['song_name'] as String?) ?? '';
      if (name.isEmpty || seen.contains(name)) continue;
      seen.add(name);
      unique.add(m);
    }

    // Derive filter options
    final animeTitles = unique
        .map((m) => (m['anime'] as Map<String, dynamic>)['title'] as String?)
        .whereType<String>()
        .toSet()
        .toList();
    final artists = unique
        .map((m) => m['artist'] as String?)
        .whereType<String>()
        .toSet()
        .toList();
    final types = unique
        .map((m) => m['op_ed_type'] as String?)
        .whereType<String>()
        .toSet()
        .toList();
    final seasons = unique
        .map((m) => (m['anime'] as Map<String, dynamic>)['season'] as String?)
        .whereType<String>()
        .toSet()
        .toList();
    final genres = unique
        .expand((m) => List<String>.from((m['anime'] as Map<String, dynamic>)['genres'] ?? []))
        .toSet()
        .toList();
    final tags = ([
      ...unique
          .expand((m) => List<String>.from((m['anime'] as Map<String, dynamic>)['tags'] ?? [])),
      ..._customTags.values.expand((lst) => lst),
    ]).toSet().toList();

    // Apply filters
    final filtered = unique.where((m) {
      final ani = m['anime'] as Map<String, dynamic>;
      final title = ani['title'] as String?;
      final artist = m['artist'] as String?;
      final type = m['op_ed_type'] as String?;
      final season = ani['season'] as String?;
      final itemGenres = List<String>.from(ani['genres'] ?? []);
      final itemTags = [
        ...List<String>.from(ani['tags'] ?? []),
        ...(_customTags[m['song_name']] ?? []),
      ];
      if (_filterAnime != null && title != _filterAnime) return false;
      if (_filterArtist != null && artist != _filterArtist) return false;
      if (_filterType != null && type != _filterType) return false;
      if (_filterSeason != null && season != _filterSeason) return false;
      if (_filterGenre != null && !itemGenres.contains(_filterGenre)) return false;
      if (_filterTag != null && !itemTags.contains(_filterTag)) return false;
      return true;
    }).toList();

    return Column(
      children: [
        ExpansionTile(
          title: const Text('Filters', style: TextStyle(fontWeight: FontWeight.bold)),
          childrenPadding: EdgeInsets.zero,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDropdownFilter(
                    label: 'Anime',
                    items: animeTitles,
                    selected: _filterAnime,
                    onChanged: (v) => setState(() => _filterAnime = v),
                  ),
                  const SizedBox(width: 12),
                  _buildDropdownFilter(
                    label: 'Artist',
                    items: artists,
                    selected: _filterArtist,
                    onChanged: (v) => setState(() => _filterArtist = v),
                  ),
                  const SizedBox(width: 12),
                  _buildDropdownFilter(
                    label: 'Type',
                    items: types,
                    selected: _filterType,
                    onChanged: (v) => setState(() => _filterType = v),
                  ),
                  const SizedBox(width: 12),
                  _buildDropdownFilter(
                    label: 'Season',
                    items: seasons,
                    selected: _filterSeason,
                    onChanged: (v) => setState(() => _filterSeason = v),
                  ),
                  const SizedBox(width: 12),
                  _buildDropdownFilter(
                    label: 'Genre',
                    items: genres,
                    selected: _filterGenre,
                    onChanged: (v) => setState(() => _filterGenre = v),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    icon: const Icon(Icons.clear_all),
                    tooltip: 'Clear Filters',
                    onPressed: () => setState(() {
                      _filterAnime = _filterArtist = _filterType = _filterSeason = _filterGenre = _filterTag = null;
                    }),
                  ),
                ],
              ),
            ),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('No matches match filters.'))
              : ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: filtered.length,
            itemBuilder: (ctx, i) {
              final match = filtered[i];
              final songName = (match['song_name'] as String?) ?? '';
              final isFav = favModel.isFavorite(songName);
              final ani = match['anime'] as Map<String, dynamic>;
              final cover = ani['cover_url'] as String?;
              final title = ani['title'] as String? ?? '';
              final note = _customNotes[songName];
              final userTags = _customTags[songName] ?? [];

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 6),
                child: ListTile(
                  leading: cover != null
                      ? Image.network(cover, width: 50, fit: BoxFit.cover)
                      : const Icon(Icons.broken_image),
                  title: Text(title),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Song: $songName'),
                      if (note != null) Text('Note: $note'),
                      if (userTags.isNotEmpty)
                        Wrap(
                          spacing: 4,
                          children: userTags.map((t) => Chip(label: Text(t))).toList(),
                        ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          isFav ? Icons.star : Icons.star_border,
                          color: isFav ? Colors.amber : null,
                        ),
                        onPressed: () => favModel.toggleFavorite(match),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_note),
                        tooltip: 'Edit Note & Tags',
                        onPressed: () async {
                          final result = await showDialog<Map<String, dynamic>>(
                            context: context,
                            builder: (_) {
                              final noteCtrl = TextEditingController(text: note);
                              final tagCtrl = TextEditingController(text: userTags.join(','));
                              return AlertDialog(
                                title: const Text('Edit Note & Tags'),
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TextField(
                                      controller: noteCtrl,
                                      decoration: const InputDecoration(labelText: 'Note'),
                                    ),
                                    TextField(
                                      controller: tagCtrl,
                                      decoration: const InputDecoration(labelText: 'Tags (comma separated)'),
                                    ),
                                  ],
                                ),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                                  ElevatedButton(
                                    onPressed: () {
                                      Navigator.pop(context, {
                                        'note': noteCtrl.text,
                                        'tags': tagCtrl.text,
                                      });
                                    },
                                    child: const Text('Save'),
                                  ),
                                ],
                              );
                            },
                          );
                          if (result != null) {
                            setState(() {
                              final n = (result['note'] as String).trim();
                              final t = (result['tags'] as String)
                                  .split(',')
                                  .map((s) => s.trim())
                                  .where((s) => s.isNotEmpty)
                                  .toList();
                              if (n.isEmpty) {
                                _customNotes.remove(songName);
                              } else {
                                _customNotes[songName] = n;
                              }
                              if (t.isEmpty) {
                                _customTags.remove(songName);
                              } else {
                                _customTags[songName] = t;
                              }
                            });
                            await _saveCustomData();
                          }
                        },
                      ),
                    ],
                  ),
                  onTap: () => Navigator.of(ctx).push(
                    MaterialPageRoute(builder: (_) => AnimeMatchDetailPage(anime: match)),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Helper to build a labeled dropdown filter
  Widget _buildDropdownFilter({
    required String label,
    required List<String> items,
    required String? selected,
    required ValueChanged<String?> onChanged,
  }) {
    return Row(
      children: [
        Text('$label:', style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        DropdownButton<String>(
          value: selected,
          hint: const Text('All'),
          items: [
            const DropdownMenuItem(value: null, child: Text('All')),
            ...items.map((it) => DropdownMenuItem(value: it, child: Text(it))).toList(),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }
}
