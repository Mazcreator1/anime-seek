// lib/screens/subscription_screen.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';

class SubscriptionScreen extends StatefulWidget {
  @override
  _SubscriptionScreenState createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  final _storage = FlutterSecureStorage();
  bool _trialUsed = false;
  bool _loading = false;

  Future<String?> _getToken() async => await _storage.read(key: 'token');

  Future<void> _startTrial(int days) async {
    final token = await _getToken();
    if (token == null) return;
    setState(() => _loading = true);
    final res = await http.post(
      Uri.parse('https://YOUR_API/subscriptions/trial'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json'
      },
      body: json.encode({
        'days': days,
      }),
    );
    setState(() => _loading = false);
    if (res.statusCode == 200) {
      setState(() => _trialUsed = true);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Trial started!'))
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${res.body}'))
      );
    }
  }

  Future<void> _subscribePaid() async {
    final token = await _getToken();
    if (token == null) return;
    setState(() => _loading = true);
    final res = await http.post(
      Uri.parse('https://YOUR_API/payments/create-checkout-session'),
      headers: {
        'Authorization': 'Bearer $token',
      },
    );
    setState(() => _loading = false);
    if (res.statusCode == 200) {
      final url = json.decode(res.body)['url'];
      if (await canLaunch(url)) await launch(url);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating session'))
      );
    }
  }

  Future<void> _cancelSubscription() async {
    final token = await _getToken();
    if (token == null) return;
    setState(() => _loading = true);
    final res = await http.post(
      Uri.parse('https://YOUR_API/subscriptions/cancel'),
      headers: {
        'Authorization': 'Bearer $token',
      },
    );
    setState(() => _loading = false);
    if (res.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Subscription canceled'))
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error canceling'))
      );
    }
  }

  @override
  Widget build(BuildContext ctx) {
    return Scaffold(
      appBar: AppBar(title: Text('Subscription')),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton(
              onPressed: _trialUsed ? null : () => _startTrial(3),
              child: Text(_trialUsed
                  ? 'Trial Already Used'
                  : 'Start 3-Day Free Trial'),
            ),
            SizedBox(height: 12),
            ElevatedButton(
              onPressed: _subscribePaid,
              child: Text('Subscribe 30-Day Plan'),
            ),
            SizedBox(height: 12),
            TextButton(
              onPressed: _cancelSubscription,
              child: Text('Cancel / End Membership'),
            ),
          ],
        ),
      ),
    );
  }
}
