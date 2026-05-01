// lib/utils/share_to_feed.dart
import 'package:flutter/material.dart';
import '../models/post_draft.dart';
import '../widgets/post_composer_sheet.dart';

void shareToFeed({
  required BuildContext context,
  String? caption,
  String? imageUrl,
  String? localImagePath,
  int? anilistId,
  String? animeTitle,
  String? characterName,
  Map<String, dynamic>? extra,
}) {
  openPostComposer(
    context,
    PostDraft(
      text: caption,
      imageUrl: imageUrl,
      localImagePath: localImagePath,
      anilistId: anilistId,
      animeTitle: animeTitle,
      characterName: characterName,
      extra: extra,
    ),
  );
}
