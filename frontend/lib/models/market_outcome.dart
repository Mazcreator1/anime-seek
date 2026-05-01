// lib/models/market_outcome.dart

class MarketOutcome {
  final int id;
  final String label;

  /// Optional fields for future expansion (odds, probability, etc.)
  final double? odds;
  final double? probability;

  MarketOutcome({
    required this.id,
    required this.label,
    this.odds,
    this.probability,
  });

  factory MarketOutcome.fromJson(Map<String, dynamic> json) {
    return MarketOutcome(
      id: json['id'],
      label: json['label'],
      odds: json['odds'] != null
          ? (json['odds'] as num).toDouble()
          : null,
      probability: json['probability'] != null
          ? (json['probability'] as num).toDouble()
          : null,
    );
  }
}
