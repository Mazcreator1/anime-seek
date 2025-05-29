import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:audioplayers/audioplayers.dart';
import '../services/audio_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'playlist_page.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  // Unified backend port
  final _baseUrl = 'http://10.0.2.2:8028';
  final AudioPlayer _audioPlayer = AudioPlayer();
  List<dynamic> _results = [];
  List<dynamic> _playlists = [];
  Set<int> _selectedPlaylistIds = {};
  Timer? _debounce;
  String _sortBy = 'song_name';
  bool _showPlaylists = true;
  String? _filterPlatform;
  String? _filterArtist;

  @override
  void initState() {
    super.initState();
    _fetchPlaylists();
    _controller.addListener(_onSearchChanged);
  }

  final Set<String> _favorites = {};

  void _toggleFavorite(String songName) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (_favorites.contains(songName)) {
        _favorites.remove(songName);
      } else {
        _favorites.add(songName);
      }
      prefs.setStringList('favorites', _favorites.toList());
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onSearchChanged);
    _controller.dispose();
    _audioPlayer.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _search(_controller.text);
    });
  }

  Future<void> _fetchPlaylists() async {
    final response = await http.get(Uri.parse('$_baseUrl/playlists'));
    if (response.statusCode == 200) {
      setState(() {
        _playlists = json.decode(response.body);
      });
    }
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }

    final response = await http.get(Uri.parse('$_baseUrl/search?q=$query'));
    if (response.statusCode == 200) {
      final decoded = json.decode(response.body);
      final rawResults = decoded is Map && decoded.containsKey('results')
          ? decoded['results']
          : decoded;

      // Apply filters locally
      final filtered = rawResults.where((song) {
        final platformMatch = _filterPlatform == null || song['streaming_service'] == _filterPlatform;
        final artistMatch = _filterArtist == null || song['artist'] == _filterArtist;
        return platformMatch && artistMatch;
      }).toList();

      filtered.sort((a, b) => a[_sortBy].toString().compareTo(b[_sortBy].toString()));
      setState(() => _results = filtered);
    }
  }

  Future<void> _addToPlaylist(AudioService svc, Map<String, dynamic> song) async {
    if (_selectedPlaylistIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one playlist')),
      );
      return;
    }

    for (final playlistId in _selectedPlaylistIds) {
      // Check existing songs
      final checkRes = await http.get(Uri.parse('$_baseUrl/playlists/$playlistId/songs'));
      if (checkRes.statusCode == 200) {
        final existing = json.decode(checkRes.body) as List;
        final exists = existing.any((s) => s['song_name'] == song['song_name']);
        if (exists) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Song already exists in playlist')),
          );
          continue;
        }
      }

      final res = await http.post(
        Uri.parse('$_baseUrl/playlists/add'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'playlist_id': playlistId,
          'song_name': song['song_name'],
          'duration': song['duration'] ?? 0,
        }),
      );

      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added "${song['song_name']}" to playlist')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add "${song['song_name']}"')),
        );
      }
    }
  }

  void _playPreview(String url) async {
    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(UrlSource(url));
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to play preview')),
      );
    }
  }

  Widget _platformIcon(String? service) {
    switch (service?.toLowerCase()) {
      case 'spotify':
        return const Icon(Icons.music_note, color: Colors.green);
      case 'youtube':
        return const Icon(Icons.ondemand_video, color: Colors.red);
      default:
        return const Icon(Icons.audiotrack, color: Colors.grey);
    }
  }

  @override
  Widget build(BuildContext context) {
    final svc = Provider.of<AudioService>(context);

    final platforms = _results.map((s) => s['streaming_service'] as String?).whereType<String>().toSet().toList();
    final artists = _results.map((s) => s['artist'] as String?).whereType<String>().toSet().toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Search'),
        actions: [
          IconButton(
            icon: const Icon(Icons.queue_music),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PlaylistPage()),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            ListTile(
              title: Text('Select Playlists (${_playlists.length})'),
              trailing: Icon(_showPlaylists ? Icons.expand_less : Icons.expand_more),
              onTap: () => setState(() => _showPlaylists = !_showPlaylists),
            ),
            if (_showPlaylists)
              SizedBox(
                height: 200,
                child: SingleChildScrollView(
                  child: Column(
                    children: _playlists.map((playlist) {
                      return CheckboxListTile(
                        title: Text(playlist['name']),
                        value: _selectedPlaylistIds.contains(playlist['id']),
                        onChanged: (selected) {
                          setState(() {
                            if (selected == true) {
                              _selectedPlaylistIds.add(playlist['id']);
                            } else {
                              _selectedPlaylistIds.remove(playlist['id']);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: 'Search song or artist...',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _sortBy,
                  items: const [
                    DropdownMenuItem(value: 'song_name', child: Text('Name')),
                    DropdownMenuItem(value: 'artist', child: Text('Artist')),
                    DropdownMenuItem(value: 'streaming_service', child: Text('Platform')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _sortBy = value);
                      _search(_controller.text);
                    }
                  },
                ),
              ],
            ),
            Row(
              children: [
                if (platforms.isNotEmpty)
                  DropdownButton<String>(
                    hint: const Text('Filter by Platform'),
                    value: _filterPlatform,
                    onChanged: (value) => setState(() {
                      _filterPlatform = value;
                      _search(_controller.text);
                    }),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All')),
                      ...platforms.map((p) => DropdownMenuItem(value: p, child: Text(p))),
                    ],
                  ),
                const SizedBox(width: 10),
                if (artists.isNotEmpty)
                  DropdownButton<String>(
                    hint: const Text('Filter by Artist'),
                    value: _filterArtist,
                    onChanged: (value) => setState(() {
                      _filterArtist = value;
                      _search(_controller.text);
                    }),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All')),
                      ...artists.map((a) => DropdownMenuItem(value: a, child: Text(a))),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _results.isEmpty
                  ? const Center(child: Text("No results"))
                  : ListView.builder(
                itemCount: _results.length,
                itemBuilder: (context, index) {
                  final song = _results[index];
                  final isFav = _favorites.contains(song['song_name']);
                  return Card(
                    child: ListTile(
                      leading: _platformIcon(song['streaming_service']),
                      title: Text(song['song_name']),
                      subtitle: Wrap(
                        spacing: 8,
                        children: [
                          Chip(label: Text(song['artist'] ?? 'Unknown')),
                          Chip(label: Text('/${song['duration'] ?? 0}s')),
                        ],
                      ),
                      trailing: Wrap(
                        spacing: 8,
                        children: [
                          IconButton(
                            icon: Icon(isFav ? Icons.star : Icons.star_border,
                                color: isFav ? Colors.amber : null),
                            onPressed: () => _toggleFavorite(song['song_name']),
                          ),
                          if (song['audio_url'] != null)
                            IconButton(
                                icon: const Icon(Icons.play_arrow),
                                onPressed: () => _playPreview(song['audio_url'])),
                          IconButton(
                              icon: const Icon(Icons.playlist_add),
                              onPressed: () => _addToPlaylist(svc, song)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          setState(() {
            _controller.clear();
            _results.clear();
            _filterPlatform = null;
            _filterArtist = null;
          });
        },
        child: const Icon(Icons.clear),
        tooltip: 'Clear search & filters',
      ),
    );
  }
}
