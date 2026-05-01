// lib/screens/sign_up_page.dart
//
// Updates:
// 1) Calls AuthService.init() once (so your CookieJar / persistent cookies are ready).
// 2) After a successful login/signup, calls AuthService.primeSession() to ensure the
//    session is valid (optionally does /auth/me and refresh if needed).
// 3) Adds mounted-checks around setState/navigation to avoid async UI crashes.
//
// NOTE: These additions assume you’ve updated AuthService to persist cookies
// (recommended: Dio + CookieJar). This page keeps your existing structure.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/auth_service.dart';

enum AuthFormType { signUp, signIn }

class SignUpPage extends StatefulWidget {
  const SignUpPage({Key? key}) : super(key: key);
  @override
  _SignUpPageState createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  AuthFormType _formType = AuthFormType.signUp;
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _displayNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  String _error = '';
  bool _loading = false;

  @override
  void initState() {
    super.initState();

    // Ensure the auth client is initialized (CookieJar / persisted cookies, etc.)
    // Safe to call multiple times; AuthService should internally no-op after first init.
    AuthService.init().catchError((_) {
      // Don’t block UI if init fails; user will see errors on submit if any.
    });
  }

  @override
  void dispose() {
    _displayNameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _toggleFormType() {
    setState(() {
      _formType =
          _formType == AuthFormType.signUp ? AuthFormType.signIn : AuthFormType.signUp;
      _error = '';
      _formKey.currentState?.reset();
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = '';
    });

    final displayName = _displayNameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    http.Response resp;

    try {
      if (_formType == AuthFormType.signUp) {
        resp = await AuthService.signup(
          displayName: displayName,
          email: email,
          password: password,
        );
      } else {
        resp = await AuthService.login(
          email: email,
          password: password,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Network error. Please try again.';
      });
      return;
    }

    if (!mounted) return;
    setState(() => _loading = false);

    if (resp.statusCode == 200 || resp.statusCode == 201) {
      // IMPORTANT:
      // Make sure tokens/cookies are persisted and session is primed.
      // primeSession() should typically:
      // - store cookies (if using a cookie-capable client)
      // - optionally call /auth/me; if 401, call /auth/refresh; then /auth/me again
      try {
        await AuthService.primeSession();
      } catch (_) {
        // Even if priming fails, proceed; the home page can trigger refresh logic too.
      }

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/');
    } else {
      // try to parse JSON { detail: "..." }
      String detail;
      try {
        final data = jsonDecode(resp.body);
        detail = (data is Map && data['detail'] != null) ? data['detail'].toString() : resp.body;
      } catch (_) {
        detail = resp.body;
      }

      // catch display-name-unique error
      if (detail.toLowerCase().contains('display') && detail.toLowerCase().contains('taken')) {
        setState(() => _error = 'That display name is already taken.');
      } else if (detail.toLowerCase().contains('account') &&
          detail.toLowerCase().contains('not') &&
          detail.toLowerCase().contains('found')) {
        setState(() => _error = 'Account not found. Please check your email and try again.');
      } else {
        setState(() => _error = detail);
      }
    }
  }

  String? _validateDisplayName(String? v) {
    if (_formType == AuthFormType.signUp) {
      if (v == null || v.trim().isEmpty) {
        return 'Please choose a display name';
      }
    }
    return null;
  }

  String? _validateEmail(String? v) {
    if (v == null || !v.contains('@')) return 'Enter a valid email';
    return null;
  }

  String? _validatePassword(String? v) {
    if (v == null || v.length < 6) return 'Min 6 characters';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isSignIn = _formType == AuthFormType.signIn;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 8,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isSignIn ? 'Welcome Back' : 'Create Account',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 24),
                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          if (!isSignIn) ...[
                            // Display Name Field (only on Sign Up)
                            TextFormField(
                              controller: _displayNameCtrl,
                              decoration: InputDecoration(
                                labelText: 'Display Name',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              validator: _validateDisplayName,
                            ),
                            const SizedBox(height: 16),
                          ],

                          // Email Field
                          TextFormField(
                            controller: _emailCtrl,
                            decoration: InputDecoration(
                              labelText: 'Email',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            validator: _validateEmail,
                          ),
                          const SizedBox(height: 16),

                          // Password Field
                          TextFormField(
                            controller: _passwordCtrl,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            obscureText: true,
                            validator: _validatePassword,
                          ),
                          const SizedBox(height: 24),

                          // Submit Button
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _loading ? null : _submit,
                              child: _loading
                                  ? const SizedBox(
                                      height: 16,
                                      width: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(isSignIn ? 'Sign In' : 'Sign Up'),
                            ),
                          ),

                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: _toggleFormType,
                            child: Text(
                              isSignIn ? 'Don’t have an account? Sign Up' : 'Have an account? Sign In',
                            ),
                          ),

                          if (_error.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Text(
                              _error,
                              style: const TextStyle(color: Colors.redAccent),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
