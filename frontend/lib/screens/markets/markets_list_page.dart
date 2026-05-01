import 'package:flutter/material.dart';
import 'package:anime_finder/models/market.dart';
import 'package:anime_finder/services/api.dart';
import 'package:anime_finder/widgets/countdown_timer.dart';

import 'market_page.dart';
import 'create_market_page.dart'; // ✅ REQUIRED

class MarketsListPage extends StatefulWidget {
  const MarketsListPage({super.key});

  @override
  State<MarketsListPage> createState() => _MarketsListPageState();
}

class _MarketsListPageState extends State<MarketsListPage> {
  
  Map<String, dynamic>? _me;
  bool _meLoading = true;

  Future<void> _loadMe() async {
    // Fetch current user from backend. This is used to gate admin-only UI.
    // Endpoint returns { ... , is_admin: true/false }.
    setState(() => _meLoading = true);
    try {
      final res = await Api.get('/auth/me');
      if (!mounted) return;
      setState(() {
        _me = (res is Map<String, dynamic>) ? res : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _me = null;
      });
    } finally {
      if (!mounted) return;
      setState(() => _meLoading = false);
    }
  }

  bool get _isAdmin {
    final v = _me?['is_admin'];
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) return v.toLowerCase() == 'true' || v == '1';
    // fallback: some APIs return role
    final role = (_me?['role'] ?? '').toString().toLowerCase();
    return role == 'admin' || role == 'administrator';
  }

List<Market> markets = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadMe();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await Api.get("/markets");
      setState(() {
        markets = (res as List)
            .map((m) => Market.fromJson(m))
            .toList();
        loading = false;
      });
    } catch (_) {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Markets"),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: "Create Market (dev)",
            onPressed: () async {
              final changed = await Navigator.push<bool>(
                context,
                MaterialPageRoute(builder: (_) => const CreateMarketPage()),
              );
              if (changed == true) _load();
            },
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
        itemCount: markets.length,
        itemBuilder: (_, i) => _marketCard(markets[i]),
      ),
    );
  }

  Widget _marketCard(Market m) {
    final isOpen = m.status == "open";

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        title: Text(m.title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              m.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            if (isOpen) CountdownTimer(target: m.closeTime),
          ],
        ),
        trailing: Chip(
          label: Text(m.status.toUpperCase()),
          backgroundColor: isOpen
              ? Colors.green.withOpacity(0.15)
              : Colors.grey.withOpacity(0.15),
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MarketPage(marketId: m.id),
            ),
          );
        },
      ),
    );
  }
}
