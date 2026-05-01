// lib/screens/history_page.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/share_to_feed.dart';
import 'package:anime_finder/services/audio_service.dart';
import 'package:anime_finder/models/favorites_model.dart';
import 'package:anime_finder/models/scene_history_model.dart';

const _kHistoryNotesKey = 'history_notes';
const _kHistoryTagsKey = 'history_custom_tags';

class HistoryPage extends StatefulWidget {
  const HistoryPage({Key? key}) : super(key: key);

  @override
  _HistoryPageState createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History & Favorites'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Audio', icon: Icon(Icons.music_note)),
            Tab(text: 'Scenes', icon: Icon(Icons.image)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _AudioHistoryTab(),
          _SceneHistoryTab(),
        ],
      ),
    );
  }
}

/// Audio History with notes, tags, song favorites
class _AudioHistoryTab extends StatefulWidget {
  const _AudioHistoryTab();
  @override
  __AudioHistoryTabState createState() => __AudioHistoryTabState();
}

class __AudioHistoryTabState extends State<_AudioHistoryTab> {
  String? _filterAnime, _filterArtist, _filterType;
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
      final m = jsonDecode(notesJson) as Map<String, dynamic>;
      m.forEach((k, v) => _customNotes[k] = v as String);
    }
    final tagsJson = prefs.getString(_kHistoryTagsKey);
    if (tagsJson != null) {
      final m = jsonDecode(tagsJson) as Map<String, dynamic>;
      m.forEach((k, v) => _customTags[k] = List<String>.from(v as List));
    }
    setState(() {});
  }

  Future<void> _saveCustomData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kHistoryNotesKey, jsonEncode(_customNotes));
    await prefs.setString(_kHistoryTagsKey, jsonEncode(_customTags));
  }

  @override
  Widget build(BuildContext context) {
    final history = context.watch<AudioService>().matchHistory;
    final favModel = context.watch<FavoritesModel>();

    // de-duplicate by song_name
    final seen = <String>{};
    final unique = <Map<String, dynamic>>[];
    for (var m in history) {
      final sn = (m['song_name'] as String?) ?? '';
      if (sn.isEmpty || seen.contains(sn)) continue;
      seen.add(sn);
      unique.add(m);
    }

    // dropdown options
    final animeTitles = unique
        .map((m) => (m['anime'] as Map)['title'] as String?)
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

    // apply filters
    final filtered = unique.where((m) {
      final ani = m['anime'] as Map<String, dynamic>;
      final title = ani['title'] as String?;
      final artist = m['artist'] as String?;
      final type = m['op_ed_type'] as String?;
      if (_filterAnime != null && title != _filterAnime) return false;
      if (_filterArtist != null && artist != _filterArtist) return false;
      if (_filterType != null && type != _filterType) return false;
      return true;
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _buildDropdown('Anime', animeTitles, _filterAnime, (v) => setState(() => _filterAnime = v)),
              const SizedBox(width: 8),
              _buildDropdown('Artist', artists, _filterArtist, (v) => setState(() => _filterArtist = v)),
              const SizedBox(width: 8),
              _buildDropdown('Type', types, _filterType, (v) => setState(() => _filterType = v)),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.clear_all),
                onPressed: () => setState(() {
                  _filterAnime = _filterArtist = _filterType = null;
                }),
              ),
            ]),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('No matches'))
              : ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: filtered.length,
            itemBuilder: (ctx, i) {
              final m = filtered[i];
              final songName = (m['song_name'] as String?) ?? '';
              final isFav = favModel.isSongFavorite(m);
              final ani = m['anime'] as Map<String, dynamic>;
              final cover = ani['cover_url'] as String?;
              final title = ani['title'] as String? ?? '';
              final note = _customNotes[songName];
              final tags = _customTags[songName] ?? [];

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 6),
                child: ListTile(
                  leading: cover != null && cover.isNotEmpty
                      ? Image.network(cover, width: 50, fit: BoxFit.cover)
                      : const Icon(Icons.broken_image),
                  title: Text(title),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Song: $songName'),
                      if (note != null && note.isNotEmpty)
                        Text('Note: $note'),
                      if (tags.isNotEmpty)
                        Wrap(
                          spacing: 4,
                          children: tags.map((t) => Chip(label: Text(t))).toList(),
                        ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Favorite Song',
                        icon: Icon(
                          isFav ? Icons.favorite : Icons.favorite_border,
                          color: isFav ? Colors.redAccent : null,
                        ),
                        onPressed: () => favModel.toggleSongFavorite(m),
                      ),
                      IconButton(
                        tooltip: 'Share to Feed',
                        icon: const Icon(Icons.send),
                        onPressed: () {
                          final caption = StringBuffer('🎵 $songName');
                          final artist = m['artist'] as String?;
                          final typ = m['op_ed_type'] as String?;
                          if (artist != null && artist.isNotEmpty) {
                            caption.write(' • $artist');
                          }
                          if (typ != null && typ.isNotEmpty) {
                            caption.write(' • $typ');
                          }
                          if (title.isNotEmpty) {
                            caption.write(' — $title');
                          }

                          shareToFeed(
                            context: context,
                            caption: caption.toString(),
                            imageUrl: cover,
                            // If you have an AniList id inside your map, add it here:
                            // anilistId: ani['id'] as int?,
                            animeTitle: title,
                            extra: {
                              "source": "History",
                              "song_name": songName,
                              "artist": artist,
                              "op_ed_type": typ,
                            },
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_note),
                        tooltip: 'Edit Note & Tags',
                        onPressed: () async {
                          final result = await _showEditDialog(songName, note, tags);
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
                  onTap: () {
                    _showAudioMetadataSheet(context, ani, songName, note, tags);
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showAudioMetadataSheet(
      BuildContext context,
      Map<String, dynamic> ani,
      String songName,
      String? note,
      List<String> tags,
      ) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if ((ani['cover_url'] as String?)?.isNotEmpty ?? false)
                Center(
                  child: Image.network(
                    ani['cover_url'],
                    height: 160,
                    fit: BoxFit.cover,
                  ),
                ),
              const SizedBox(height: 10),
              Text(
                ani['title'] ?? '',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              if (ani['artist'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text('Artist: ${ani['artist']}',
                      style: const TextStyle(color: Colors.teal)),
                ),
              if (ani['season'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2.0),
                  child: Text('Season: ${ani['season']}'),
                ),
              if (ani['genres'] != null &&
                  ani['genres'] is List &&
                  (ani['genres'] as List).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2.0),
                  child: Text('Genres: ${(ani['genres'] as List).join(', ')}'),
                ),
              if (ani['tags'] != null &&
                  ani['tags'] is List &&
                  (ani['tags'] as List).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2.0),
                  child: Text('Tags: ${(ani['tags'] as List).join(', ')}'),
                ),
              if (note != null && note.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text('Note: $note',
                      style: const TextStyle(fontStyle: FontStyle.italic)),
                ),
              if (tags.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2.0),
                  child: Wrap(
                    spacing: 4,
                    children: tags.map((t) => Chip(label: Text(t))).toList(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<Map<String, dynamic>?> _showEditDialog(
      String songName, String? note, List<String> tags) {
    final noteCtrl = TextEditingController(text: note);
    final tagCtrl = TextEditingController(text: tags.join(','));
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => AlertDialog(
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
              decoration: const InputDecoration(labelText: 'Tags (comma)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(
              context,
              {'note': noteCtrl.text, 'tags': tagCtrl.text},
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown(
      String label,
      List<String> items,
      String? selected,
      ValueChanged<String?> onChanged,
      ) {
    // Use nullable generics so an "All" (null) option is valid.
    return DropdownButton<String?>(
      value: selected,
      hint: Text(label),
      items: <DropdownMenuItem<String?>>[
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('All'),
        ),
        ...items.map(
              (it) => DropdownMenuItem<String?>(
            value: it,
            child: Text(it),
          ),
        ),
      ],
      onChanged: onChanged,
    );
    // End nullable dropdown
  }
}

/// Scene History tab (tap to show metadata)
class _SceneHistoryTab extends StatelessWidget {
  const _SceneHistoryTab();
  @override
  Widget build(BuildContext context) {
    final sceneHistory = context.watch<SceneHistoryModel>().entries;
    final favModel = context.watch<FavoritesModel>();

    if (sceneHistory.isEmpty) {
      return const Center(child: Text('No scene history yet.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: sceneHistory.length,
      itemBuilder: (ctx, i) {
        final e = sceneHistory[i];
        final isFav = favModel.isAnimeFavorite(e.aniListId.toString());
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: ListTile(
            leading: e.coverUrl.isNotEmpty
                ? Image.network(e.coverUrl, width: 50, fit: BoxFit.cover)
                : const Icon(Icons.broken_image),
            title: Text(e.title),
            subtitle: Text('Episode ${e.episode} • ${e.timeRange}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Share to Feed',
                  icon: const Icon(Icons.send),
                  onPressed: () {
                    shareToFeed(
                      context: context,
                      caption:
                      "🎬 ${e.title} • Ep ${e.episode} @ ${e.timeRange}",
                      imageUrl: e.coverUrl,
                      anilistId: e.aniListId,
                      animeTitle: e.title,
                      extra: {
                        "source": "History-Scenes",
                        "episode": e.episode,
                        "time_range": e.timeRange,
                        "added": e.dateAdded.toIso8601String(),
                      },
                    );
                  },
                ),
                IconButton(
                  icon: Icon(
                    isFav ? Icons.star : Icons.star_border,
                    color: isFav ? Colors.amber : null,
                  ),
                  onPressed: () =>
                      favModel.toggleAnimeFavoriteById(e.aniListId.toString()),
                ),
              ],
            ),
            onTap: () {
              _showSceneMetaSheet(context, e);
            },
          ),
        );
      },
    );
  }

  void _showSceneMetaSheet(BuildContext context, SceneHistoryEntry e) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (e.coverUrl.isNotEmpty)
              Center(child: Image.network(e.coverUrl, height: 160, fit: BoxFit.cover)),
            const SizedBox(height: 10),
            Text(e.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Episode: ${e.episode}', style: const TextStyle(color: Colors.teal)),
            Text('Time: ${e.timeRange}', style: const TextStyle(color: Colors.indigo)),
            Text('AniList ID: ${e.aniListId}', style: const TextStyle(color: Colors.purple)),
            Text('Added: ${e.dateAdded.toLocal()}',
                style: const TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
