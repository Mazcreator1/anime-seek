import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:anime_finder/models/favorites_model.dart';
import 'package:anime_finder/models/playlist_model.dart';


class PlaylistPage extends StatelessWidget {
  final String name;
  const PlaylistPage({Key? key, required this.name}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final songs = context.watch<PlaylistsModel>().songs(name);
    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              final text = songs.map((m) {
                final title = m['anime']?['title'] ?? m['anime_title'] ?? '';
                final song  = m['song_name'] ?? '';
                return '$song — $title';
              }).join('\n');
              Share.share(text, subject: 'My Playlist: $name');
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('Delete Playlist?'),
                content: Text('Are you sure you want to delete "$name"?'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  ElevatedButton(
                    onPressed: () {
                      context.read<PlaylistsModel>().delete(name);
                      Navigator.pop(context); // close dialog
                      Navigator.pop(context); // back to Favorites
                    },
                    child: const Text('Delete'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: songs.isEmpty
          ? const Center(child: Text('No songs in this playlist.'))
          : ListView.builder(
        itemCount: songs.length,
        itemBuilder: (_, i) {
          final m = songs[i];
          final cover = m['anime']?['cover_url'];
          return ListTile(
            leading: cover != null
                ? Image.network(cover, width: 50, fit: BoxFit.cover)
                : const Icon(Icons.music_note),
            title: Text(m['song_name'] ?? ''),
            subtitle: Text(m['anime']?['title'] ?? ''),
          );
        },
      ),
    );
  }
}
