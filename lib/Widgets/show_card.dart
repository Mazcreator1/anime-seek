// lib/widgets/show_card.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:flutter/material.dart';
import 'package:anime_finder/utils/colors.dart';
import 'package:anime_finder/services/api_service.dart';
import 'package:anime_finder/models/post.dart';
import 'package:anime_finder/widgets/poll_card.dart';

enum ShowCardType { anime, profile, post }

class ShowCard extends StatelessWidget {
  final ShowCardType type;


  // Common optional
  final Map<String, dynamic>? post;
  final Map<String, dynamic>? poll;
  final ApiService? api;

  // —— Anime props
  final int? animeId;
  final String? animeTitle;
  final String? animeCoverUrl;
  final List<String>? animeGenres;
  final VoidCallback? onOpenAnime;
  final VoidCallback? onFavAnime;
  final VoidCallback? onOpenAniList;
  final EdgeInsets? outerMargin;
  final bool clipForOverlay;
  // —— Profile props
  final int? userId;
  final String? displayName;
  final String? avatarUrl;
  final String? headline;
  final bool? isFollowing;
  final bool? isLiked;
  final VoidCallback? onOpenProfile;
  final VoidCallback? onFollowToggle;
  final VoidCallback? onLikeToggle;

  // —— Post props
  final String? postSnippet;
  final String? backgroundColor;
  final VoidCallback? onOpenPost;

  // —— Post counters, flags, handlers
  final int? likeCount;
  final int? commentCount;
  final int? reshareCount;
  final bool? likedByMe;
  final bool? resharedByMe;
  final VoidCallback? onLike;
  final VoidCallback? onComment;
  final VoidCallback? onReshare;

  const ShowCard.anime({
    Key? key,
    required this.animeId,
    required this.animeTitle,
    required this.animeCoverUrl,
    this.animeGenres,
    this.onOpenAnime,
    this.onFavAnime,
    this.onOpenAniList,
    this.post,
    this.poll,
    this.api,
  })  : type = ShowCardType.anime,
        userId = null,
        displayName = null,
        avatarUrl = null,
        headline = null,
        isFollowing = null,
        isLiked = null,
        onOpenProfile = null,
        onFollowToggle = null,
        onLikeToggle = null,
        postSnippet = null,
        onOpenPost = null,
        backgroundColor = null,
        likeCount = null,
        commentCount = null,
        reshareCount = null,
        likedByMe = null,
        resharedByMe = null,
        onLike = null,
        onComment = null,
        onReshare = null,
        outerMargin = null,
        clipForOverlay = false,
        super(key: key);


  const ShowCard.profile({
    Key? key,
    required this.userId,
    required this.displayName,
    required this.avatarUrl,
    this.headline,
    this.isFollowing,
    this.isLiked,
    this.onOpenProfile,
    this.onFollowToggle,
    this.onLikeToggle,
    this.post,
    this.poll,
    this.api,
  })  : type = ShowCardType.profile,
        animeId = null,
        animeTitle = null,
        animeCoverUrl = null,
        animeGenres = null,
        onOpenAnime = null,
        onFavAnime = null,
        onOpenAniList = null,
        postSnippet = null,
        onOpenPost = null,
        backgroundColor = null,
        likeCount = null,
        commentCount = null,
        reshareCount = null,
        likedByMe = null,
        resharedByMe = null,
        onLike = null,
        onComment = null,
        onReshare = null,
  // NEW:
        outerMargin = null,
        clipForOverlay = false,
        super(key: key);


  const ShowCard.post({
    Key? key,
    required this.userId,
    required this.displayName,
    required this.avatarUrl,
    required this.postSnippet,
    this.backgroundColor,
    this.onOpenPost,
    this.onOpenProfile,
    this.post,
    this.poll,
    this.api,
    this.likeCount,
    this.commentCount,
    this.reshareCount,
    this.likedByMe,
    this.resharedByMe,
    this.onLike,
    this.onComment,
    this.onReshare,
    this.outerMargin,
    this.clipForOverlay = false,
  })  : type = ShowCardType.post,
        animeId = null,
        animeTitle = null,
        animeCoverUrl = null,
        animeGenres = null,
        onOpenAnime = null,
        onFavAnime = null,
        onOpenAniList = null,
        headline = null,
        isFollowing = null,
        isLiked = null,
        onFollowToggle = null,
        onLikeToggle = null,
        super(key: key);


  @override
  Widget build(BuildContext context) {
    switch (type) {
      case ShowCardType.anime:
        return _AnimeCard(
          title: animeTitle!,
          coverUrl: animeCoverUrl!,
          genres: animeGenres ?? const [],
          onOpen: onOpenAnime,
          onFav: onFavAnime,
          onOpenAniList: onOpenAniList,
        );

      case ShowCardType.profile:
        return _ProfileCard(
          displayName: displayName!,
          avatarUrl: avatarUrl!,
          headline: headline ?? '',
          isFollowing: isFollowing ?? false,
          isLiked: isLiked ?? false,
          onOpenProfile: onOpenProfile,
          onFollowToggle: onFollowToggle,
          onLikeToggle: onLikeToggle,
        );

      case ShowCardType.post:
        return _PostCard(
          displayName: displayName!,
          avatarUrl: avatarUrl!,
          snippet: postSnippet!,
          backgroundColor: backgroundColor,
          onOpenPost: onOpenPost,
          onOpenProfile: onOpenProfile,
          likeCount: likeCount,
          commentCount: commentCount,
          reshareCount: reshareCount,
          likedByMe: likedByMe,
          resharedByMe: resharedByMe,
          onLike: onLike,
          onComment: onComment,
          onReshare: onReshare,
          post: post,
          poll: poll,
          api: api,

          outerMargin: outerMargin,
          clipForOverlay: clipForOverlay ?? false,
        );
    }
  }
}

// ===== Anime Card =====
class _AnimeCard extends StatelessWidget {
  final String title, coverUrl;
  final List<String> genres;
  final VoidCallback? onOpen, onFav, onOpenAniList;
  const _AnimeCard({
    required this.title,
    required this.coverUrl,
    required this.genres,
    this.onOpen,
    this.onFav,
    this.onOpenAniList,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onOpen,
      child: Container(
        width: 240,
        margin: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4))
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            children: [
              Image.network(coverUrl,
                  width: 240, height: 360, fit: BoxFit.cover),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _GradientFooter(
                  title: title,
                  subtitle: genres.take(3).join(', '),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                          icon: const Icon(Icons.star_border),
                          color: Colors.white,
                          onPressed: onFav),
                      IconButton(
                          icon: const Icon(Icons.open_in_new),
                          color: Colors.white,
                          onPressed: onOpenAniList),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===== Profile Card =====
class _ProfileCard extends StatelessWidget {
  final String displayName, avatarUrl, headline;
  final bool isFollowing, isLiked;
  final VoidCallback? onOpenProfile, onFollowToggle, onLikeToggle;

  const _ProfileCard({
    required this.displayName,
    required this.avatarUrl,
    required this.headline,
    required this.isFollowing,
    required this.isLiked,
    this.onOpenProfile,
    this.onFollowToggle,
    this.onLikeToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      margin: const EdgeInsets.only(right: 16, bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Theme.of(context).cardColor,
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3))
        ],
      ),
      child: Row(
        children: [
          InkWell(
            onTap: () {
              // consume the tap and navigate
              onOpenProfile?.call();
            },
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.all(2), // slightly bigger hit target
              child: CircleAvatar(backgroundImage: NetworkImage(avatarUrl)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: onOpenProfile,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(displayName,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(headline,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 8),
                  Row(children: [
                    TextButton.icon(
                      onPressed: onFollowToggle,
                      icon: Icon(isFollowing
                          ? Icons.check
                          : Icons.person_add_alt),
                      label: Text(isFollowing ? 'Following' : 'Follow'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: onLikeToggle,
                      icon: Icon(isLiked
                          ? Icons.favorite
                          : Icons.favorite_border),
                      label: Text(isLiked ? 'Liked' : 'Like'),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===== Post Card =====
class _PostCard extends StatelessWidget {
  final String displayName, avatarUrl, snippet;
  final String? backgroundColor;
  final VoidCallback? onOpenPost, onOpenProfile;

  final int? likeCount, commentCount, reshareCount;
  final bool? likedByMe, resharedByMe;
  final VoidCallback? onLike, onComment, onReshare;

  final Map<String, dynamic>? post;

  // Optional poll blob already resolved at the feed level
  final dynamic poll;

  final ApiService? api;

  final EdgeInsets? outerMargin;
  final bool clipForOverlay;

  const _PostCard({
    required this.displayName,
    required this.avatarUrl,
    required this.snippet,
    this.backgroundColor,
    this.onOpenPost,
    this.onOpenProfile,
    this.likeCount,
    this.commentCount,
    this.reshareCount,
    this.likedByMe,
    this.resharedByMe,
    this.onLike,
    this.onComment,
    this.onReshare,
    this.post,
    this.poll,
    this.api,

    this.outerMargin,
    this.clipForOverlay = false,
  });

  static const _defaultBg = Color(0xFF17181A);

  @override
  Widget build(BuildContext context) {
      final bg = parseHexColor(backgroundColor) ?? _defaultBg;
      final cs = Theme.of(context).colorScheme;

      final pollData = poll ?? post?['poll'];
      final isPoll = (post?['type'] == 'poll') || (pollData != null);
      final question = isPoll
          ? (pollData?['question'] ?? post?['text'] ?? snippet)
          : snippet;

      debugPrint('POST TYPE: ${post?['type']}');
      debugPrint('POLL DATA RAW: $pollData');

      if (pollData != null) {
        debugPrint('POLL QUESTION: ${pollData['question']}');
        debugPrint('POLL OPTIONS: ${pollData['options']}');
      }

      return InkWell(
        onTap: () {
          final pollData = poll ?? post?['poll'];
          final isPoll = (post?['type'] == 'poll') || (pollData != null);
          final question = isPoll
              ? (pollData?['question'] ?? post?['text'] ?? snippet)
              : snippet;

          if (isPoll) {
            // Build a Post model for PollCard
            final Map<String, dynamic> raw = {
              ...?post,
              'text': question,
              if (pollData != null) 'poll': pollData,
            };

            final pModel = Post.fromJson(raw);

            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PollCard(
                  post: pModel,
                  onVote: (List<int> optionIdxs) async {
                    final svc = api ?? ApiService.instance;
                    return await svc.votePoll(pModel.id, optionIdxs);
                  },
                ),
              ),
            );
          } else {
            onOpenPost?.call();
          }
        },
        child: Container(
          // NEW: allow caller to remove margin when overlaying a badge
          margin: outerMargin ?? const EdgeInsets.only(right: 16, bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3))
            ],
          ),
          // NEW: ensure anything drawn on top is clipped when desired
          clipBehavior: clipForOverlay ? Clip.hardEdge : Clip.none,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: onOpenProfile,
                    child: CircleAvatar(backgroundImage: NetworkImage(avatarUrl)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      displayName,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                question,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (isPoll && pollData?['options'] != null)
                _PollSection(poll: Map<String, dynamic>.from(pollData)),
              if (likeCount != null ||
                  commentCount != null ||
                  reshareCount != null) ...[
                const SizedBox(height: 8),
                Divider(height: 1, color: cs.outlineVariant.withOpacity(.5)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: _action(
                        icon: likedByMe == true
                            ? Icons.thumb_up
                            : Icons.thumb_up_alt_outlined,
                        label: 'Like',
                        count: likeCount,
                        onTap: onLike,
                      ),
                    ),
                    Expanded(
                      child: _action(
                        icon: Icons.mode_comment_outlined,
                        label: 'Comment',
                        count: commentCount,
                        onTap: onComment,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
    );
  }

  Widget _action({
    required IconData icon,
    required String label,
    int? count,
    VoidCallback? onTap,
  }) {
    final txt = count == null ? label : '$label ($count)';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 6),
              Text(txt),
            ],
          ),
        ),
      ),
    );
  }
}

// ===== Poll section =====
class _PollSection extends StatelessWidget {
  final Map<String, dynamic> poll;
  const _PollSection({required this.poll});

  @override
  Widget build(BuildContext context) {
    final options = List<Map<String, dynamic>>.from(poll['options'] ?? []);
    final int totalVotes = (poll['total_votes'] ?? 0) is int
        ? poll['total_votes'] as int
        : int.tryParse('${poll['total_votes'] ?? 0}') ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        ...options.map((opt) {
          final String label = (opt['text'] ?? '') as String;
          final int votes = (opt['vote_count'] ?? 0) is int
              ? opt['vote_count'] as int
              : int.tryParse('${opt['vote_count'] ?? 0}') ?? 0;
          final double pct = totalVotes > 0 ? votes / totalVotes : 0.0;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Stack(
              children: [
                Container(
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: pct.clamp(0.0, 1.0),
                  child: Container(
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.teal.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Center(
                    child: Text(
                      '$label  (${(pct * 100).toStringAsFixed(1)}%)',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

// ===== Gradient footer (used by anime card) =====
class _GradientFooter extends StatelessWidget {
  final String title, subtitle;
  final Widget? trailing;
  const _GradientFooter(
      {required this.title, required this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black54],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                        const TextStyle(color: Colors.white70, fontSize: 12)),
                  ])),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

// --- Poll voting helper ---
// Uses ApiService if available via dynamic (to reuse auth); otherwise falls back to direct HTTP.
// Adjust _kApiBaseFallback if your ApiService resolves a different base.
const String _kApiBaseFallback = 'https://anime-seek.com';

extension PollApi on ApiService {
  Future<Post> votePoll(int postId, List<int> optionIdxs) async {
    // Try to call a dynamic JSON POST on ApiService (if your ApiService exposes one)
    try {
      final dynamic self = this;
      final dynamic res = await self.postJson(
        "/posts/$postId/poll/vote",
        {"option_idxs": optionIdxs},
      );
      final data = Map<String, dynamic>.from(res['post'] ?? {});
      return Post.fromJson(data);
    } catch (_) {
      // Fallback: direct HTTP POST (may need auth header depending on your ApiService)
      final uri = Uri.parse("$_kApiBaseFallback/posts/$postId/poll/vote");
      final resp = await http.post(
        uri,
        headers: const {
          "Content-Type": "application/json",
          "Accept": "application/json",
        },
        body: jsonEncode({"option_idxs": optionIdxs}),
      );
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception("vote failed (${resp.statusCode}): ${resp.body}");
      }
      final decoded = jsonDecode(resp.body);
      final data = decoded is Map<String, dynamic> ? decoded['post'] : null;
      return Post.fromJson(Map<String, dynamic>.from(data ?? {}));
    }
  }
}
