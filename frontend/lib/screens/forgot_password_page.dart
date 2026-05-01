import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'verify_email_page.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({Key? key}) : super(key: key);

  @override
  _ForgotPasswordPageState createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  bool _loading = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final resp = await AuthService.forgotPassword(
      email: _emailCtrl.text.trim().toLowerCase(),
    );
    setState(() {
      _loading = false;
    });

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      setState(() {
        _sent = true;
      });
    } else {
      String serverMessage;
      try {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        serverMessage = (body['message'] as String?) ?? resp.body;
      } catch (_) {
        serverMessage = resp.body;
      }
      setState(() {
        _error = serverMessage;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const burgundy = Color(0xFF000000);
    const tealGreen = Color(0xFFfcdca9);
    const ivory = Color(0xFFFFFFFF);
    const chartreuse = Color(0xFFecc4b3);

    return Scaffold(
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
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
                  child: _sent ? _buildSentView() : _buildForm(burgundy),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(Color burgundy) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Reset Password',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: burgundy,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            'Enter your email address and we\'ll send you a link to reset your password.',
            style: TextStyle(color: burgundy.withOpacity(0.8)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _emailCtrl,
            decoration: InputDecoration(
              labelText: 'Email Address',
              prefixIcon: Icon(Icons.email, color: burgundy),
              border: const OutlineInputBorder(),
              errorStyle: const TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
                fontStyle: FontStyle.italic,
              ),
            ),
            keyboardType: TextInputType.emailAddress,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: (v) {
              if (v == null || !v.contains('@')) return 'Enter a valid email';
              return null;
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          ],
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loading ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: burgundy,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
            child: _loading
                ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
                : const Text('Send Reset Link →', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildSentView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: const [
        Icon(Icons.check_circle_outline, size: 80, color: Colors.green),
        SizedBox(height: 16),
        Text(
          'Email Sent!',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: 8),
        Text(
          'Please check your inbox for the password reset link.',
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
