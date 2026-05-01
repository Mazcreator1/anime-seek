// lib/screens/anime_detail_page.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:anime_finder/screens/search_page.dart';

class AnimeDetailPage extends StatefulWidget {
  final int id;
  final String? currentTier;
  final int? remainingSearches;

  const AnimeDetailPage({
    Key? key,
    required this.id,
    this.currentTier,
    this.remainingSearches,
  }) : super(key: key);

  @override
  _AnimeDetailPageState createState() => _AnimeDetailPageState();
}

class _AnimeDetailPageState extends State<AnimeDetailPage>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  Map<String, dynamic>? _anime;
  YoutubePlayerController? _ytController;
  late TabController _tabController;
  List<SimilarAnime> _similar = [];

  List<Character> _mainCharacters = [];
  List<Character> _supportingCharacters = [];
  bool _loadingCharacters = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _fetchDetail();
  }

  @override
  void dispose() {
    _ytController?.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchDetail() async {
    const query = r'''
query($id: Int) {
  Media(id: $id, type: ANIME) {
    id
    title { romaji native english }
    coverImage { large }
    bannerImage
    description(asHtml: false)
    season
    seasonYear
    episodes
    genres
    tags { name }
    trailer { id }
    recommendations(perPage: 10) {
      nodes {
        mediaRecommendation {
          id
          title { romaji }
          coverImage { large }
        }
      }
    }
  }
}
''';

    final resp = await http.post(
      Uri.parse('https://graphql.anilist.co'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'query': query, 'variables': {'id': widget.id}}),
    );

    if (resp.statusCode == 200) {
      final data = (json.decode(resp.body)['data']['Media']
      as Map<String, dynamic>);
      final trailer = data['trailer'] as Map<String, dynamic>?;
      if (trailer != null && trailer['id'] != null) {
        _ytController = YoutubePlayerController(
          initialVideoId: trailer['id'] as String,
          flags: const YoutubePlayerFlags(autoPlay: false),
        );
      }
      final recNodes = (data['recommendations']['nodes'] as List<dynamic>);
      _similar = recNodes.map((node) {
        final m = node['mediaRecommendation'] as Map<String, dynamic>;
        return SimilarAnime(
          id: m['id'] as int,
          title: m['title']['romaji'] as String,
          coverUrl: m['coverImage']['large'] as String,
        );
      }).toList();

      setState(() {
        _anime = data;
        _loading = false;
      });

      _fetchCharacters();
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _fetchCharacters() async {
    setState(() => _loadingCharacters = true);

    const charQuery = r'''
query($id: Int) {
  Media(id: $id) {
    characters(perPage: 50) {
      edges {
        role
        node {
          id
          name { full }
          image { large }
        }
      }
    }
  }
}
''';

    final resp = await http.post(
      Uri.parse('https://graphql.anilist.co'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'query': charQuery, 'variables': {'id': widget.id}}),
    );

    if (resp.statusCode == 200) {
      final edges = ((json.decode(resp.body)['data']['Media']
      ['characters']['edges'])
      as List<dynamic>)
          .cast<Map<String, dynamic>>();

      for (var edge in edges) {
        final role = edge['role'] as String;
        final node = edge['node'] as Map<String, dynamic>;
        final character = Character(
          id: node['id'] as int,
          name: node['name']['full'] as String,
          imageUrl: node['image']['large'] as String,
        );
        if (role == 'MAIN') {
          _mainCharacters.add(character);
        } else {
          _supportingCharacters.add(character);
        }
      }
    }

    setState(() => _loadingCharacters = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_anime != null
            ? (_anime!['title']['romaji'] ?? 'Anime')
            : 'Loading...'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _anime == null
          ? const Center(child: Text('Failed to load details.'))
          : Theme(
        data: Theme.of(context).copyWith(
          textTheme: Theme.of(context).textTheme.apply(
            bodyColor: Colors.white,
            displayColor: Colors.white,
          ),
        ),
        child: Stack(
          children: [
            // Banner as background (cover)
            if ((_anime!['bannerImage'] as String?)?.isNotEmpty ==
                true)
              Positioned.fill(
                child: Image.network(
                  _anime!['bannerImage'] as String,
                  fit: BoxFit.cover,
                ),
              ),
            // Dark overlay
            Positioned.fill(
              child: Container(color: Colors.black.withOpacity(0.5)),
            ),
            // Foreground content
            Column(
              children: [
                const SizedBox(height: 8),
                TabBar(
                  controller: _tabController,
                  indicatorColor: Colors.amber,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white70,
                  tabs: const [
                    Tab(text: 'Info'),
                    Tab(text: 'Trailer'),
                    Tab(text: 'Similar'),
                    Tab(text: 'Characters'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildInfoTab(),
                      _buildTrailerTab(),
                      _buildSimilarTab(),
                      _buildCharactersTab(),
                    ],
                  ),
                )
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoTab() {
    final rawDesc = (_anime!['description'] as String? ?? '')
        .replaceAll(RegExp(r'<br\s*/?>'), '\n');
    final cleanDesc = rawDesc.replaceAll(RegExp(r'<[^>]*>'), '').trim();
    final seriesInfo =
        '${_anime!['season']} ${_anime!['seasonYear']} • ${_anime!['episodes']} Episodes';
    final fullDesc =
        '$seriesInfo\n\n${cleanDesc.isNotEmpty ? cleanDesc : 'No description.'}';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.currentTier != null && widget.remainingSearches != null)
            Card(
              color: Colors.grey[100],
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text('Tier:', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text('${widget.currentTier}'),
                        Text('|'),
                        Text('Searches left:', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text('${widget.remainingSearches}'),
                      ],
                    ),
                    if (widget.remainingSearches == 0) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Please upgrade for a higher limit!',
                        style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          Text(
            _anime!['title']['english'] ?? _anime!['title']['romaji'],
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            _anime!['title']['native'] ?? '',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 12),
          Text(fullDesc,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.white)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: (_anime!['genres'] as List<dynamic>)
                .map((g) => ActionChip(
              label: Text(g as String),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        SearchPage(initialGenreFilter: g as String)),
              ),
            ))
                .toList(),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: (_anime!['tags'] as List<dynamic>)
                .map((t) => ActionChip(
              label: Text((t as Map)['name'] as String),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => SearchPage(
                        initialTagFilter: (t)['name'] as String)),
              ),
            ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTrailerTab() {
    return Center(
      child: _ytController != null
          ? YoutubePlayer(controller: _ytController!)
          : const Text('No trailer available.'),
    );
  }

  Widget _buildSimilarTab() {
    if (_similar.isEmpty) {
      return const Center(child: Text('No similar anime found.'));
    }
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(16),
      itemCount: _similar.length,
      itemBuilder: (_, i) {
        final s = _similar[i];
        return GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AnimeDetailPage(
                id: s.id, // s is SimilarAnime
              ),
            ),
          ),
          child: Container(
            width: 140,
            margin: const EdgeInsets.only(right: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    s.coverUrl,
                    width: 140,
                    height: 200,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  s.title,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Colors.white),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCharactersTab() {
    if (_loadingCharacters) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_mainCharacters.isEmpty && _supportingCharacters.isEmpty) {
      return const Center(child: Text('No characters found.'));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_mainCharacters.isNotEmpty) ...[
            Text('Main Characters',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(color: Colors.white)),
            const SizedBox(height: 8),
            SizedBox(
              height: 240,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _mainCharacters.length,
                itemBuilder: (_, i) =>
                    _buildCharacterCard(_mainCharacters[i]),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (_supportingCharacters.isNotEmpty) ...[
            Text('Supporting Characters',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(color: Colors.white)),
            const SizedBox(height: 8),
            SizedBox(
              height: 240,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _supportingCharacters.length,
                itemBuilder: (_, i) =>
                    _buildCharacterCard(_supportingCharacters[i]),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCharacterCard(Character c) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => CharacterDetailPage(id: c.id)),
      ),
      child: Container(
        width: 120,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                c.imageUrl,
                width: 100,
                height: 100,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Text(
                c.name,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.white),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---- Supporting classes ----

class SimilarAnime {
  final int id;
  final String title;
  final String coverUrl;
  SimilarAnime({
    required this.id,
    required this.title,
    required this.coverUrl,
  });
}

class Character {
  final int id;
  final String name;
  final String imageUrl;
  Character({
    required this.id,
    required this.name,
    required this.imageUrl,
  });
}

// ---- Minimal stub for CharacterDetailPage ----

class CharacterDetailPage extends StatefulWidget {
  final int id;
  const CharacterDetailPage({Key? key, required this.id}) : super(key: key);

  @override
  _CharacterDetailPageState createState() => _CharacterDetailPageState();
}

class _CharacterDetailPageState extends State<CharacterDetailPage> {
  bool _loading = true;
  Map<String, dynamic>? _character;

  @override
  void initState() {
    super.initState();
    _fetchCharacter();
  }

  Future<void> _fetchCharacter() async {
    const query = r'''
query($id: Int) {
  Character(id: $id) {
    id
    name { full native alternative }
    image { large }
    description(asHtml: false)
    media { edges { node { id title { romaji } } } }
  }
}
''';
    final resp = await http.post(
      Uri.parse('https://graphql.anilist.co'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'query': query, 'variables': {'id': widget.id}}),
    );
    if (resp.statusCode == 200) {
      setState(() {
        _character = json.decode(resp.body)['data']['Character']
        as Map<String, dynamic>;
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_character != null
            ? _character!['name']['full'] as String
            : 'Loading...'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _character == null
          ? const Center(child: Text('Failed to load character.'))
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                _character!['image']['large'] as String,
                height: 240,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _character!['name']['native'] != null &&
                  (_character!['name']['native'] as String)
                      .isNotEmpty
                  ? _character!['name']['native'] as String
                  : _character!['name']['full'] as String,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              _character!['description'] as String? ?? 'No bio.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Text('Appears in:',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (var edge
            in (_character!['media']['edges'] as List))
              ListTile(
                title: Text(edge['node']['title']['romaji']
                as String),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        AnimeDetailPage(id: edge['node']['id']),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
