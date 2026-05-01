// lib/screens/main_recognition_page.dart
//
// Audio is temporarily disabled (commented out) per request.
// This page now shows ONLY the Scene/Search tab, and keeps the swipe-left
// behavior to open SwipeTabPage.

import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import 'package:anime_finder/services/audio_service.dart';
// import 'package:anime_finder/screens/anime_match_detail_page.dart';
import 'package:anime_finder/screens/trace_Search_page.dart';
import 'package:anime_finder/screens/swipe_tab_page.dart';

class MainRecognitionPage extends StatelessWidget {
  const MainRecognitionPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Audio disabled: single-tab view for Scene Seek only.
    return Scaffold(
      appBar: AppBar(
        title: const Text('Anime Seek'),
        centerTitle: true,
      ),
      body: const _SceneSwipeWrapper(),
    );
  }
}

/* ===========================
   AUDIO TAB (DISABLED FOR NOW)
   ===========================

class _AudioTab extends StatelessWidget {
  const _AudioTab({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<AudioService>();

    // Whenever we get metadata, navigate to detail page
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final metadata = svc.animeMetadata;
      if (metadata != null) {
        svc.clearAnimeMetadata();
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => AnimeMatchDetailPage(
            anime: metadata,
            currentTier: svc.currentTier,
            remainingSearches: svc.remainingSearches,
          ),
        ));
      }
    });

    // Only vertical drags here; horizontal swipes go to TabBarView
    return GestureDetector(
      onVerticalDragEnd: (_) => svc.resetUI(),
      behavior: HitTestBehavior.translucent,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Record / Stop button
              ElevatedButton.icon(
                key: ValueKey<bool>(svc.isRecording),
                onPressed: svc.isRecording
                    ? svc.stopRecording
                    : svc.startRecording,
                icon: Icon(svc.isRecording ? Icons.stop : Icons.mic),
                label: Text(
                    svc.isRecording ? 'Stop Recording' : 'Start Recording'),
              ),
              const SizedBox(height: 12),

              // Live timer
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
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Send to Backend'),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: svc.isRecording || svc.isLoading
                      ? null
                      : svc.playRecording,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Play Recording'),
                ),
                const SizedBox(height: 32),
              ],

              // Show tier & remaining searches
              if (svc.currentTier != null && svc.remainingSearches != null) ...[
                Card(
                  color: Colors.grey[100],
                  margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
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
                            Text('${svc.currentTier}'),
                            Text('|'),
                            Text('Searches left:', style: TextStyle(fontWeight: FontWeight.bold)),
                            Text('${svc.remainingSearches}'),
                          ],
                        ),
                        // Info, upgrade, and error all inside the tier card
                        if (svc.info != null) ...[
                          const SizedBox(height: 8),
                          Text(svc.info!, style: TextStyle(color: Colors.teal[700])),
                        ],
                        if (svc.remainingSearches == 0) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Please upgrade for a higher limit!',
                            style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                        ],
                        if (svc.error != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            '⚠️ ${svc.error}',
                            style: const TextStyle(color: Colors.red),
                            textAlign: TextAlign.center,
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
    );
  }
}

*/

/// Wraps Scene Seek in a detector that on swipe-left pushes to SwipeTabPage.
class _SceneSwipeWrapper extends StatelessWidget {
  const _SceneSwipeWrapper({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (details) {
        // negative velocity = user swiped left
        if (details.primaryVelocity != null && details.primaryVelocity! < 0) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SwipeTabPage()),
          );
        }
      },
      child: const TraceSearchPage(),
    );
  }
}