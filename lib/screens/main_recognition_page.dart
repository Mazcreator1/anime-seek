import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:anime_finder/services/audio_service.dart';
import 'package:anime_finder/screens/anime_match_detail_page.dart';  // ← import detail page
import 'package:anime_finder/screens/swipe_tab_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<AudioService>();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final metadata = svc.animeMetadata;               // ← use the real getter
      if (metadata != null) {
        svc.clearAnimeMetadata();
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => AnimeMatchDetailPage(anime: metadata),
        ));
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Anime OP Finder'),
        centerTitle: true,
      ),
      body: GestureDetector(
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity != null && details.primaryVelocity! < 0) {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SwipeTabPage()),
            );
          }
        },
        onVerticalDragEnd: (_) => svc.resetUI(),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Record / Stop
                ElevatedButton.icon(
                  key: ValueKey<bool>(svc.isRecording),
                  onPressed:
                  svc.isRecording ? svc.stopRecording : svc.startRecording,
                  icon: Icon(svc.isRecording ? Icons.stop : Icons.mic),
                  label: Text(
                      svc.isRecording ? 'Stop Recording' : 'Start Recording'),
                ),
                const SizedBox(height: 12),
                // Timer
                AnimatedOpacity(
                  opacity: svc.isRecording ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: Text('⏺️ Recording: ${svc.fmtDuration}'),
                ),
                const SizedBox(height: 24),
                // Send & Play
                if (svc.hasRecording) ...[
                  ElevatedButton(
                    onPressed:
                    svc.isRecording || svc.isLoading ? null : svc.sendAudio,
                    child: svc.isLoading
                        ? const SizedBox(
                      width: 24,
                      height: 24,
                      child:
                      CircularProgressIndicator(strokeWidth: 2),
                    )
                        : const Text('Send to Backend'),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed:
                    svc.isRecording || svc.isLoading ? null : svc.playRecording,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Play Recording'),
                  ),
                ],
                const SizedBox(height: 32),
                // Title / Info / Error
                if (svc.title != null || svc.error != null) ...[
                  Card(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            svc.title ?? 'No match found',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          if (svc.info != null) ...[
                            const SizedBox(height: 8),
                            Text(svc.info!),
                          ],
                          if (svc.error != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              '⚠️ ${svc.error}',
                              style: const TextStyle(color: Colors.red),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// This wrapper stays the same
class MainRecognitionPage extends StatelessWidget {
  const MainRecognitionPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) => const HomePage();
}
