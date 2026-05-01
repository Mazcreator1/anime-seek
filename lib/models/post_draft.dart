// lib/models/post_draft.dart
class PostDraft {
  final String? text;                 // optional caption
  final String? imageUrl;             // cover/character image to attach (remote)
  final String? localImagePath;       // if you snapshot or cache locally
  final int? anilistId;               // or your internal id
  final String? animeTitle;
  final String? characterName;
  final Map<String, dynamic>? extra;  // season, ep, timestamp, tags, etc.

  PostDraft({
    this.text,
    this.imageUrl,
    this.localImagePath,
    this.anilistId,
    this.animeTitle,
    this.characterName,
    this.extra,
  });

  Map<String, dynamic> toJson() => {
    "text": text,
    "imageUrl": imageUrl,
    "anilistId": anilistId,
    "animeTitle": animeTitle,
    "characterName": characterName,
    "extra": extra,
  }..removeWhere((k,v)=>v==null);
}
