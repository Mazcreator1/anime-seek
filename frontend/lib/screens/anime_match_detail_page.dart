// lib/screens/anime_match_detail_page.dart

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';

import 'package:anime_finder/services/audio_service.dart';
import 'package:anime_finder/models/favorites_model.dart';
import 'package:anime_finder/screens/swipe_tab_page.dart';
import 'package:anime_finder/screens/history_page.dart';
import 'package:anime_finder/screens/favorites_page.dart';
import 'package:anime_finder/screens/search_page.dart';
import 'package:anime_finder/screens/analytics_page.dart';
import 'package:anime_finder/screens/discord_page.dart';


class AnimeMatchDetailPage extends StatefulWidget {
  final Map<String, dynamic> anime;
  final String? currentTier;
  final int? remainingSearches;
  const AnimeMatchDetailPage({
    Key? key,
    required this.anime,
    this.currentTier,
    this.remainingSearches,
  }) : super(key: key);

  @override
  _AnimeMatchDetailPageState createState() => _AnimeMatchDetailPageState();
}

class _AnimeMatchDetailPageState extends State<AnimeMatchDetailPage> {
  late AudioPlayer _previewPlayer;
  YoutubePlayerController? _ytController;
  bool _isPreviewPlaying = false;

  @override
  void initState() {
    super.initState();
    _previewPlayer = AudioPlayer();

    // Prepare YouTube player if URL present
    final youTubeUrl = widget.anime['youtube_url'] as String?;
    if (youTubeUrl != null && youTubeUrl.isNotEmpty) {
      final videoId = YoutubePlayer.convertUrlToId(youTubeUrl);
      if (videoId != null) {
        _ytController = YoutubePlayerController(
          initialVideoId: videoId,
          flags: const YoutubePlayerFlags(autoPlay: false),
        );
      }
    }
  }

  @override
  void dispose() {
    _previewPlayer.dispose();
    _ytController?.dispose();
    super.dispose();
  }

  Future<void> _togglePreview() async {
    final previewUrl = widget.anime['preview_url'] as String?;
    if (previewUrl == null || previewUrl.isEmpty) return;

    if (!_isPreviewPlaying) {
      try {
        await _previewPlayer.setUrl(previewUrl);
        await _previewPlayer.play();
        setState(() => _isPreviewPlaying = true);
        _previewPlayer.playerStateStream.listen((state) {
          if (state.processingState == ProcessingState.completed) {
            setState(() => _isPreviewPlaying = false);
          }
        });
      } catch (e) {
        debugPrint('Preview play error: $e');
      }
    } else {
      await _previewPlayer.stop();
      setState(() => _isPreviewPlaying = false);
    }
  }

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Could not launch URL')));
    }
  }

  @override
  Widget build(BuildContext context) {
    // The raw AniList data may be nested under `anime` or already flattened.

    final m = widget.anime;
    final dynamic animeField = m['anime'];
    final Map<String, dynamic> rawAnime = animeField is Map<String, dynamic>
        ? animeField
        : m;

    final favModel = context.watch<FavoritesModel>();
    final songName = (m['song_name'] as String?) ?? '';
    final isFav = songName.isNotEmpty && favModel.isFavorite(songName);

    // Pull all display fields from rawAnime
    final coverUrl   = rawAnime['cover_url']    as String?;
    final title      = rawAnime['title']        as String?;
    final romaji     = rawAnime['title_romaji'] as String?;
    final native     = rawAnime['title_native'] as String?;
    final description= rawAnime['description']  as String?;
    final season     = rawAnime['season']       as String?;
    final year       = rawAnime['year']         as int?;
    final format     = rawAnime['type']         as String?;
    final genres     = List<String>.from(rawAnime['genres'] ?? []);
    final tags       = List<String>.from(rawAnime['tags']   ?? []);
    final previewUrl = rawAnime['preview_url']  as String?;
    final youtubeUrl = rawAnime['youtube_url']  as String?;
    final spotifyUrl = rawAnime['spotify_url']  as String?;
    final videoUrl   = rawAnime['video_url']    as String?;
    final artistName = rawAnime['artist']       as String?;
    final opEdType   = rawAnime['op_ed_type']   as String?;

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity != null &&
            details.primaryVelocity! < 0) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SwipeTabPage()),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(title ?? romaji ?? 'Anime Match'),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // Cover art
              Center(
                child: coverUrl != null && coverUrl.isNotEmpty
                    ? Image.network(coverUrl, height: 240, fit: BoxFit.cover)
                    : const Icon(Icons.broken_image, size: 100),
              ),
              const SizedBox(height: 12),

              // YouTube embed
              if (_ytController != null) ...[
                YoutubePlayer(controller: _ytController!),
                const SizedBox(height: 12),
              ],

              // Titles
              Text(
                romaji ?? native ?? title ?? '',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                '${season ?? '-'} ${year ?? ''} • ${format ?? '-'}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),

              // Match fields
              if (songName.isNotEmpty) Text('Song Name: $songName'),
              if (artistName != null) Text('Artist: $artistName'),
              if (opEdType   != null) Text('OP/ED Type: $opEdType'),
              const SizedBox(height: 12),

              // Description
              Text(
                description ?? 'No description available.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),

              // Genres
              if (genres.isNotEmpty) ...[
                Text('Genres:', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: genres.map((g) => ActionChip(
                    label: Text(g),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SearchPage(initialTagFilter: g),
                      ),
                    ),
                  )).toList(),
                ),
                const SizedBox(height: 16),
              ],

              // Tags
              if (tags.isNotEmpty) ...[
                Text('Tags:', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: tags.map((t) => ActionChip(
                    label: Text(t),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SearchPage(initialTagFilter: t),
                      ),
                    ),
                  )).toList(),
                ),
                const SizedBox(height: 16),
              ],

              // Preview button
              if (previewUrl != null && previewUrl.isNotEmpty) ...[
                Center(
                  child: ElevatedButton.icon(
                    icon: Icon(_isPreviewPlaying ? Icons.pause : Icons.play_arrow),
                    label: Text(_isPreviewPlaying ? 'Stop Preview' : 'Play Preview'),
                    onPressed: _togglePreview,
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // External links
              Wrap(spacing: 8, children: [
                if (youtubeUrl != null && youtubeUrl.isNotEmpty)
                  ActionChip(
                    avatar: const Icon(Icons.video_library),
                    label: const Text('YouTube'),
                    onPressed: () => _launch(youtubeUrl),
                  ),
                if (spotifyUrl != null && spotifyUrl.isNotEmpty)
                  ActionChip(
                    avatar: const Icon(Icons.music_note),
                    label: const Text('Spotify'),
                    onPressed: () => _launch(spotifyUrl),
                  ),
                if (videoUrl != null && videoUrl.isNotEmpty)
                  ActionChip(
                    avatar: const Icon(Icons.link),
                    label: const Text('Other Video'),
                    onPressed: () => _launch(videoUrl),
                  ),
              ]),
              if (widget.currentTier != null && widget.remainingSearches != null) ...[
                Card(
                  color: Colors.grey[100],
                  margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          'Tier: ${widget.currentTier}   |   Searches left: ${widget.remainingSearches}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        if (widget.remainingSearches == 0) ...[
                          const SizedBox(height: 8),
                          const Text(
                            'Please upgrade for a higher limit!',
                            style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              const SizedBox(height: 16),
              const Center(
                child: Text('Swipe left to continue', style: TextStyle(color: Colors.grey)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
