// lib/screens/auth_screen.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthScreen extends StatefulWidget {
  @override
  _AuthScreenState createState() => _AuthScreenState();
}

enum AuthMode { Login, Signup, ForgotPassword, ResetPassword }

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _storage = FlutterSecureStorage();
  AuthMode _mode = AuthMode.Login;
  String _email = '', _password = '', _confirm = '', _resetToken = '';

  Future<void> _submit() async {
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;
    _formKey.currentState!.save();

    String url;
    Map<String,String> body;
    switch (_mode) {
      case AuthMode.Login:
        url = 'https://api.anime-seek.com/auth/login';
        // OAuth2PasswordRequestForm expects form-url-encoded
        body = {
          'username': _email,
          'password': _password,
        };
        break;
      case AuthMode.Signup:
        url = 'https://api.anime-seek.com/auth/register';
        body = json.encode({'email': _email, 'password': _password});
        break;
      case AuthMode.ForgotPassword:
        url = 'https://api.anime-seek.com/auth/password-reset-request';
        body = json.encode({'email': _email});
        break;
      case AuthMode.ResetPassword:
        url = 'https://api.anime-seek.com/password-reset';
        body = json.encode({
          'token': _resetToken,
          'new_password': _password,
        });
        break;
    }

    final headers = (_mode == AuthMode.Login)
        ? {'Content-Type': 'application/x-www-form-urlencoded'}
        : {'Content-Type': 'application/json'};

    final res = await http.post(
      Uri.parse(url),
      headers: headers,
      body: (_mode == AuthMode.Login) ? body : body,
    );

    if (res.statusCode == 200) {
      final data = json.decode(res.body);
      if (_mode == AuthMode.Login) {
        // store token for authenticated calls
        await _storage.write(key: 'token', value: data['access_token']);
      }
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Success! Check your email if applicable.'))
      );
      if (_mode == AuthMode.Signup || _mode == AuthMode.Login) {
        // navigate on login/signup
        Navigator.of(context).pushReplacementNamed('/home');
      }
    } else {
      final err = json.decode(res.body);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err['detail'] ?? 'Error'))
      );
    }
  }

  String? _validateEmail(String? v) {
    if (v == null || !v.contains('@')) return 'Enter a valid email';
    return null;
  }
  String? _validatePassword(String? v) {
    if (v == null || v.length < 7) return 'At least 7 chars';
    if (!RegExp(r'^(?=.*[A-Za-z])(?=.*\d)').hasMatch(v))
      return 'Include letters & numbers';
    return null;
  }

  @override
  Widget build(BuildContext ctx) {
    final isLogin = _mode == AuthMode.Login;
    return Scaffold(
      appBar: AppBar(title: Text('Welcome')),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(children: [
            if (_mode == AuthMode.ResetPassword)
              TextFormField(
                decoration: InputDecoration(labelText: 'Reset Token'),
                onSaved: (v) => _resetToken = v!.trim(),
              ),
            TextFormField(
              decoration: InputDecoration(labelText: 'Email'),
              validator: _validateEmail,
              onSaved: (v) => _email = v!.trim(),
            ),
            if (_mode != AuthMode.ForgotPassword)
              TextFormField(
                decoration: InputDecoration(labelText: 'Password'),
                obscureText: true,
                validator: _validatePassword,
                onSaved: (v) => _password = v!.trim(),
              ),
            if (_mode == AuthMode.Signup || _mode == AuthMode.ResetPassword)
              TextFormField(
                decoration: InputDecoration(labelText: 'Confirm Password'),
                obscureText: true,
                validator: (v) =>
                v != _password ? 'Passwords do not match' : null,
                onSaved: (v) => _confirm = v!.trim(),
              ),
            SizedBox(height: 20),
            ElevatedButton(
              child: Text({
                AuthMode.Login:    'Login',
                AuthMode.Signup:   'Sign Up',
                AuthMode.ForgotPassword: 'Send Reset Link',
                AuthMode.ResetPassword:  'Reset Password',
              }[_mode]!),
              onPressed: _submit,
            ),
            TextButton(
              child: Text({
                AuthMode.Login: 'Need an account? Sign up',
                AuthMode.Signup: 'Have an account? Login',
                AuthMode.Login: 'Forgot password?',
                AuthMode.ForgotPassword: 'Back to login',
                AuthMode.ResetPassword: 'Back to login',
              }[_mode]!),
              onPressed: () => setState(() {
                if (_mode == AuthMode.Login)       _mode = AuthMode.Signup;
                else if (_mode == AuthMode.Signup) _mode = AuthMode.Login;
                else if (_mode == AuthMode.ForgotPassword) _mode = AuthMode.Login;
                else if (_mode == AuthMode.Login)  _mode = AuthMode.ForgotPassword;
              }),
            ),
          ]),
        ),
      ),
    );
  }
}
