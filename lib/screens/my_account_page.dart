// lib/screens/my_account_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:anime_finder/screens/sign_up_page.dart';
import '../services/auth_service.dart';
import '../app_theme.dart'; // keep for Theme Extension if needed

class MyAccountPage extends StatefulWidget {
  const MyAccountPage({Key? key}) : super(key: key);

  @override
  _MyAccountPageState createState() => _MyAccountPageState();
}

class _MyAccountPageState extends State<MyAccountPage> {
  bool _loading = true;
  bool _subscribed = false;
  String? _email;
  String? _displayName;
  String? _subscriptionExpires;
  bool _canceled = false;
  String? _error;

  static const _basePricingUrl = 'https://41265f55.anime-pricing.pages.dev';

  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _loadAccount();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) {
            final url = request.url;
            if (url.contains('/subscribe/success')) {
              setState(() {
                _subscribed = true;
                _canceled = false;
              });
              Navigator.of(context).pop();
              Future.delayed(const Duration(seconds: 3), _loadAccount);
              return NavigationDecision.prevent;
            }
            if (url.contains('/subscribe/cancel')) {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Checkout canceled')),
              );
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      );
  }

  Future<void> _loadAccount() async {
    setState(() => _loading = true);

    try {
      final resp = await AuthService.me();
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final isSubscribed = data['is_subscribed'] as bool? ?? false;
        final expires = data['subscription_expires'] as String?;

        setState(() {
          _displayName = data['display_name'] as String?;
          _email = data['email'] as String?;
          _subscribed = isSubscribed;
          _subscriptionExpires = expires;
          _canceled = data['cancel_at_period_end'] as bool? ?? false;
          _error = null;
        });
      } else {
        setState(() => _error = 'Could not load account info');
      }
    } catch (_) {
      setState(() => _error = 'Unexpected error');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _openPricingTable() async {
    final token = await AuthService.getToken();
    if (token == null) {
      _showSnack('Not signed in');
      return;
    }
    final url = '$_basePricingUrl?token=$token';

    _controller.loadRequest(Uri.parse(url));

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            leading: BackButton(onPressed: () => Navigator.of(context).pop()),
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: const Text('Choose Your Plan'),
            centerTitle: true,
          ),
          body: WebViewWidget(controller: _controller),
        ),
      ),
    );

    await _loadAccount();
  }

  Future<bool> _confirmCancelSubscription() async {
    final scheme = Theme.of(context).colorScheme;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Cancel subscription?'),
        content: Text(
          _subscriptionExpires != null
              ? 'Your plan will remain active until $_subscriptionExpires.\n\nDo you want to schedule cancellation now?'
              : 'Do you want to schedule cancellation now?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep Plan'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
              minimumSize: const Size(0, 40),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel Plan'),
          ),
        ],
      ),
    );

    return ok == true;
  }

  Future<void> _cancelSubscription() async {
    final ok = await _confirmCancelSubscription();
    if (!ok) return;

    try {
      final resp = await AuthService.cancelSubscription();
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        await _loadAccount();
        _showSnack('Cancellation scheduled – active until $_subscriptionExpires');
      } else {
        _showSnack('Failed to Cancel: ${AuthService.readError(resp)}');
      }
    } catch (e) {
      _showSnack('Failed to cancel: $e');
    }
  }

  Future<void> _deleteAccount() async {
    final scheme = Theme.of(context).colorScheme;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Delete account?'),
        content: const Text('This cannot be undone. Are you sure?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
              minimumSize: const Size(0, 40),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final resp = await AuthService.deleteAccount();
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('access_token');

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const SignUpPage()),
        (route) => false,
      );
    } else {
      _showSnack('Could not delete account');
    }
  }

  Future<void> _logout() async {
    await AuthService.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const SignUpPage()),
      (route) => false,
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;

    // Always dark in this build
    const isDark = true;

    // Status -> icon/color/text
    final (IconData statusIcon, Color statusColor, String statusText) = () {
      if (_canceled) {
        return (Icons.hourglass_empty, scheme.tertiary, 'Canceled');
      }
      if (_subscribed) {
        return (Icons.check_circle, scheme.primary, 'Subscribed');
      }
      return (Icons.cancel, scheme.error, 'Not Subscribed');
    }();

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Account Settings '),
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null)
              ? Center(
                  child: Text(
                    _error!,
                    style: TextStyle(color: scheme.error),
                  ),
                )
              : SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(
      children: [
        // Profile header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [scheme.secondary, scheme.primary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 10,
                offset: Offset(0, 4),
              )
            ],
          ),
          child: Row(
            children: [
              Icon(Icons.account_circle, size: 64, color: scheme.onPrimary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _displayName ?? 'Unknown',
                      style: text.headlineSmall?.copyWith(color: scheme.onPrimary),
                    ),
                    Text(
                      _email ?? '',
                      style: text.bodyMedium?.copyWith(color: scheme.onPrimary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Subscription card
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 6,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: Column(
              children: [
                ListTile(
                  leading: Icon(statusIcon, color: statusColor, size: 32),
                  title: Text(statusText, style: text.titleMedium),
                  subtitle: _subscriptionExpires != null
                      ? Text('Active until $_subscriptionExpires', style: text.bodySmall)
                      : null,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: _openPricingTable,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: scheme.primary,
                        foregroundColor: scheme.onPrimary,
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        minimumSize: const Size(0, 44),
                      ),
                      child: Text((_canceled || !_subscribed) ? 'Subscribe' : 'Change Plan'),
                    ),
                    if (!_canceled && _subscribed) ...[
                      const SizedBox(width: 12),
                      OutlinedButton(
                        onPressed: _cancelSubscription,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: scheme.onSurface,
                          shape: const StadiumBorder(),
                          side: BorderSide(color: scheme.outline),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          minimumSize: const Size(0, 44),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 24),

        ListTile(
          leading: const Icon(Icons.lock_reset),
          title: const Text('Change password'),
          onTap: () => Navigator.pushNamed(context, '/forgot-password'),
        ),
        ListTile(
          leading: Icon(Icons.delete_forever, color: scheme.error),
          title: Text('Delete account', style: TextStyle(color: scheme.error)),
          onTap: _deleteAccount,
        ),
      ],
    ),
  ),
    );
  }
}
