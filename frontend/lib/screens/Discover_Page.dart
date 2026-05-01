// lib/screens/Discover_Page.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../utils/share_to_feed.dart';
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
    description:
    (json['description'] ?? '').toString().replaceAll(RegExp(r'<[^>]*>'), ''),
  );
}

class DiscoverPage extends StatefulWidget {
  const DiscoverPage({Key? key}) : super(key: key);
  @override
  _DiscoverPageState createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  List<String> _tabTitles = [];

  // season state (auto-rotating)
  late String _season; // WINTER/SPRING/SUMMER/FALL
  late int _year;
  late String _upcomingSeason;
  late int _upcomingYear;
  String _seasonKey = '';
  String _upcomingKey = '';

  Timer? _midnightTimer;
  Timer? _seasonTicker;

  bool _loading = false;

  // data per tab (sized dynamically to _tabTitles.length)
  List<bool> _hasMore = [];
  List<int> _currentPage = [];
  List<List<Anime>> _lists = [];
  List<DateTime?> _lastLoadedAt = [];

  static const _apiUrl = 'https://graphql.anilist.co';

  // AniList genres you asked for
  static const List<String> _genreTabs = [
    'Action',
    'Adventure',
    'Comedy',
    'Drama',
    'Ecchi',
    'Fantasy',
    'Horror',
    'Mahou Shoujo',
    'Mecha',
    'Music',
    'Mystery',
    'Psychological',
    'Romance',
  ];

  // ---------- lifecycle ----------
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _recomputeSeasons();
    _computeTabTitles();      // builds titles
    _allocDataArrays();       // sizes lists to _tabTitles.length

    _tabController = TabController(length: _tabTitles.length, vsync: this)
      ..addListener(() {
        _ensureSeasonFresh();
        if (!_loading) {
          final i = _tabController.index;
          final stale = _lastLoadedAt[i] == null ||
              DateTime.now().difference(_lastLoadedAt[i]!).inHours >= 6;
          if (_lists[i].isEmpty || stale) _refreshCurrentTab();
        }
      });

    _scheduleMidnightRefresh();
    _seasonTicker = Timer.periodic(const Duration(hours: 6), (_) => _ensureSeasonFresh());
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshCurrentTab());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnightTimer?.cancel();
    _seasonTicker?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _ensureSeasonFresh();
  }

  // ---------- season utils ----------
  String _seasonForMonth(int m) {
    if (m <= 3) return 'WINTER';
    if (m <= 6) return 'SPRING';
    if (m <= 9) return 'SUMMER';
    return 'FALL';
  }

  String _prettySeason(String s) => s.isEmpty ? s : s[0] + s.substring(1).toLowerCase();

  bool _recomputeSeasons() {
    final now = DateTime.now();
    final s = _seasonForMonth(now.month);
    final y = now.year;
    const order = ['WINTER', 'SPRING', 'SUMMER', 'FALL'];
    final i = order.indexOf(s);
    final upS = order[(i + 1) % 4];
    final upY = (s == 'FALL') ? y + 1 : y;

    final newKey = '$s-$y';
    final newUpKey = '$upS-$upY';
    final changed = (newKey != _seasonKey) || (newUpKey != _upcomingKey);

    _season = s;
    _year = y;
    _upcomingSeason = upS;
    _upcomingYear = upY;
    _seasonKey = newKey;
    _upcomingKey = newUpKey;
    return changed;
  }
  void _allocDataArrays() {
    final n = _tabTitles.length;
    if (_lists.length == n) return;
    _hasMore        = List<bool>.filled(n, true, growable: false);
    _currentPage    = List<int>.filled(n, 1, growable: false);
    _lists          = List.generate(n, (_) => <Anime>[], growable: false);
    _lastLoadedAt   = List<DateTime?>.filled(n, null, growable: false);
  }

  void _ensureSeasonFresh() {
    if (_recomputeSeasons()) {
      _computeTabTitles();        // same length, just new labels
      for (final i in [0,1,2]) {
        _lists[i].clear(); _hasMore[i] = true; _currentPage[i] = 1; _lastLoadedAt[i] = null;
      }
      setState(() {});
    }
  }


  void _scheduleMidnightRefresh() {
    _midnightTimer?.cancel();
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day + 1);
    _midnightTimer = Timer(next.difference(now), () {
      _ensureSeasonFresh();
      _scheduleMidnightRefresh();
    });
  }

  // ---------- tabs / controller ----------
  void _computeTabTitles() {
    final now = DateTime.now();
    const mn = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final today = '${mn[now.month - 1]} ${now.day}';

    _tabTitles = [
      'Upcoming ${_prettySeason(_upcomingSeason)} $_upcomingYear',
      'Seasonal ${_prettySeason(_season)} $_year',
      'Top 10 ${_prettySeason(_season)} $_year',
      'Recommended',
      // genre tabs
      'Action','Adventure','Comedy','Drama','Ecchi','Fantasy','Horror',
      'Mahou Shoujo','Mecha','Music','Mystery','Psychological','Romance',
    ];
    setState(() {}); // labels change, count stays the same
  }


  void _resizeDataStructures(int n) {
    bool first = _lists.isEmpty;
    _hasMore = List<bool>.filled(n, true, growable: false);
    _currentPage = List<int>.filled(n, 1, growable: false);
    _lists = List.generate(n, (_) => <Anime>[], growable: false);
    _lastLoadedAt = List<DateTime?>.filled(n, null, growable: false);
    if (!first) setState(() {});
  }

  void _recreateControllerIfNeeded() {
    final initial = (_tabControllerOrNull?.index ?? 0).clamp(0, _tabTitles.length - 1);
    _tabControllerOrNull?.dispose();
    _tabController = TabController(length: _tabTitles.length, vsync: this, initialIndex: initial)
      ..addListener(() {
        _ensureSeasonFresh();
        if (!_loading) {
          final i = _tabController.index;
          final stale = _lastLoadedAt[i] == null ||
              DateTime.now().difference(_lastLoadedAt[i]!).inHours >= 6;
          if (_lists[i].isEmpty || stale) _refreshCurrentTab();
        }
      });
  }

  TabController? get _tabControllerOrNull =>
      (mounted && (identical(_tabController, _tabController))) ? _tabController : null;

  // ---------- fetch ----------
  Future<void> _refreshCurrentTab() async {
    final i = _tabController.index.clamp(0, _lists.length - 1);
    _currentPage[i] = 1;
    _hasMore[i] = true;
    _lists[i].clear();
    _lastLoadedAt[i] = null;
    await _fetchPage(i);
  }

  Future<void> _fetchPage(int index) async {
    _ensureSeasonFresh();
    if (!_hasMore[index] || _loading) return;
    setState(() => _loading = true);

    String query = '';
    Map<String, dynamic> vars = {};

    switch (index) {
      case 0: // Upcoming (next season)
      case 1: // Current season
        query = r'''
          query($page:Int,$per:Int,$season:MediaSeason,$year:Int){
            Page(page:$page, perPage:$per){
              media(season:$season, seasonYear:$year, type:ANIME){
                id title{romaji} coverImage{large} genres description
              }
            }
          }
        ''';
        final isUpcoming = index == 0;
        vars = {
          'page': _currentPage[index],
          'per': 12,
          'season': isUpcoming ? _upcomingSeason : _season,
          'year': isUpcoming ? _upcomingYear : _year,
        };
        break;

      case 2: // Top 10 of current season
        query = r'''
          query($page:Int,$per:Int,$season:MediaSeason,$year:Int){
            Page(page:$page, perPage:$per){
              media(
                season:$season, seasonYear:$year, type:ANIME,
                sort:[POPULARITY_DESC]
              ){
                id title{romaji} coverImage{large} genres description
              }
            }
          }
        ''';
        vars = {
          'page': _currentPage[index],
          'per': 10,
          'season': _season,
          'year': _year,
        };
        break;

      case 3: // Recommended (based on a random seasonal pick; fallback to trending)
        final seasonal = _lists[1];
        if (seasonal.isNotEmpty) {
          query = r'''
            query($id:Int){
              Media(id:$id){
                recommendations(perPage:10){
                  nodes{
                    mediaRecommendation{
                      id title{romaji} coverImage{large} genres description
                    }
                  }
                }
              }
            }
          ''';
          vars = {
            'id': seasonal[DateTime.now().millisecondsSinceEpoch % seasonal.length].id
          };
        } else {
          query = r'''
            query($page:Int,$per:Int){
              Page(page:$page, perPage:$per){
                media(type:ANIME, sort:[TRENDING_DESC]){
                  id title{romaji} coverImage{large} genres description
                }
              }
            }
          ''';
          vars = {'page': _currentPage[index], 'per': 10};
        }
        break;

      default: // Genre tabs (index >= 4)
        final genre = _genreTabs[index - 4];
        query = r'''
          query($page:Int,$per:Int,$genre:String){
            Page(page:$page, perPage:$per){
              media(
                type:ANIME,
                isAdult:false,
                genre_in:[$genre],
                sort:[TRENDING_DESC, POPULARITY_DESC]
              ){
                id title{romaji} coverImage{large} genres description
              }
            }
          }
        ''';
        vars = {'page': _currentPage[index], 'per': 12, 'genre': genre};
        break;
    }

    try {
      final res = await http.post(
        Uri.parse(_apiUrl),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({'query': query, 'variables': vars}),
      );

      if (res.statusCode != 200) {
        debugPrint('AniList error: ${res.statusCode} ${res.body}');
        setState(() => _loading = false);
        return;
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>?;

      List<Anime> fetched = [];
      if (index == 3 && _lists[1].isNotEmpty) {
        final nodes = (data?['data']?['Media']?['recommendations']?['nodes'] as List?) ?? [];
        fetched = nodes
            .map((n) => Anime.fromGraphQL(
            (n as Map<String, dynamic>)['mediaRecommendation'] as Map<String, dynamic>))
            .toList();
        _hasMore[index] = false;
      } else {
        final media = (data?['data']?['Page']?['media'] as List?) ?? [];
        fetched = media.map((m) => Anime.fromGraphQL(m as Map<String, dynamic>)).toList();
        if (fetched.length < (vars['per'] as int)) _hasMore[index] = false;

        // Gentle fallback: if a genre tab comes up empty, widen to POPULARITY only
        if (index >= 4 && fetched.isEmpty) {
          final fallback = r'''
            query($page:Int,$per:Int,$genre:String){
              Page(page:$page, perPage:$per){
                media(type:ANIME, isAdult:false, genre_in:[$genre], sort:[POPULARITY_DESC]){
                  id title{romaji} coverImage{large} genres description
                }
              }
            }
          ''';
          final r2 = await http.post(Uri.parse(_apiUrl),
              headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
              body: jsonEncode({
                'query': fallback,
                'variables': {'page': 1, 'per': 12, 'genre': _genreTabs[index - 4]}
              }));
          if (r2.statusCode == 200) {
            final m2 = (jsonDecode(r2.body)['data']?['Page']?['media'] as List?) ?? [];
            fetched = m2.map((m) => Anime.fromGraphQL(m as Map<String, dynamic>)).toList();
          }
        }
      }

      setState(() {
        _lists[index].addAll(fetched);
        _currentPage[index]++;
        _lastLoadedAt[index] = DateTime.now();
      });
    } catch (e) {
      debugPrint('Fetch error tab $index: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Discover'),
        bottom: TabBar(
          key: ValueKey('tabs-$_seasonKey'), // force title rebuild on season flip
          controller: _tabController,
          isScrollable: true,
          tabs: _tabTitles.map((t) => Tab(text: t)).toList(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchPage())),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: List.generate(_tabTitles.length, (i) => KeyedSubtree(
          key: (i <= 2) ? ValueKey('season-$_seasonKey-$i') : ValueKey('tab-$i'),
          child: _buildSection(i),
        )),
      ),
    );
  }

  Widget _buildSection(int i) {
    if (i >= _lists.length) return const SizedBox.shrink();
    final list = _lists[i];
    if (_loading && list.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (list.isEmpty) {
      return Center(child: Text('No data for "${_tabTitles[i]}".'));
    }
    return RefreshIndicator(
      onRefresh: () async {
        if (i <= 2) _ensureSeasonFresh();
        return _refreshCurrentTab();
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Container(
            width: double.infinity,
            color: Colors.black12,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            child: Text(
              _tabTitles[i],
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
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
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AnimeDetailPage(id: a.id))),
      child: Container(
        width: 240,
        margin: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              Image.network(a.coverUrl, width: 240, height: 360, fit: BoxFit.cover),
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black54]),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(a.title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text(a.genres.join(', '), style: const TextStyle(color: Colors.white70, fontSize: 12),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text(a.description, style: const TextStyle(color: Colors.white70, fontSize: 12),
                          maxLines: 3, overflow: TextOverflow.ellipsis),
                      IconButton(
                        tooltip: 'Share to Feed',
                        icon: const Icon(Icons.send),
                        onPressed: () {
                          shareToFeed(
                            context: context,
                            caption: "🔥 Check out ${a.title}",
                            imageUrl: a.coverUrl,
                            anilistId: a.id,
                            animeTitle: a.title,
                            extra: {
                              "source": "Discover",
                              "genres": a.genres,
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 8, right: 8,
                child: Column(
                  children: [
                    IconButton(
                      icon: Icon(
                        context.read<FavoritesModel>().isAnimeFavorite(a.id.toString())
                            ? Icons.star : Icons.star_border,
                      ),
                      color: context.read<FavoritesModel>().isAnimeFavorite(a.id.toString())
                          ? Colors.amber : Colors.white,
                      onPressed: () {
                        setState(() {
                          context.read<FavoritesModel>().toggleAnimeFavoriteById(a.id.toString());
                        });
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.share), color: Colors.white,
                      onPressed: () => Share.share(
                        'Check out ${a.title} on AniList: https://anilist.co/anime/${a.id}\n'
                            'Genres: ${a.genres.join(', ')}\n'
                            'Desc: ${a.description}',
                      ),
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
