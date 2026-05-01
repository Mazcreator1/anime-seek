// pages/wallet_page.dart

import 'package:flutter/material.dart';
import '../models/wallet.dart';
import '../models/wallet_transaction.dart';
import '../services/wallet_service.dart';

class WalletPage extends StatefulWidget {
  const WalletPage({super.key});

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  Wallet? wallet;
  List<WalletTransaction> transactions = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final w = await WalletService.fetchWallet();
    final tx = await WalletService.fetchTransactions();

    setState(() {
      wallet = w;
      transactions = tx;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Wallet")),
      body: Column(
        children: [
          _balanceCard(),
          const Divider(),
          Expanded(child: _transactionList()),
        ],
      ),
    );
  }

  Widget _balanceCard() {
    return Card(
      margin: const EdgeInsets.all(12),
      child: ListTile(
        title: const Text("Balance"),
        subtitle: Text("${wallet?.balance ?? 0} coins"),
      ),
    );
  }

  Widget _transactionList() {
    if (transactions.isEmpty) {
      return const Center(child: Text("No transactions yet"));
    }

    return ListView.builder(
      itemCount: transactions.length,
      itemBuilder: (context, index) {
        final tx = transactions[index];
        return ListTile(
          title: Text(tx.type),
          subtitle: Text(tx.note ?? ""),
          trailing: Text("${tx.amount}"),
        );
      },
    );
  }
}
