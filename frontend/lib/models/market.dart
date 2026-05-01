import 'market_outcome.dart';

class Market {
  final int id;
  final String title;
  final String description;
  final String status;
  final DateTime closeTime;
  final List<MarketOutcome> outcomes;

  final int? winningOutcomeId;
  final DateTime? resolvedAt;

  Market({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.closeTime,
    required this.outcomes,
    this.winningOutcomeId,
    this.resolvedAt,
  });

  factory Market.fromJson(Map<String, dynamic> json) {
    return Market(
      id: json['id'],
      title: json['title'],
      description: json['description'] ?? '',
      status: json['status'],
      closeTime: DateTime.parse(json['close_time']),
      outcomes: (json['outcomes'] as List)
          .map((o) => MarketOutcome.fromJson(o))
          .toList(),
      winningOutcomeId: json['winning_outcome_id'],
      resolvedAt: json['resolved_at'] != null
          ? DateTime.parse(json['resolved_at'])
          : null,
    );
  }

  /// Convenience helpers
  bool get isOpen => status == "open";
  bool get isClosed => status == "closed";
  bool get isResolved => status == "resolved";

  MarketOutcome? get winningOutcome {
    if (!isResolved || winningOutcomeId == null) return null;
    return outcomes.firstWhere(
          (o) => o.id == winningOutcomeId,
      orElse: () => outcomes.first,
    );
  }
}
