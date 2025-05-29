// lib/screens/swipe_tab_page.dart

import 'package:flutter/material.dart';

class SwipeTabPage extends StatelessWidget {
  const SwipeTabPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("More Features"),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.analytics), text: "Analytics"),
              Tab(icon: Icon(Icons.library_music), text: "Playlists"),
              Tab(icon: Icon(Icons.search), text: "Search"),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            Center(child: Text("Analytics page")),
            Center(child: Text("Playlist management")),
            Center(child: Text("Search and add to playlist")),
          ],
        ),
      ),
    );
  }
}