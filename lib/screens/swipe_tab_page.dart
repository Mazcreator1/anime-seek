// lib/screens/swipe_tab_page.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:anime_finder/screens/history_page.dart';
import 'package:anime_finder/screens/favorites_page.dart';
// 👇 Make sure this matches the actual file name where DiscoverPage lives
import 'package:anime_finder/screens/Discover_Page.dart';
import 'package:anime_finder/screens/analytics_page.dart';
import 'package:anime_finder/screens/discord_page.dart';
import 'package:anime_finder/screens/trace_Search_page.dart';
import 'package:anime_finder/screens/subscription_screen.dart';
import 'package:anime_finder/screens/signup.dart';

class SwipeTabPage extends StatefulWidget {
  const SwipeTabPage({Key? key}) : super(key: key);

  @override
  State<SwipeTabPage> createState() => _SwipeTabPageState();
}

class _SwipeTabPageState extends State<SwipeTabPage> with TickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
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
        title: const Text('Library'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.history), text: 'History'),
            Tab(icon: Icon(Icons.star), text: 'Favorites'),
            Tab(icon: Icon(Icons.explore), text: 'Discover'),
            Tab(icon: Icon(Icons.analytics), text: 'Analytics'),
            Tab(icon: Icon(Icons.chat), text: 'Discord'),
            Tab(icon: Icon(Icons.search), text: 'TraceAnime'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          HistoryPage(),
          FavoritesPage(),
          DiscoverPage(),
          AnalyticsPage(),
          DiscordPage(),
          TraceSearchPage(),
        ],
      ),
    );
  }
}
