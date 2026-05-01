import 'dart:async';
import 'package:flutter/material.dart';

import 'package:anime_finder/models/market.dart';
import 'package:anime_finder/models/wallet.dart';
import 'package:anime_finder/models/position.dart';

import 'package:anime_finder/services/api_service.dart';
import 'package:anime_finder/services/market_service.dart';
import 'package:anime_finder/services/positions_service.dart';
import 'package:anime_finder/widgets/countdown_timer.dart';

import 'markets_list_page.dart';
import 'notifications_page.dart';
import 'position_detail_page.dart';

class MarketPage extends StatefulWidget {
  final int marketId;
  const MarketPage({super.key, required this.marketId});

  @override
  State<MarketPage> createState() => _MarketPageState();
}

class _MarketPageState extends State<MarketPage> {
  Market? market;
  Wallet? wallet;
  Position? myPosition;

  int? selectedOutcome;
  final TextEditingController stakeController = TextEditingController(text: "100");

  bool loading = true;
  bool submitting = false;

  Timer? _pollTimer;

  // Optional (only if backend provides it)
  // Supports either:
  // - marketJson["odds"] = { "12": 0.62, "13": 0.38 }
  // - marketJson["outcome_odds"] = [ { "outcome_id": 12, "p": 0.62 }, ... ]
  Map<int, double> oddsByOutcomeId = {};

  @override
  void initState() {
    super.initState();
    _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) => _load());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    stakeController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final marketJson = await ApiService.instance.getJson("/markets/${widget.marketId}");
      final walletJson = await ApiService.instance.getJson("/me/wallet");
      final positions = await PositionsService.fetchMyPositions();

      if (!mounted) return;

      final matches = positions.where((p) => p.marketId == widget.marketId).toList();

      setState(() {
        market = Market.fromJson(marketJson);
        wallet = Wallet.fromJson(walletJson);
        myPosition = matches.isNotEmpty ? matches.first : null;
        oddsByOutcomeId = _extractOdds(marketJson);
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      _error("Failed to load market");
    }
  }

  Map<int, double> _extractOdds(Map<String, dynamic> marketJson) {
    final out = <int, double>{};

    final odds = marketJson['odds'];
    if (odds is Map) {
      for (final entry in odds.entries) {
        final k = int.tryParse(entry.key.toString());
        final v = (entry.value is num) ? (entry.value as num).toDouble() : null;
        if (k != null && v != null) out[k] = v.clamp(0.0, 1.0);
      }
      return out;
    }

    final arr = marketJson['outcome_odds'];
    if (arr is List) {
      for (final item in arr) {
        if (item is Map) {
          final oid = (item['outcome_id'] is num) ? (item['outcome_id'] as num).toInt() : null;
          final p = (item['p'] is num) ? (item['p'] as num).toDouble() : null;
          if (oid != null && p != null) out[oid] = p.clamp(0.0, 1.0);
        }
      }
    }

    return out;
  }

  void _error(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  void _success(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _enterMarket() async {
    if (submitting || market == null || wallet == null) return;

    if (selectedOutcome == null) {
      _error("Pick an outcome first");
      return;
    }

    final stake = int.tryParse(stakeController.text.trim()) ?? 0;
    if (stake <= 0) {
      _error("Enter a valid stake");
      return;
    }

    setState(() => submitting = true);

    try {
      await MarketService.enterMarket(
        marketId: market!.id,
        outcomeId: selectedOutcome!,
        stakeAmount: stake,
      );

      _success("Position placed!");
      await _load();
    } catch (e) {
      _error("Failed: $e");
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case "open":
        return Colors.green;
      case "closed":
        return Colors.orange;
      case "resolved":
        return Colors.blue;
      case "cancelled":
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _prettyStatus(String status) {
    switch (status) {
      case "open":
        return "OPEN";
      case "closed":
        return "CLOSED";
      case "resolved":
        return "RESOLVED";
      case "cancelled":
        return "CANCELLED";
      default:
        return status.toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading || market == null || wallet == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final m = market!;
    final w = wallet!;
    final isOpen = m.status == "open";
    final DateTime endTime = m.closeTime;

    // Winner label (only if resolved + winning_outcome_id exists in model JSON)
    String? winnerLabel;
    final winningId = m.winningOutcomeId; // assume your Market model has it; if not, remove this line
    if (m.status == "resolved" && winningId != null) {
      final win = m.outcomes.where((o) => o.id == winningId).toList();
      if (win.isNotEmpty) winnerLabel = win.first.label;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Market"),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotificationsPage()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.list_alt),
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const MarketsListPage()),
                (_) => false,
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Header Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Theme.of(context).cardColor,
                boxShadow: const [
                  BoxShadow(blurRadius: 12, offset: Offset(0, 6), color: Colors.black12),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        m.title,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: _statusColor(m.status).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: _statusColor(m.status).withOpacity(0.35)),
                        ),
                        child: Text(
                          _prettyStatus(m.status),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: _statusColor(m.status),
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if ((m.description ?? "").trim().isNotEmpty)
                    Text(
                      m.description ?? "",
                      style: TextStyle(color: Colors.grey.shade700, height: 1.35),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.timer_outlined, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: CountdownTimer(target: endTime)),
                    ],
                  ),
                  if (m.status == "resolved" && winnerLabel != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.blue.withOpacity(0.10),
                        border: Border.all(color: Colors.blue.withOpacity(0.25)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.emoji_events_outlined, color: Colors.blue),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              "Winner: $winnerLabel",
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Wallet + My position
            Row(
              children: [
                Expanded(
                  child: _statCard(
                    icon: Icons.account_balance_wallet_outlined,
                    title: "Balance",
                    value: w.balance.toString(),
                    subtitle: "virtual",
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _statCard(
                    icon: Icons.assignment_ind_outlined,
                    title: "My Position",
                    value: myPosition == null ? "—" : "Entered",
                    subtitle: myPosition == null ? "not placed" : "tap to view",
                    onTap: myPosition == null
                        ? null
                        : () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PositionDetailPage(position: myPosition!),
                              ),
                            );
                          },
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),

            const Text(
              "Outcomes",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),

            ...m.outcomes.map((o) {
              final p = oddsByOutcomeId[o.id]; // null if backend not providing odds
              final isSelected = selectedOutcome == o.id;

              return GestureDetector(
                onTap: isOpen ? () => setState(() => selectedOutcome = o.id) : null,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: isSelected ? Colors.black.withOpacity(0.04) : Theme.of(context).cardColor,
                    border: Border.all(
                      color: isSelected ? Colors.black87 : Colors.black12,
                      width: isSelected ? 1.2 : 1.0,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              o.label,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                            ),
                          ),
                          if (m.status == "resolved" && winnerLabel == o.label)
                            const Icon(Icons.check_circle, color: Colors.green),
                          if (isOpen)
                            Radio<int>(
                              value: o.id,
                              groupValue: selectedOutcome,
                              onChanged: (v) => setState(() => selectedOutcome = v),
                            ),
                        ],
                      ),
                      if (p != null) ...[
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: p,
                            minHeight: 10,
                            backgroundColor: Colors.black12,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          "Implied odds: ${(p * 100).toStringAsFixed(1)}%",
                          style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),

            const SizedBox(height: 8),

            if (isOpen) ...[
              TextField(
                controller: stakeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Stake (virtual coins)",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: (!submitting) ? _enterMarket : null,
                  child: submitting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          "Enter Market",
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.black.withOpacity(0.04),
                  border: Border.all(color: Colors.black12),
                ),
                child: const Text(
                  "This market is not open for entry.",
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statCard({
    required IconData icon,
    required String title,
    required String value,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    final child = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Theme.of(context).cardColor,
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          if (onTap != null) const Icon(Icons.chevron_right),
        ],
      ),
    );

    if (onTap == null) return child;
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(16), child: child);
  }
}
