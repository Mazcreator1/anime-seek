// models/wallet_transaction.dart

class WalletTransaction {
  final int id;
  final double amount;
  final String reason;
  final String? referenceType;
  final int? referenceId;
  final DateTime createdAt;

  WalletTransaction({
    required this.id,
    required this.amount,
    required this.reason,
    this.referenceType,
    this.referenceId,
    required this.createdAt,
  });

  factory WalletTransaction.fromJson(Map<String, dynamic> json) {
    return WalletTransaction(
      id: json['id'],
      amount: (json['amount'] as num).toDouble(),
      reason: json['reason'],
      referenceType: json['reference_type'],
      referenceId: json['reference_id'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  bool get isCredit => amount > 0;
}
