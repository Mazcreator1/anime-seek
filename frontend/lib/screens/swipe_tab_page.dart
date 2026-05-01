import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;

import 'package:anime_finder/services/api_service.dart';
import 'package:anime_finder/services/auth_service.dart';
import 'package:anime_finder/models/analytics_model.dart';

// Core app pages
import 'feed_page.dart';
import 'Discover_Page.dart';
import 'history_page.dart';
import 'favorites_page.dart';
import 'analytics_page.dart';
import 'discord_page.dart';
import 'my_account_page.dart';
import 'profile_page.dart';
import 'discover_profiles_page.dart';
import 'character_creator_page.dart';

import 'package:anime_finder/screens/settings_page.dart';

// import 'package:anime_finder/screens/markets/markets_list_page.dart';

class SwipeTabPage extends StatefulWidget {
  const SwipeTabPage({Key? key}) : super(key: key);

  @override
  State<SwipeTabPage> createState() => _SwipeTabPageState();
}

class _SwipeTabPageState extends State<SwipeTabPage>
    with TickerProviderStateMixin {
  late final TabController _tabController;

  late final List<Tab> _tabs = <Tab>[
    const Tab(text: 'Feed'),
    const Tab(text: 'Profile'),
    const Tab(text: 'Discover Profiles'),
    const Tab(text: 'History'),
    const Tab(text: 'Favorites'),
    const Tab(text: 'Discover Anime'),

    const Tab(text: 'Character Creator'),
    const Tab(text: 'Analytics'),
    const Tab(text: 'Discord'),
    const Tab(text: 'Account'),
    const Tab(text: 'Settings'),
  ];

  late final List<Widget> _pages = <Widget>[
    const FeedPage(),

    FutureBuilder<http.Response>(
      future: AuthService.me(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || snapshot.data?.statusCode != 200) {
          return const Center(child: Text('Failed to load profile.'));
        }
        final data = jsonDecode(snapshot.data!.body) as Map<String, dynamic>;
        final id = (data['id'] as num?)?.toInt() ?? 0;
        return ProfilePage(userId: id);
      },
    ),

    const DiscoverProfilesPage(),
    const HistoryPage(),
    const FavoritesPage(),
    const DiscoverPage(),
   
    const CharacterCreatorPage(),
    ChangeNotifierProvider<AnalyticsModel>(
      create: (_) => AnalyticsModel(),
      child: const AnalyticsPage(),
    ),
    const DiscordPage(),
    const MyAccountPage(),
    SettingsPage(),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: const Text('Library'),
      bottom: TabBar(
        controller: _tabController,
        isScrollable: true,
        tabs: _tabs,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: TabBarView(
        controller: _tabController,
        children: _pages,
      ),
    );
  }
}