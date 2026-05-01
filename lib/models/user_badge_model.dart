class UserBadge {
  final String name;
  final String description;
  final DateTime unlockedAt;

  UserBadge({
    required this.name,
    required this.description,
    required this.unlockedAt,
  });

  factory UserBadge.fromJson(Map<String, dynamic> json) => UserBadge(
    name: json['name'],
    description: json['description'] ?? '',
    unlockedAt: DateTime.parse(json['unlocked_at']),
  );
}
