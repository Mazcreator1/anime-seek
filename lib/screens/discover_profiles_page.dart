// lib/screens/discover_profiles_page.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:anime_finder/services/auth_service.dart';
import 'package:anime_finder/screens/profile_page.dart';

class UserLite {
  final int id;
  final String displayName;
  final String avatarUrl;
  final String headline;
  bool isFollowing;
  bool isLiked;
  int likeCount;

  UserLite({
    required this.id,
    required this.displayName,
    required this.avatarUrl,
    required this.headline,
    required this.isFollowing,
    required this.isLiked,
    required this.likeCount,
  });

  factory UserLite.fromMap(Map m0) {
    final m = Map<String, dynamic>.from(m0 as Map);

    String pickStr(List<String> keys) {
      for (final k in keys) {
        final v = m[k];
        if (v != null && v.toString().trim().isNotEmpty) return v.toString();
      }
      return '';
    }

    bool pickBool(dynamic v) {
      if (v is bool) return v;
      if (v is num) return v.toInt() == 1;
      if (v is String) return v == '1' || v.toLowerCase() == 'true';
      return false;
    }

    int pickInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    return UserLite(
      id: pickInt(m['id']),
      displayName: pickStr(['display_name','username','name']),
      avatarUrl: pickStr(['avatar_url','avatar','image','photo']),
      headline: pickStr(['top_line','headline','bio_snippet']),
      isFollowing: pickBool(m['is_following'] ?? m['follows_by_me']),
      isLiked:     pickBool(m['is_liked']     ?? m['liked_by_me']),
      likeCount:   pickInt(m['like_count']),
    );
  }
}

class DiscoverProfilesPage extends StatefulWidget {
  const DiscoverProfilesPage({Key? key}) : super(key: key);
  @override
  State<DiscoverProfilesPage> createState() => _DiscoverProfilesPageState();
}

class _DiscoverProfilesPageState extends State<DiscoverProfilesPage> {
  final _searchCtl = TextEditingController();
  Timer? _debounce;

  final List<UserLite> _users = [];
  bool _loading = false;
  bool _hasMore = true;
  int _page = 1; // 1-based pages
  static const _perPage = 24;

  // Adjust this to your backend browse/search endpoint.
  // Expecting JSON: { items: [ {id,...}, ... ], next_page?: int }
  static const _base = 'https://anime-seek.com/fastapi';

  @override
  void initState() {
    super.initState();
    _load(reset: true);
    _searchCtl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _load(reset: true);
    });
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    if (reset) {
      setState(() { _page = 1; _hasMore = true; _users.clear(); });
    }
    if (!_hasMore) return;

    setState(() => _loading = true);
    try {
      final headers = await AuthService.authHeaders;
      final q = _searchCtl.text.trim();
      final uri = Uri.parse('$_base/users/discover').replace(queryParameters: {
        'q': q,
        'page': '$_page',
        'per': '$_perPage',
      });

      final r = await http.get(uri, headers: {...headers, 'Accept': 'application/json'});
      if (r.statusCode != 200) {
        debugPrint('discover profiles ${r.statusCode} ${r.body}');
        setState(() => _loading = false);
        return;
      }

      final body = r.body.isEmpty ? '{}' : r.body;
      final j = json.decode(body);

// local vars (in scope for setState)
      final List items = (j is Map && j['items'] is List) ? j['items'] : (j is List ? j : []);
      final int? nextPage = (j is Map && j['next_page'] != null) ? int.tryParse('${j['next_page']}') : null;

      final List<UserLite> mapped = items
          .whereType<Map>()
          .map((m) => UserLite.fromMap(Map<String, dynamic>.from(m)))
          .toList();

      setState(() {
        // merge by replacing existing objects (since fields are final)
        final idToIndex = <int,int>{ for (int i=0;i<_users.length;i++) _users[i].id : i };
        for (final nu in mapped) {
          final idx = idToIndex[nu.id];
          if (idx != null) {
            _users[idx] = nu; // replace with server truth
          } else {
            _users.add(nu);
          }
        }

        _page += 1;
        _hasMore = mapped.length >= _perPage && (nextPage == null || nextPage >= _page);
      });

    } catch (e) {
      debugPrint('discover profiles error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleFollow(UserLite u) async {
    try {
      final headers = await AuthService.authHeaders;
      if (u.isFollowing) {
        await http.delete(Uri.parse('$_base/users/${u.id}/unfollow'),
            headers: {...headers, 'Accept':'application/json'});
        setState(() => u.isFollowing = false);
      } else {
        await http.post(Uri.parse('$_base/users/${u.id}/follow'),
            headers: {...headers, 'Accept':'application/json'});
        setState(() => u.isFollowing = true);
      }
    } catch (_) {}
  }

  Future<void> _toggleLike(UserLite u) async {
    try {
      final headers = await AuthService.authHeaders;
      http.Response res;

      if (u.isLiked) {
        // UNLIKE
        res = await http.delete(
          Uri.parse('$_base/users/${u.id}/like'),
          headers: {...headers, 'Accept': 'application/json'},
        );
      } else {
        // LIKE
        res = await http.post(
          Uri.parse('$_base/users/${u.id}/like'),
          headers: {...headers, 'Accept': 'application/json'},
        );
      }

      if (res.statusCode == 200) {
        final j = json.decode(res.body) as Map<String, dynamic>;

        bool parseBool(dynamic v) =>
            v == true ||
                v == 1 ||
                v == '1' ||
                (v is String && v.toLowerCase() == 'true');

        final liked = j.containsKey('liked')
            ? parseBool(j['liked'])
            : !u.isLiked; // fallback: just flip

        final newCount = (j['like_count'] is num)
            ? (j['like_count'] as num).toInt()
            : (u.likeCount + (liked ? 1 : -1)).clamp(0, 1 << 31);

        setState(() {
          u.isLiked = liked;
          u.likeCount = newCount;
        });
      }
    } catch (_) {
      // optional: show snack/error
    }
  }




  Future<void> _refresh() async => _load(reset: true);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Discover Profiles'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => _load(reset: true),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _searchCtl,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search people by name or headline',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.pixels >= n.metrics.maxScrollExtent - 200) _load();
            return false;
          },
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            itemCount: _users.length + (_loading ? 1 : 0),
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (ctx, i) {
              if (i >= _users.length) {
                return const Center(child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(),
                ));
              }
              final u = _users[i];
              final avatar = u.avatarUrl.isEmpty
                  ? 'https://anime-seek.com/uploads/user_avatars/default_avatar.jpg'
                  : (u.avatarUrl.startsWith('http') ? u.avatarUrl : 'https://anime-seek.com${u.avatarUrl.startsWith('/') ? '' : '/'}${u.avatarUrl}');
              return InkWell(
                onTap: () {
                  Navigator.push(ctx, MaterialPageRoute(
                    builder: (_) => ProfilePage(userId: u.id),
                  ));
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF17181A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0x22222222)),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: Image.network(avatar, width: 56, height: 56, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(width:56,height:56,color:Colors.grey[800]),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(u.displayName, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            if (u.headline.isNotEmpty)
                              Text(u.headline, maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(Icons.favorite, size: 16, color: Colors.pink[300]),
                                const SizedBox(width: 4),
                                Text('${u.likeCount}', style: const TextStyle(fontSize: 12, color: Colors.white70)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: u.isLiked ? 'Unlike' : 'Like profile',
                            onPressed: () => _toggleLike(u),
                            icon: Icon(u.isLiked ? Icons.favorite : Icons.favorite_border),
                            color: Colors.pink[300],
                          ),
                          SizedBox(
                            height: 34,
                            child: OutlinedButton(
                              onPressed: () => _toggleFollow(u),
                              child: Text(u.isFollowing ? 'Following' : 'Follow'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
