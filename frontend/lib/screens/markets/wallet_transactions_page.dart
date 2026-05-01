import 'package:flutter/material.dart';
import '../models/wallet_transaction.dart';
import '../services/wallet_service.dart';

class WalletTransactionsPage extends StatefulWidget {
  const WalletTransactionsPage({super.key});

  @override
  State<WalletTransactionsPage> createState() => _WalletTransactionsPageState();
}

class _WalletTransactionsPageState extends State<WalletTransactionsPage> {
  late Future<List<WalletTransaction>> txs;

  @override
  void initState() {
    super.initState();
    txs = WalletService.fetchTransactions();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Transactions")),
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
