// lib/models/post.dart
// lib/models/post.dart
class Post {
  final int id;
  final String text;
  final String? imageUrl;
  final String? imagePreviewUrl;
  final String? videoUrl;
  final String? backgroundColor;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final int likeCount;
  final int commentCount;
  final bool likedByMe;
  final int reshareCount;
  final bool resharedByMe;
  final bool commentsLocked;
  final DateTime lockAfterAt;
  final UserLite user;

  // Poll fields (present when type == 'poll')
  final String? type;
  final Poll? poll;

  Post({
    required this.id,
    required this.text,
    required this.imageUrl,
    required this.imagePreviewUrl,
    required this.videoUrl,
    required this.backgroundColor,
    required this.createdAt,
    required this.updatedAt,
    required this.likeCount,
    required this.commentCount,
    required this.likedByMe,
    required this.reshareCount,
    required this.resharedByMe,
    required this.commentsLocked,
    required this.lockAfterAt,
    required this.user,
    required this.type,
    required this.poll,
  });

  factory Post.fromJson(Map<String, dynamic> j) {
    DateTime _iso(String? s) =>
        (s == null || s.isEmpty) ? DateTime.now().toUtc() : DateTime.parse(s);

    return Post(
      id: j['id'] as int,
      text: (j['text'] ?? '') as String,
      imageUrl: j['image_url'] as String?,
      imagePreviewUrl: j['image_preview_url'] as String?,
      videoUrl: j['video_url'] as String?,
      backgroundColor: j['background_color'] as String?,
      createdAt: _iso(j['created_at'] as String?),
      updatedAt: j['updated_at'] == null ? null : DateTime.parse(j['updated_at']),
      likeCount: (j['like_count'] ?? 0) as int,
      commentCount: (j['comment_count'] ?? 0) as int,
      likedByMe: (j['liked_by_me'] ?? false) as bool,
      reshareCount: (j['reshare_count'] ?? 0) as int,
      resharedByMe: (j['reshared_by_me'] ?? false) as bool,
      commentsLocked: (j['comments_locked'] ?? false) as bool,
      lockAfterAt: _iso(j['lock_after_at'] as String?),
      user: UserLite.fromJson(j['user'] as Map<String, dynamic>),
      type: j['type'] as String?,
      poll: j['poll'] == null ? null : Poll.fromJson(j['poll']),
    );
  }
}

class UserLite {
  final int id;
  final String displayName;
  final String? avatarUrl;

  UserLite({required this.id, required this.displayName, this.avatarUrl});

  factory UserLite.fromJson(Map<String, dynamic> j) => UserLite(
    id: j['id'] as int,
    displayName: (j['display_name'] ?? 'User') as String,
    avatarUrl: j['avatar_url'] as String?,
  );
}

class Poll {
  final int id;
  final String question;
  final bool multiple;
  final bool allowChange;
  final DateTime? closesAt;
  final bool isClosed;
  final int totalVotes;
  final List<PollOption> options;
  final List<int> votedOptionIds;

  Poll({
    required this.id,
    required this.question,
    required this.multiple,
    required this.allowChange,
    required this.closesAt,
    required this.isClosed,
    required this.totalVotes,
    required this.options,
    required this.votedOptionIds,
  });

  factory Poll.fromJson(Map<String, dynamic> j) {
    DateTime? ca;
    final s = j['closes_at'] as String?;
    if (s != null && s.isNotEmpty) {
      try { ca = DateTime.parse(s); } catch (_) {}
    }
    final opts = ((j['options'] ?? []) as List)
        .map((o) => PollOption.fromJson(o as Map<String, dynamic>))
        .toList();

    return Poll(
      id: (j['id'] ?? 0) as int,
      question: (j['question'] ?? '') as String,
      multiple: (j['multiple'] ?? false) as bool,
      allowChange: (j['allow_change'] ?? true) as bool,
      closesAt: ca,
      isClosed: (j['is_closed'] ?? false) as bool,
      totalVotes: (j['total_votes'] ?? 0) as int,
      options: opts,
      votedOptionIds: ((j['voted_option_ids'] ?? []) as List).map((e) => e as int).toList(),
    );
  }

  bool get canVote => !isClosed && (allowChange || votedOptionIds.isEmpty);
}

class PollOption {
  final int id;
  final int idx;
  final String text;
  final int voteCount;

  PollOption({required this.id, required this.idx, required this.text, required this.voteCount});

  factory PollOption.fromJson(Map<String, dynamic> j) => PollOption(
    id: j['id'] as int,
    idx: (j['idx'] ?? j['position'] ?? 0) as int,
    text: (j['text'] ?? '') as String,
    voteCount: (j['vote_count'] ?? 0) as int,
  );
}
