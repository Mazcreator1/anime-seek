
import 'package:flutter/material.dart';
import 'screens/analytics_page.dart';
import 'screens/playlist_page.dart';
import 'screens/search_page.dart';

class SwipeTabPage extends StatefulWidget {
  const SwipeTabPage({Key? key}) : super(key: key);

  @override
  State<SwipeTabPage> createState() => _SwipeTabPageState();
}

class _SwipeTabPageState extends State<SwipeTabPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Explore"),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: "Analytics"),
            Tab(text: "Playlists"),
            Tab(text: "Search"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          AnalyticsPage(),
          PlaylistPage(),
          SearchPage(),
        ],
      ),
    );
  }
}
