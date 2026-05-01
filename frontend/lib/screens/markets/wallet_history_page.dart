import 'package:flutter/material.dart';
import '../models/wallet_transaction.dart';
import '../services/wallet_service.dart';

class WalletHistoryPage extends StatefulWidget {
  const WalletHistoryPage({super.key});

  @override
  State<WalletHistoryPage> createState() => _WalletHistoryPageState();
}

class _WalletHistoryPageState extends State<WalletHistoryPage> {
  late Future<List<WalletTransaction>> txs;

  @override
  void initState() {
    super.initState();
    txs = WalletService.fetchTransactions();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Wallet History")),
      body: FutureBuilder<List<WalletTransaction>>(
        future: txs,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text("No transactions yet"));
          }

          return ListView.builder(
            itemCount: snapshot.data!.length,
            itemBuilder: (context, index) {
              final tx = snapshot.data![index];
              return ListTile(
                title: Text(tx.type),
                subtitle: Text(tx.note ?? ""),
                trailing: Text("${tx.amount}"),
              );
            },
          );
        },
      ),
    );
  }
}
