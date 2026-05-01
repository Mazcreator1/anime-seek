class GeneratedCharacter {
  static const String backendBaseUrl = 'https://anime-seek.com/fastapi';

  final int? id;
  final String prompt;
  final String style;
  final String artStyle;
  final String gender;
  final String hair;
  final String eyes;
  final String outfit;
  final String mood;
  final String imageUrl;
  final bool isFavorite;
  final DateTime? createdAt;

  final String? name;
  final String? backstory;
  final String? storyScene;

  GeneratedCharacter({
    this.id,
    required this.prompt,
    required this.style,
    this.artStyle = 'modern_anime',
    required this.gender,
    required this.hair,
    required this.eyes,
    required this.outfit,
    required this.mood,
    required this.imageUrl,
    this.isFavorite = false,
    this.createdAt,
    this.name,
    this.backstory,
    this.storyScene,
  });

  String get resolvedImageUrl {
    if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
      return imageUrl;
    }

    if (imageUrl.startsWith('/fastapi/')) {
      return 'https://anime-seek.com$imageUrl';
    }

    if (imageUrl.startsWith('/')) {
      return '$backendBaseUrl$imageUrl';
    }

    return '$backendBaseUrl/$imageUrl';
  }

  GeneratedCharacter copyWith({
    int? id,
    String? prompt,
    String? style,
    String? artStyle,
    String? gender,
    String? hair,
    String? eyes,
    String? outfit,
    String? mood,
    String? imageUrl,
    bool? isFavorite,
    DateTime? createdAt,
    String? name,
    String? backstory,
    String? storyScene,
  }) {
    return GeneratedCharacter(
      id: id ?? this.id,
      prompt: prompt ?? this.prompt,
      style: style ?? this.style,
      artStyle: artStyle ?? this.artStyle,
      gender: gender ?? this.gender,
      hair: hair ?? this.hair,
      eyes: eyes ?? this.eyes,
      outfit: outfit ?? this.outfit,
      mood: mood ?? this.mood,
      imageUrl: imageUrl ?? this.imageUrl,
      isFavorite: isFavorite ?? this.isFavorite,
      createdAt: createdAt ?? this.createdAt,
      name: name ?? this.name,
      backstory: backstory ?? this.backstory,
      storyScene: storyScene ?? this.storyScene,
    );
  }

  factory GeneratedCharacter.fromJson(Map<String, dynamic> json) {
    return GeneratedCharacter(
      id: json['id'],
      prompt: json['prompt'] ?? '',
      style: json['style'] ?? '',
      artStyle: json['art_style'] ?? json['artStyle'] ?? 'modern_anime',
      gender: json['gender'] ?? '',
      hair: json['hair'] ?? '',
      eyes: json['eyes'] ?? '',
      outfit: json['outfit'] ?? '',
      mood: json['mood'] ?? '',
      imageUrl: json['image_url'] ?? '',
      isFavorite: json['is_favorite'] ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'])
          : null,
      name: json['name'],
      backstory: json['backstory'],
      storyScene: json['story_scene'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'prompt': prompt,
      'style': style,
      'art_style': artStyle,
      'gender': gender,
      'hair': hair,
      'eyes': eyes,
      'outfit': outfit,
      'mood': mood,
      'image_url': imageUrl,
      'is_favorite': isFavorite,
      'created_at': createdAt?.toIso8601String(),
      'name': name,
      'backstory': backstory,
      'story_scene': storyScene,
    };
  }
}