// lib/screens/subscription_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/auth_service.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({Key? key}) : super(key: key);

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen>
    with WidgetsBindingObserver {
  String _userInfo = 'Loading…';
  String _respCheckout = '';
  String _respCancel = '';
  String _respDelete = '';
  String _respLogout = '';

  bool _loadingUser = false;
  bool _creatingCheckout = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUserInfo();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // When user returns from Stripe (browser/SafariView), refresh account info
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadUserInfo();
    }
  }

  Future<void> _loadUserInfo() async {
    if (_loadingUser) return;
    setState(() => _loadingUser = true);

    try {
      final token = await AuthService.getToken();
      if (token == null) {
        setState(() => _userInfo = 'Not logged in');
        return;
      }

      final resp = await AuthService.me();
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        setState(() {
          _userInfo = const JsonEncoder.withIndent('  ').convert(data);
        });
      } else {
        setState(() => _userInfo = 'Error fetching account info (${resp.statusCode})');
      }
    } catch (e) {
      setState(() => _userInfo = 'Error fetching account info: $e');
    } finally {
      if (mounted) setState(() => _loadingUser = false);
    }
  }

  Future<void> _createCheckout(String tier) async {
    if (_creatingCheckout) return;

    setState(() {
      _creatingCheckout = true;
      _respCheckout = '';
    });

    try {
      final resp = await AuthService.createCheckout(tier);

      Map<String, dynamic> data = {};
      try {
        data = json.decode(resp.body) as Map<String, dynamic>;
      } catch (_) {
        // non-json response
      }

      setState(() {
        _respCheckout = const JsonEncoder.withIndent('  ').convert(
          data.isNotEmpty ? data : {'raw': resp.body, 'status': resp.statusCode},
        );
      });

      final checkoutUrl = data['checkout_url'] as String?;
      if (resp.statusCode >= 200 && resp.statusCode < 300 && checkoutUrl != null) {
        final uri = Uri.parse(checkoutUrl);

        // Use the newer API if available; fallback to old calls
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
    } finally {
      if (mounted) setState(() => _creatingCheckout = false);
    }
  }

  Future<void> _cancelSubscription() async {
    final resp = await AuthService.cancelSubscription();
    setState(() => _respCancel = resp.body);
    await _loadUserInfo();
  }

  Future<void> _deleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text('Are you sure? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Yes')),
        ],
      ),
    );

    if (confirm == true) {
      final resp = await AuthService.deleteAccount();
      setState(() => _respDelete = resp.body);
      if (resp.statusCode == 200) {
        await AuthService.clearToken();
        if (mounted) Navigator.pushReplacementNamed(context, '/signup');
      }
    }
  }

  Future<void> _logout() async {
    await AuthService.clearToken();
    setState(() => _respLogout = 'Logged out');
    if (mounted) Navigator.pushReplacementNamed(context, '/signup');
  }

  @override
  Widget build(BuildContext context) {
    final busy = _loadingUser || _creatingCheckout;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Account'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadingUser ? null : _loadUserInfo,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Account Info
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_loadingUser) const LinearProgressIndicator(),
                    const SizedBox(height: 8),
                    Text(_userInfo),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Subscription
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Subscription', style: TextStyle(fontSize: 18)),
                    const SizedBox(height: 8),

                    // Free tier should not hit Stripe
                    ElevatedButton(
                      onPressed: busy
                          ? null
                          : () async {
                              setState(() {
                                _respCheckout = 'Free tier is the default (no checkout required).';
                              });
                              await _loadUserInfo();
                            },
                      child: const Text('Watcher (Free)'),
                    ),

                    ElevatedButton(
                      onPressed: busy ? null : () => _createCheckout('otaku'),
                      child: const Text('Otaku (\$2/month)'),
                    ),
                    ElevatedButton(
                      onPressed: busy ? null : () => _createCheckout('senpai'),
                      child: const Text('Senpai (\$3/month)'),
                    ),
                    ElevatedButton(
                      onPressed: busy ? null : () => _createCheckout('kami'),
                      child: const Text('Kami-sama (\$5/month)'),
                    ),

                    if (_respCheckout.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(_respCheckout),
                      const SizedBox(height: 8),
                      const Text(
                        'Note: your tier updates after Stripe sends the webhook. '
                        'If you just paid, tap Refresh or return to the app and it will auto-refresh.',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ],

                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: busy ? null : _cancelSubscription,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      child: const Text('Cancel Subscription'),
                    ),
                    if (_respCancel.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(_respCancel),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Delete Account
            Card(
              color: Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Danger Zone',
                        style: TextStyle(fontSize: 18, color: Colors.red)),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: busy ? null : _deleteAccount,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      child: const Text('Delete My Account'),
                    ),
                    if (_respDelete.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(_respDelete),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Logout
            ElevatedButton(
              onPressed: _logout,
              child: const Text('Log Out'),
            ),
            if (_respLogout.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(_respLogout),
            ],
          ],
        ),
      ),
    );
  }
}
