import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:anime_finder/models/favorites_model.dart';
import 'package:anime_finder/screens/search_page.dart';
import 'package:anime_finder/screens/anime_detail_page.dart';

class Anime {
  final int id;
  final String title;
  final String coverUrl;
  final List<String> genres;
  final String description;

  Anime({
    required this.id,
    required this.title,
    required this.coverUrl,
    required this.genres,
    required this.description,
  });

  factory Anime.fromGraphQL(Map<String, dynamic> json) => Anime(
    id: json['id'] as int,
    title: (json['title']?['romaji'] ?? '') as String,
    coverUrl: (json['coverImage']?['large'] ?? '') as String,
    genres: List<String>.from(json['genres'] ?? []),
    description: (json['description'] ?? '')
        .toString()
        .replaceAll(RegExp(r'<[^>]*>'), ''),
  );
}

class DiscoverPage extends StatefulWidget {
  const DiscoverPage({Key? key}) : super(key: key);
  @override
  _DiscoverPageState createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage>
    with TickerProviderStateMixin {
  late TabController _tabController;
  late List<String> _tabTitles;
  final String _season = 'Spring';
  late String _upcomingSeason;
  final int _year = DateTime.now().year;
  late int _upcomingYear;
  final String _apiUrl = 'https://graphql.anilist.co';

  bool _loading = false;
  List<bool> _hasMore = List.filled(9, true);
  List<int> _currentPage = List.filled(9, 1);
  final List<List<Anime>> _lists = List.generate(9, (_) => []);

  @override
  void initState() {
    super.initState();
    const seasons = ['WINTER', 'SPRING', 'SUMMER', 'FALL'];
    int idx = seasons.indexOf(_season.toUpperCase());
    _upcomingSeason = seasons[(idx + 1) % seasons.length];
    _upcomingYear = (idx == seasons.length - 1) ? _year + 1 : _year;

    _computeTabTitles();
    _scheduleTitleUpdate();

    _tabController = TabController(length: 9, vsync: this)
      ..addListener(() {
        if (!_loading && _lists[_tabController.index].isEmpty) {
          _refreshCurrentTab();
        }
      });

    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshCurrentTab());
  }

  void _computeTabTitles() {
    final now = DateTime.now();
    const mn = [
      'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    final today = '${mn[now.month - 1]} ${now.day}';
    _tabTitles = [
      'Upcoming $_upcomingSeason $_upcomingYear',
      'Seasonal $_season $_year',
      'Top 10 $_season $_year',
      'Recommended',
      'Hits of $today',
      'Make You Cry',
      'Action Picks',
      'Scary',
      'Gore',
    ];
  }

  void _scheduleTitleUpdate() {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    Timer(tomorrow.difference(now), () {
      setState(_computeTabTitles);
      _scheduleTitleUpdate();
    });
  }

  Future<void> _refreshCurrentTab() async {
    int i = _tabController.index;
    _currentPage[i] = 1;
    _hasMore[i] = true;
    _lists[i].clear();
    await _fetchPage(i);
  }

  Future<void> _fetchPage(int index) async {
    if (!_hasMore[index] || _loading) return;
    setState(() => _loading = true);

    String query = '';
    Map<String, dynamic> vars = {};

    switch (index) {
      case 0:
      case 1:
        query = '''
          query(\$page:Int,\$per:Int,\$season:MediaSeason,\$year:Int){
            Page(page:\$page,perPage:\$per){
              media(season:\$season,seasonYear:\$year,type:ANIME){
                id title{romaji} coverImage{large} genres description
              }
            }
          }
        ''';
        vars = {
          'page': _currentPage[index],
          'per': 10,
          'season': (index == 0 ? _upcomingSeason : _season).toUpperCase(),
          'year': (index == 0 ? _upcomingYear : _year),
        };
        break;

      case 2:
        query = '''
          query(\$page:Int,\$per:Int,\$season:MediaSeason,\$year:Int){
            Page(page:\$page,perPage:\$per){
              media(season:\$season,seasonYear:\$year,type:ANIME,sort:[POPULARITY_DESC]){
                id title{romaji} coverImage{large} genres description
              }
            }
          }
        ''';
        vars = {
          'page': _currentPage[index],
          'per': 10,
          'season': _season.toUpperCase(),
          'year': _year,
        };
        break;

      case 3:
        query = '''
          query(\$id:Int){
            Media(id:\$id){
              recommendations(perPage:10){
                nodes{ mediaRecommendation{ id title{romaji} coverImage{large} genres description } }
              }
            }
          }
        ''';
        final seasonal = _lists[1];
        vars = {
          'id': seasonal.isNotEmpty
              ? seasonal[DateTime.now().millisecondsSinceEpoch % seasonal.length].id
              : 1
        };
        break;

      case 4:
        query = '''
          query(\$page:Int,\$per:Int){
            Page(page:\$page,perPage:\$per){
              media(type:ANIME,status:RELEASING,sort:[TRENDING_DESC]){
                id title{romaji} coverImage{large} genres description
              }
            }
          }
        ''';
        vars = {'page': _currentPage[index], 'per': 10};
        break;

      case 5: // Make You Cry
        query = '''
          query(\$page:Int,\$per:Int){
            Page(page:\$page,perPage:\$per){
              media(type:ANIME,genre_in:["Drama","Tragedy"],sort:[SCORE_DESC]){
                id title{romaji} coverImage{large} genres description
              }
            }
          }
        ''';
        vars = {'page': _currentPage[index], 'per': 10};
        break;

      case 6: // Action Picks
        query = '''
          query(\$page:Int,\$per:Int){
            Page(page:\$page,perPage:\$per){
              media(type:ANIME,genre_in:["Action"],sort:[TRENDING_DESC]){
                id title{romaji} coverImage{large} genres description
              }
            }
          }
        ''';
        vars = {'page': _currentPage[index], 'per': 10};
        break;

      case 7: // Scary
        query = '''
          query(\$page:Int,\$per:Int){
            Page(page:\$page,perPage:\$per){
              media(type:ANIME,genre_in:["Horror","Thriller"],sort:[TRENDING_DESC]){
                id title{romaji} coverImage{large} genres description
              }
            }
          }
        ''';
        vars = {'page': _currentPage[index], 'per': 10};
        break;

      case 8: // Gore
        query = '''
          query(\$page:Int,\$per:Int){
            Page(page:\$page,perPage:\$per){
              media(type:ANIME,genre_in:["Horror"],sort:[SCORE_DESC]){
                id title{romaji} coverImage{large} genres description
              }
            }
          }
        ''';
        vars = {'page': _currentPage[index], 'per': 10};
        break;
    }

    debugPrint('=== Fetching tab $index (“${_tabTitles[index]}”), page ${vars['page']}');
    debugPrint('Variables: $vars');

    try {
      final res = await http.post(
        Uri.parse(_apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'query': query, 'variables': vars}),
      );
      final data = jsonDecode(res.body) as Map<String, dynamic>?;

      List<Anime> fetched;
      if (index == 3) {
        final nodes = (data?['data']?['Media']?['recommendations']?['nodes'] as List?)
            ?.map((n) => Anime.fromGraphQL(
            (n as Map<String, dynamic>)['mediaRecommendation'] as Map<String, dynamic>))
            .toList() ??
            [];
        fetched = nodes;
        _hasMore[index] = false;
      } else {
        final media = (data?['data']?['Page']?['media'] as List?) ?? [];
        fetched = media
            .map((m) => Anime.fromGraphQL(m as Map<String, dynamic>))
            .toList();
        if (fetched.length < (vars['per'] as int)) _hasMore[index] = false;
      }

      debugPrint('Fetched ${fetched.length} items for tab $index');

      setState(() {
        _lists[index].addAll(fetched);
        _currentPage[index]++;
      });
    } catch (e) {
      debugPrint('Fetch error tab $index: $e');
    } finally {
      if (!_lists[index].isNotEmpty) debugPrint('No more pages for tab $index');
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Discover'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: _tabTitles.map((t) => Tab(text: t)).toList(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SearchPage()),
            ),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: List.generate(9, (i) => _buildSection(i)),
      ),
    );
  }

  Widget _buildSection(int i) {
    final list = _lists[i];
    if (_loading && list.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (list.isEmpty) {
      return Center(child: Text('No data for "${_tabTitles[i]}".'));
    }
    return RefreshIndicator(
      onRefresh: () async => _refreshCurrentTab(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Container(
            width: double.infinity,
            color: Colors.black12,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            child: Text(
              _tabTitles[i],
              style: const TextStyle(
                  fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: NotificationListener<ScrollNotification>(
              onNotification: (notif) {
                if (notif.metrics.pixels >= notif.metrics.maxScrollExtent - 50) {
                  _fetchPage(i);
                }
                return false;
              },
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: list.length,
                itemBuilder: (_, j) => _buildCard(list[j]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(Anime a) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AnimeDetailPage(id: a.id)),
      ),
      child: Container(
        width: 240,
        margin: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              Image.network(a.coverUrl, width: 240, height: 360, fit: BoxFit.cover),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black54],
                    ),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        a.title,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        a.genres.join(', '),
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        a.description,
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
              // Favorite & Share
              Positioned(
                top: 8,
                right: 8,
                child: Column(
                  children: [
                    IconButton(
                      icon: Icon(
                        context.read<FavoritesModel>().isAnimeFavorite(a.id.toString())
                            ? Icons.star
                            : Icons.star_border,
                      ),
                      color: context.read<FavoritesModel>().isAnimeFavorite(a.id.toString())
                          ? Colors.amber
                          : Colors.white,
                      onPressed: () {
                        setState(() {
                          context
                              .read<FavoritesModel>()
                              .toggleAnimeFavoriteById(a.id.toString());
                        });
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.share),
                      color: Colors.white,
                      onPressed: () {
                        Share.share(
                          'Check out ${a.title} on AniList: https://anilist.co/anime/${a.id}\n'
                              'Genres: ${a.genres.join(', ')}\n'
                              'Desc: ${a.description}',
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
