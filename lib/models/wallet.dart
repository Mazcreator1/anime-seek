// models/wallet.dart

class Wallet {
  final double balance;

  Wallet({required this.balance});

  factory Wallet.fromJson(Map<String, dynamic> json) {
    return Wallet(balance: (json['balance'] as num).toDouble());
  }
}
