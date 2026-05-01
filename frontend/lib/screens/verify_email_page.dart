import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class VerifyEmailPage extends StatefulWidget {
  const VerifyEmailPage({Key? key}) : super(key: key);

  @override
  _VerifyEmailPageState createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends State<VerifyEmailPage> {
  static const Color burgundy   = Color(0xFF000000);
  static const Color tealGreen  = Color(0xFFfcdca9);
  static const Color ivory      = Color(0xFFFFFFFF);
  static const Color chartreuse = Color(0xFFecc4b3);

  bool _loading = false;
  String _message = 'A verification link has been sent to your email.\n'
      'Once you click it in your mail client, tap “Refresh Status”.';

  Future<void> _refreshStatus() async {
    setState(() {
      _loading = true;
      _message = '';
    });

    final resp = await AuthService.me();  // calls GET /auth/me

    setState(() => _loading = false);

    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['is_verified'] == true) {
        Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false);
        return;
      } else {
        setState(() {
          _message = 'Still not verified. Have you clicked the link in your inbox?';
        });
      }
    } else {
      setState(() {
        if (resp.statusCode == 401) {
          _message = 'Email not verified yet.';
        } else {
          _message = 'Error fetching status (${resp.statusCode}).';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false, // disable back
      child: Scaffold(
        body: AnimatedContainer(
          duration: const Duration(milliseconds: 800),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [burgundy, tealGreen, ivory, chartreuse],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Card(
                  color: ivory.withOpacity(0.95),
                  elevation: 16,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.email, size: 64, color: burgundy),
                        const SizedBox(height: 16),
                        Text(
                          _message,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 16, color: burgundy),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _loading ? null : _refreshStatus,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: chartreuse,
                            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: _loading
                              ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                          )
                              : const Text('Refresh Status', style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
