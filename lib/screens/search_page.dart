// lib/screens/search_page.dart

import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:anime_finder/screens/anime_detail_page.dart';

/// SearchPage now supports initial genre/tag filters for deep-linking.
class SearchPage extends StatefulWidget {
  /// Pre-select a genre filter when opening.
  final String? initialGenreFilter;
  /// Pre-select a tag filter when opening.
  final String? initialTagFilter;
  const SearchPage({Key? key, this.initialGenreFilter, this.initialTagFilter}) : super(key: key);

  @override
  _SearchPageState createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchController = TextEditingController();
  bool _loading = false;
  List<_Anime> _results = [];

  // Filter selections
  final Set<String> _selectedGenres = {};
  final Set<String> _selectedTags = {};

  // All filter options
  List<String> _allGenres = [];
  List<String> _allTags = [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {});
    });

    // Load filter options, then apply any initial filters and run search
    _fetchFilterOptions().then((_) {
      if (widget.initialGenreFilter != null && _allGenres.contains(widget.initialGenreFilter)) {
        _selectedGenres.add(widget.initialGenreFilter!);
      }
      if (widget.initialTagFilter != null && _allTags.contains(widget.initialTagFilter)) {
        _selectedTags.add(widget.initialTagFilter!);
      }
      // perform initial search with filters
      _performSearch();
    });
  }

  /// Fetches all genres and a sampling of tags for filter chips
  Future<void> _fetchFilterOptions() async {
    // Get AniList genres
    const genresQuery = '{ GenreCollection }';
    final gResp = await http.post(
      Uri.parse('https://graphql.anilist.co'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'query': genresQuery}),
    );
    if (gResp.statusCode == 200) {
      final data = json.decode(gResp.body)['data']['GenreCollection'] as List;
      _allGenres = List<String>.from(data)..sort();
    }

    // Get tags from a sample of anime
    const tagsQuery = '''
query {
  Page(page:1, perPage:50) {
    media(type:ANIME) { tags { name } }
  }
}''';
    final tResp = await http.post(
      Uri.parse('https://graphql.anilist.co'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'query': tagsQuery}),
    );
    if (tResp.statusCode == 200) {
      final media = json.decode(tResp.body)['data']['Page']['media'] as List;
      final tags = <String>{};
      for (var m in media) {
        for (var t in m['tags'] as List) {
          tags.add(t['name'] as String);
        }
      }
      _allTags = tags.toList()..sort();
    }

    setState(() {});
  }

  /// Executes a GraphQL search by title, then filters by genre/tag on client
  Future<void> _performSearch() async {
    final queryText = _searchController.text.trim();
    setState(() {
      _loading = true;
      _results = [];
    });

    const searchQuery = '''
query(\$search:String, \$page:Int, \$perPage:Int) {
  Page(page:\$page, perPage:\$perPage) {
    media(search:\$search, type:ANIME) {
      id
      title { romaji }
      coverImage { large }
      genres
      tags { name }
      description(asHtml:false)
    }
  }
}''';
    final resp = await http.post(
      Uri.parse('https://graphql.anilist.co'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'query': searchQuery,
        'variables': {
          'search': queryText.isEmpty ? null : queryText,
          'page': 1,
          'perPage': 50,
        },
      }),
    );
    if (resp.statusCode == 200) {
      final media = json.decode(resp.body)['data']['Page']['media'] as List;
      final items = media.map((e) => _Anime.fromJSON(e)).toList();
      final filtered = items.where((a) {
        if (_selectedGenres.isNotEmpty &&
            !_selectedGenres.any((g) => a.genres.contains(g))) return false;
        if (_selectedTags.isNotEmpty &&
            !_selectedTags.any((t) => a.tags.contains(t))) return false;
        return true;
      }).toList();
      setState(() {
        _results = filtered;
      });
    }

    setState(() {
      _loading = false;
    });
  }

  Future<void> _launchUrl(int id) async {
    final url = 'https://anilist.co/anime/$id';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open AniList page for ID $id')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search Anime')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search input
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: 'Search by title...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _performSearch(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: _performSearch, child: const Text('Search')),
              ],
            ),
          ),

          // Genre filters
          if (_allGenres.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text('Filter by Genre', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: _allGenres.map((g) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(g),
                    selected: _selectedGenres.contains(g),
                    onSelected: (sel) {
                      setState(() {
                        sel ? _selectedGenres.add(g) : _selectedGenres.remove(g);
                      });
                    },
                  ),
                )).toList(),
              ),
            ),
          ],

          // Tag filters
          if (_allTags.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text('Filter by Tag', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: _allTags.map((t) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(t),
                    selected: _selectedTags.contains(t),
                    onSelected: (sel) {
                      setState(() {
                        sel ? _selectedTags.add(t) : _selectedTags.remove(t);
                      });
                    },
                  ),
                )).toList(),
              ),
            ),
          ],

          const Divider(),

          // Results list
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
              itemCount: _results.length,
              itemBuilder: (ctx, i) {
                final a = _results[i];
                return ListTile(
                  leading: a.coverUrl.isNotEmpty
                      ? Image.network(a.coverUrl, width: 50, fit: BoxFit.cover)
                      : null,
                  title: Text(a.title),
                  subtitle: Text(
                    '${a.genres.join(', ')}\n${a.tags.join(', ')}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  isThreeLine: true,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AnimeDetailPage(id: a.id),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Internal model for search results (includes both genres & tags)
class _Anime {
  final int id;
  final String title;
  final String coverUrl;
  final List<String> genres;
  final List<String> tags;
  final String description;

  _Anime({
    required this.id,
    required this.title,
    required this.coverUrl,
    required this.genres,
    required this.tags,
    required this.description,
  });

  factory _Anime.fromJSON(Map<String, dynamic> json) {
    return _Anime(
      id: json['id'] as int,
      title: (json['title']?['romaji'] ?? '') as String,
      coverUrl: (json['coverImage']?['large'] ?? '') as String,
      genres: List<String>.from(json['genres'] ?? []),
      tags: (json['tags'] as List).map((t) => t['name'] as String).toList(),
      description: (json['description'] ?? '')
          .toString()
          .replaceAll(RegExp(r'<[^>]*>'), ''),
    );
  }
}
