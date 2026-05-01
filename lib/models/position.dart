class Position {
  final int marketId;
  final String marketTitle;
  final String outcomeLabel;
  final double stake;
  final bool isResolved;
  final bool isWin;

  Position({
    required this.marketId,
    required this.marketTitle,
    required this.outcomeLabel,
    required this.stake,
    required this.isResolved,
    required this.isWin,
  });

  factory Position.fromJson(Map<String, dynamic> json) {
    return Position(
      marketId: json['market_id'],
      marketTitle: json['market_title'],
      outcomeLabel: json['outcome_label'],
      stake: (json['stake'] as num).toDouble(),
      isResolved: json['is_resolved'] ?? false,
      isWin: json['is_win'] ?? false,
    );
  }
}
