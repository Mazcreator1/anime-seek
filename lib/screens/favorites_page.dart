// lib/screens/favorites_page.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/share_to_feed.dart';
import 'package:anime_finder/models/favorites_model.dart';
import 'package:anime_finder/models/playlist_model.dart';
import 'package:anime_finder/screens/anime_match_detail_page.dart';
import 'package:anime_finder/screens/anime_detail_page.dart';

const _kSelectedSongPlaylistKey = 'selected_song_playlist';
const _kSelectedAnimePlaylistKey = 'selected_anime_playlist';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({Key? key}) : super(key: key);

  @override
  _FavoritesPageState createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  String? _selectedSongPlaylist;
  String? _selectedAnimePlaylist;

  Map<String, Anime> _animeDetails = {};
  bool _loadingAnimes = false;

  bool get isSongsTab => _tabController.index == 0;
  String? get _selectedPlaylist =>
      isSongsTab ? _selectedSongPlaylist : _selectedAnimePlaylist;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (mounted) _loadSelectedPlaylist();

        // If switching to the Animes tab, make sure we have details
        if (_tabController.index == 1) {
          final ids = context.read<FavoritesModel>().animeFavoritesList;
          _fetchAnimeDetails(ids);
        }
      });

    _searchController.addListener(() {
      if (!mounted) return;
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadSelectedPlaylist();
      final ids = context.read<FavoritesModel>().animeFavoritesList;
      _fetchAnimeDetails(ids);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSelectedPlaylist() async {
    final prefs = await SharedPreferences.getInstance();
    final song = prefs.getString(_kSelectedSongPlaylistKey);
    final anime = prefs.getString(_kSelectedAnimePlaylistKey);
    if (!mounted) return;
    setState(() {
      _selectedSongPlaylist = song;
      _selectedAnimePlaylist = anime;
    });
  }

  Future<void> _saveSelectedPlaylist(String? name) async {
    final prefs = await SharedPreferences.getInstance();
    if (isSongsTab) {
      _selectedSongPlaylist = name;
      if (!mounted) return;
      if (name == null) {
        await prefs.remove(_kSelectedSongPlaylistKey);
      } else {
        await prefs.setString(_kSelectedSongPlaylistKey, name);
      }
    } else {
      _selectedAnimePlaylist = name;
      if (!mounted) return;
      if (name == null) {
        await prefs.remove(_kSelectedAnimePlaylistKey);
      } else {
        await prefs.setString(_kSelectedAnimePlaylistKey, name);
      }
    }
  }

  Future<void> _fetchAnimeDetails(List<String> ids) async {
    if (_loadingAnimes) return;
    _loadingAnimes = true;
    if (mounted) setState(() {});
    const apiUrl = 'https://graphql.anilist.co';

    for (final id in ids) {
      if (_animeDetails.containsKey(id)) continue;
      final query = '''
        query(\$id:Int){
          Media(id:\$id){
            id title{romaji} coverImage{large} genres description
          }
        }
      ''';
      try {
        final res = await http.post(
          Uri.parse(apiUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'query': query, 'variables': {'id': int.parse(id)}}),
        );
        if (!mounted) return;
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final media = data['data']?['Media'];
        if (media != null) {
          _animeDetails[id] = Anime.fromGraphQL(media);
        }
      } catch (_) {
        // ignore fetch error
      }
    }

    _loadingAnimes = false;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final favModel = context.watch<FavoritesModel>();
    final playlistsModel = context.watch<PlaylistsModel>();

    // Build the base song list depending on playlist selection,
    // then apply the search filter so search works in both modes.
    final List<Map<String, dynamic>> baseSongs =
    _selectedSongPlaylist == null
        ? favModel.songFavoritesList
        : playlistsModel.getSongsInPlaylist(_selectedSongPlaylist!);

    List<Map<String, dynamic>> filteredSongs = baseSongs.where((m) {
      final song = (m['song_name'] as String? ?? '').toLowerCase();
      final title = (m['anime']?['title'] as String? ?? '').toLowerCase();
      return _searchQuery.isEmpty ||
          song.contains(_searchQuery) ||
          title.contains(_searchQuery);
    }).toList();

    // Anime favorites: apply search first
    final animeIds = favModel.animeFavoritesList
        .where((id) => id.toLowerCase().contains(_searchQuery))
        .toList();

    // If a playlist is selected for Animes, intersect with that playlist
    final List<String> filteredAnimes = _selectedAnimePlaylist == null
        ? animeIds
        : playlistsModel
        .getAnimesInPlaylist(_selectedAnimePlaylist!)
        .where((id) => animeIds.contains(id))
        .toList();

    Future<void> _onCreatePlaylist() async {
      final items = isSongsTab
          ? filteredSongs
          : filteredAnimes.map((id) => {'id': id}).toList();
      await _showCreateDialog(items);
    }

    Future<void> _onAddToPlaylist() async {
      final items = isSongsTab
          ? filteredSongs
          : filteredAnimes.map((id) => {'id': id}).toList();
      await _showAddDialog(items);
    }

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Favorites'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: 'Songs'), Tab(text: 'Animes')],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.playlist_add),
            tooltip: 'New Playlist',
            onPressed: (isSongsTab ? filteredSongs.isNotEmpty : filteredAnimes.isNotEmpty)
                ? _onCreatePlaylist
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.playlist_add_check),
            tooltip: 'Add to Playlist',
            onPressed: (isSongsTab
                ? (_selectedSongPlaylist != null)
                : (_selectedAnimePlaylist != null))
                ? _onAddToPlaylist
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.clear),
            tooltip: 'Clear Playlist Filter',
            onPressed: () {
              setState(() {
                if (isSongsTab) {
                  _selectedSongPlaylist = null;
                } else {
                  _selectedAnimePlaylist = null;
                }
              });
              _saveSelectedPlaylist(null);
            },
          ),
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Share All',
            onPressed: () {
              final buffer = StringBuffer();
              if (isSongsTab) {
                for (var m in filteredSongs) {
                  final anime = m['anime'] as Map<String, dynamic>? ?? {};
                  final id = anime['id']?.toString();
                  buffer.writeln('🎵 ${m['song_name']}');
                  buffer.writeln(
                    '• Anime: ${anime['title'] ?? ''}'
                        '${id != null ? ' — https://anilist.co/anime/$id' : ''}',
                  );
                  buffer.writeln();
                }
              } else {
                for (var id in filteredAnimes) {
                  final a = _animeDetails[id];
                  if (a != null) {
                    buffer.writeln('⭐ ${a.title}');
                    buffer.writeln('Genres: ${a.genres.join(', ')}');
                    buffer.writeln('Link: https://anilist.co/anime/${a.id}');
                    buffer.writeln();
                  } else {
                    buffer.writeln('⭐ Anime #$id');
                  }
                }
              }
              Share.share(
                buffer.toString(),
                subject: isSongsTab
                    ? 'My Favorite Anime Songs'
                    : 'My Favorite Anime List',
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Search favorites…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
          ),

          // Playlist dropdown + delete icon
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: DropdownButton<String>(
              isExpanded: true,
              hint: Text(isSongsTab ? 'Song Playlist' : 'Anime Playlist'),
              value: _selectedPlaylist,
              items: (isSongsTab
                  ? playlistsModel.songNames
                  : playlistsModel.animeNames)
                  .map((name) => DropdownMenuItem(
                value: name,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(name),
                    IconButton(
                      icon: const Icon(Icons.delete, size: 20),
                      onPressed: () {
                        if (isSongsTab) {
                          playlistsModel.deleteSongPlaylist(name);
                          if (_selectedSongPlaylist == name) {
                            _saveSelectedPlaylist(null);
                          }
                        } else {
                          playlistsModel.deleteAnimePlaylist(name);
                          if (_selectedAnimePlaylist == name) {
                            _saveSelectedPlaylist(null);
                          }
                        }
                        setState(() {});
                      },
                    ),
                  ],
                ),
              ))
                  .toList(),
              onChanged: (v) {
                setState(() {
                  if (isSongsTab) {
                    _selectedSongPlaylist = v;
                  } else {
                    _selectedAnimePlaylist = v;
                  }
                });
                _saveSelectedPlaylist(v);
              },
            ),
          ),

          // Tab views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Songs tab
                filteredSongs.isEmpty
                    ? const Center(child: Text('No song favorites found.'))
                    : ListView.builder(
                  itemCount: filteredSongs.length,
                  itemBuilder: (_, i) {
                    final m = filteredSongs[i];
                    final key = ValueKey(
                      '${m['song_name']}-${m['anime']?['id'] ?? ''}',
                    );
                    return Dismissible(
                      key: key,
                      direction: DismissDirection.endToStart,
                      background: Container(
                        color: Colors.red,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      onDismissed: (_) {
                        setState(() {
                          if (_selectedSongPlaylist == null) {
                            // Use the new FavoritesModel API
                            context.read<FavoritesModel>().toggleSongFavorite(m);
                          } else {
                            playlistsModel.removeSongFromPlaylist(
                              _selectedSongPlaylist!,
                              m,
                            );
                          }
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              _selectedSongPlaylist == null
                                  ? 'Removed "${m['song_name']}"'
                                  : 'Removed "${m['song_name']}" from $_selectedSongPlaylist',
                            ),
                          ),
                        );
                      },
                      child: songTile(m),
                    );
                  },
                ),

                // Animes tab
                filteredAnimes.isEmpty
                    ? const Center(child: Text('No anime favorites found.'))
                    : ListView.builder(
                  itemCount: filteredAnimes.length,
                  itemBuilder: (_, i) {
                    final id = filteredAnimes[i];
                    final title = _animeDetails[id]?.title ?? 'Anime #$id';
                    return Dismissible(
                      key: ValueKey(id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        color: Colors.red,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      onDismissed: (_) {
                        setState(() {
                          if (_selectedAnimePlaylist == null) {
                            // Keep using your existing anime toggler if present
                            context
                                .read<FavoritesModel>()
                                .toggleAnimeFavoriteById(id);
                          } else {
                            playlistsModel.removeAnimeFromPlaylist(
                              _selectedAnimePlaylist!,
                              id,
                            );
                          }
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              _selectedAnimePlaylist == null
                                  ? 'Removed "$title"'
                                  : 'Removed "$title" from $_selectedAnimePlaylist',
                            ),
                          ),
                        );
                      },
                      child: animeTile(id),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showCreateDialog(List<Map<String, dynamic>> items) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('New Playlist'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: 'Playlist name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      final model = context.read<PlaylistsModel>();
      final success = isSongsTab
          ? await model.createSongPlaylist(name, items)
          : await model.createAnimePlaylist(name, items);
      if (success) {
        setState(() {
          if (isSongsTab) {
            _selectedSongPlaylist = name;
          } else {
            _selectedAnimePlaylist = name;
          }
        });
        await _saveSelectedPlaylist(name);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Playlist exists or name empty')),
        );
      }
    }
  }

  Future<void> _showAddDialog(List<Map<String, dynamic>> items) async {
    final model = context.read<PlaylistsModel>();
    final names = isSongsTab ? model.songNames : model.animeNames;
    if (names.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No playlists exist')),
      );
      return;
    }
    String? pick;
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add to Playlist'),
        content: DropdownButtonFormField<String>(
          items: names
              .map((n) => DropdownMenuItem(value: n, child: Text(n)))
              .toList(),
          onChanged: (v) => pick = v,
          decoration: const InputDecoration(labelText: 'Playlist'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, pick),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (result != null) {
      if (isSongsTab) {
        await model.addSongs(result, items);
      } else {
        await model.addAnimes(result, items);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added to "$result"')),
      );
      setState(() {});
    }
  }

  Widget songTile(Map<String, dynamic> m) {
    final title = m['song_name'] as String? ?? '';
    final ani = m['anime'] as Map<String, dynamic>? ?? {};
    final coverUrl = ani['cover_url'] as String?;
    final animeTitle = (ani['title'] as String?) ?? '';
    final animeIdAny = ani['id'];
    final anilistId = animeIdAny is int
        ? animeIdAny
        : (animeIdAny is String ? int.tryParse(animeIdAny) : null);

    return ListTile(
      leading: (coverUrl != null && coverUrl.isNotEmpty)
          ? Image.network(coverUrl, width: 50, fit: BoxFit.cover)
          : const Icon(Icons.music_note),
      title: Text(title),
      subtitle: Text(animeTitle),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AnimeMatchDetailPage(anime: m)),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Share to Feed',
            icon: const Icon(Icons.send),
            onPressed: () {
              final artist = m['artist'] as String?;
              final typ = m['op_ed_type'] as String?;
              final caption = StringBuffer('🎵 $title');
              if (artist != null && artist.isNotEmpty) caption.write(' • $artist');
              if (typ != null && typ.isNotEmpty) caption.write(' • $typ');
              if (animeTitle.isNotEmpty) caption.write(' — $animeTitle');

              shareToFeed(
                context: context,
                caption: caption.toString(),
                imageUrl: coverUrl,
                anilistId: anilistId,
                animeTitle: animeTitle,
                extra: {
                  "source": "Favorites-Songs",
                  "song_name": title,
                  "artist": artist,
                  "op_ed_type": typ,
                },
              );
            },
          ),
          if (_selectedPlaylist != null)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () {
                setState(() {
                  context
                      .read<PlaylistsModel>()
                      .removeSongFromPlaylist(_selectedPlaylist!, m);
                });
              },
            ),
        ],
      ),
    );
  }

  Widget animeTile(String id) {
    final a = _animeDetails[id];
    final coverUrl = a?.coverUrl;
    final title = a?.title ?? 'Anime #$id';
    final anilistId = a?.id;

    return ListTile(
      leading: (coverUrl != null && coverUrl.isNotEmpty)
          ? Image.network(coverUrl, width: 50, fit: BoxFit.cover)
          : const Icon(Icons.movie),
      title: Text(title),
      subtitle: Text(a?.genres.join(', ') ?? ''),
      onTap: () {
        if (a != null) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => AnimeDetailPage(id: a.id)),
          );
        }
      },
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Share to Feed',
            icon: const Icon(Icons.send),
            onPressed: () {
              shareToFeed(
                context: context,
                caption: "⭐ $title",
                imageUrl: coverUrl,
                anilistId: anilistId,
                animeTitle: title,
                extra: {
                  "source": "Favorites-Animes",
                  "genres": a?.genres,
                },
              );
            },
          ),
          if (_selectedPlaylist != null)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () {
                setState(() {
                  context
                      .read<PlaylistsModel>()
                      .removeAnimeFromPlaylist(_selectedPlaylist!, id);
                });
              },
            ),
        ],
      ),
    );
  }
}

class Anime {
  final int id;
  final String title;
  final String coverUrl;
  final List<String> genres;
  final String description;

  Anime({
    required this.id,
    required this.title,
    required this.coverUrl,
    required this.genres,
    required this.description,
  });

  factory Anime.fromGraphQL(Map<String, dynamic> json) => Anime(
    id: json['id'] as int,
    title: (json['title']?['romaji'] ?? '') as String,
    coverUrl: (json['coverImage']?['large'] ?? '') as String,
    genres: List<String>.from(json['genres'] ?? []),
    description: (json['description'] ?? '')
        .toString()
        .replaceAll(RegExp(r'<[^>]*>'), ''),
  );
}
