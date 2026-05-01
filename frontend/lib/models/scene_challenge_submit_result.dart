class SceneChallenge {
  final int id;
  final int? anilistId;
  final int? episode;
  final String? timestamp;
  final String imageUrl;
  final String difficulty;
  final List<String> hints;
  final List<String> options;

  SceneChallenge({
    required this.id,
    required this.imageUrl,
    required this.difficulty,
    required this.hints,
    required this.options,
    this.anilistId,
    this.episode,
    this.timestamp,
  });

  factory SceneChallenge.fromJson(Map<String, dynamic> json) {
    return SceneChallenge(
      id: json['id'] as int,
      anilistId: json['anilist_id'] as int?,
      episode: json['episode'] as int?,
      timestamp: json['timestamp']?.toString(),
      imageUrl: json['image_url']?.toString() ?? '',
      difficulty: json['difficulty']?.toString() ?? 'easy',
      hints: (json['hints'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      options: (json['options'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}