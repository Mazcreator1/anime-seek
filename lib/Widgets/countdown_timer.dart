import 'dart:async';
import 'package:flutter/material.dart';

class CountdownTimer extends StatefulWidget {
  final DateTime target;

  const CountdownTimer({super.key, required this.target});

  @override
  State<CountdownTimer> createState() => _CountdownTimerState();
}

class _CountdownTimerState extends State<CountdownTimer> {
  late Duration remaining;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final diff = widget.target.difference(DateTime.now().toUtc());
    setState(() {
      remaining = diff.isNegative ? Duration.zero : diff;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (remaining == Duration.zero) {
      return const Text(
        "Market closed",
        style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
      );
    }

    final hours = remaining.inHours;
    final minutes = remaining.inMinutes.remainder(60);
    final seconds = remaining.inSeconds.remainder(60);

    final urgent = remaining.inMinutes <= 15;

    return Text(
      "Closes in ${hours}h ${minutes}m ${seconds}s",
      style: TextStyle(
        color: urgent ? Colors.red : Colors.orange,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}
