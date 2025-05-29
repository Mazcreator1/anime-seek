import 'package:flutter/material.dart';

/// A swipeable page exposing three tabs: Analytics, Playlists, Search
class TabbedPage extends StatelessWidget {
  const TabbedPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.transparent,
          bottom: TabBar(
            labelColor: Colors.blue,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.blue,
            tabs: const [
              Tab(text: 'Analytics'),
              Tab(text: 'Playlists'),
              Tab(text: 'Search'),
            ],
          ),
        ),
        body: const TabBarView(
          physics: BouncingScrollPhysics(),
          children: [
            // TODO: Replace these Containers with your actual pages
            Center(child: Text('Analytics Content')),
            Center(child: Text('Playlists Content')),
            Center(child: Text('Search Content')),
          ],
        ),
      ),
    );
  }
}
