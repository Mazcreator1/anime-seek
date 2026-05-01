// lib/services/wallet_service.dart
import 'package:anime_finder/services/api_service.dart';
import '../models/wallet.dart';
import '../models/wallet_transaction.dart';

class WalletService {
  static Future<Wallet> fetchWallet() async {
    final json = await ApiService.instance.getJson("/me/wallet");
    return Wallet.fromJson(json);
  }

  static Future<List<WalletTransaction>> fetchTransactions() async {
    final data = await ApiService.instance.getJsonList("/me/wallet/transactions");
    return data
        .map((t) => WalletTransaction.fromJson(t as Map<String, dynamic>))
        .toList();
  }
}
