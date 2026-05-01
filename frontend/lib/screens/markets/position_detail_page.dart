import 'package:flutter/material.dart';
import 'package:anime_finder/models/position.dart';

class PositionDetailPage extends StatelessWidget {
  final Position position;
  const PositionDetailPage({super.key, required this.position});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Position Detail")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Market ID: ${position.marketId}",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text("Stake: ${position.stake}"),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
