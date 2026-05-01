// lib/screens/sign_up_page.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:profanity_filter/profanity_filter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../services/auth_service.dart';
import './verify_email_page.dart';

class SignUpPage extends StatelessWidget {
  const SignUpPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;

    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 800),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              scheme.primary,
              scheme.secondary,
              scheme.surface,
              scheme.tertiary,
            ],
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
                color: scheme.surface.withOpacity(0.95),
                elevation: 16,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: DefaultTabController(
                  length: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          'assets/LastSupper.jpg',
                          width: 600,
                          height: 100,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Welcome to AnimeSeek',
                          style: text.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: scheme.onSurface,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Step into the World of Anime\nSenpai Is Watching!',
                          style: text.bodyMedium?.copyWith(
                            color: scheme.onSurface.withOpacity(0.8),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        Container(
                          decoration: BoxDecoration(
                            color: scheme.secondaryContainer.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: TabBar(
                            indicator: BoxDecoration(
                              color: scheme.surface,
                              borderRadius: const BorderRadius.all(
                                Radius.circular(30),
                              ),
                            ),
                            labelColor: scheme.onSecondaryContainer,
                            unselectedLabelColor:
                                scheme.onSecondaryContainer.withOpacity(0.7),
                            tabs: const [
                              Tab(text: 'SIGN IN'),
                              Tab(text: 'SIGN UP'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 400,
                          child: TabBarView(
                            children: [
                              _SignInForm(accent: scheme.primary),
                              _SignUpForm(accent: scheme.primary),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('Or continue with  ', style: text.bodySmall),
                            const Icon(Icons.account_circle, size: 24),
                            const SizedBox(width: 16),
                            const Icon(Icons.alternate_email, size: 24),
                          ],
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

/// Note: kept your function but made it safe by allowing an optional tokenJson
/// so there’s no compile error. If you have a token map, pass it in; otherwise it’s ignored.
Future<String> getProviderUid({Map<String, dynamic>? tokenJson}) async {
  final prefs = await SharedPreferences.getInstance();

  final maybeToken = tokenJson?['access_token'];
  if (maybeToken is String && maybeToken.isNotEmpty) {
    await prefs.setString('access_token', maybeToken);
  }

  var uid = prefs.getString('provider_uid');
  if (uid == null) {
    uid = const Uuid().v4();
    await prefs.setString('provider_uid', uid);
  }
  return uid;
}

// ── SIGN IN FORM ─────────────────────────────────────────────────────────

class _SignInForm extends StatefulWidget {
  final Color accent;
  const _SignInForm({required this.accent});

  @override
  __SignInFormState createState() => __SignInFormState();
}

class __SignInFormState extends State<_SignInForm> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _loading = false;
  bool _obscure = true;
  bool _remember = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _showFriendlyError(Object e) {
    String message = 'Something went wrong. Please try again.';

    if (e is SocketException) {
      message =
          'No internet connection. Please check your connection and try again.';
    } else if (e is TimeoutException) {
      message = 'Connection timed out. Please try again.';
    }

    if (mounted) {
      setState(() => _error = message);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (mounted) {
      setState(() {
        _error = null;
        _loading = true;
      });
    }

    try {
      final resp = await AuthService.login(
        email: _emailCtrl.text.trim().toLowerCase(),
        password: _passCtrl.text.trim(),
      );

      if (!mounted) return;

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        final token = (body['access_token'] as String?) ?? '';

        if (token.isNotEmpty) {
          await AuthService.saveToken(token);
        } else {
          debugPrint('[LOGIN] Missing access_token in response.');
        }

        final meResp = await AuthService.me();
        if (!mounted) return;

        if (meResp.statusCode >= 200 && meResp.statusCode < 300) {
          final meData = jsonDecode(meResp.body) as Map<String, dynamic>;
          final verified = meData['is_verified'] as bool? ?? false;

          final apiKey = (meData['api_key'] as String?)?.trim();
          if (apiKey != null && apiKey.isNotEmpty) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('api_key', apiKey);
            debugPrint(
              '[LOGIN] Saved api_key from /auth/me (${apiKey.substring(0, 4)}…${apiKey.substring(apiKey.length - 4)})',
            );
          } else {
            debugPrint(
              '[LOGIN] /auth/me did not include api_key. Ensure backend returns it if you rely on key-based auth.',
            );
          }

          if (verified) {
            Navigator.pushReplacementNamed(context, '/');
          } else {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const VerifyEmailPage()),
            );
          }
          return;
        } else {
          if (mounted) {
            setState(() => _error = 'Failed to fetch user info');
          }
          return;
        }
      }

      String message;
      if (resp.statusCode == 401) {
        message = 'Invalid email or password.';
      } else {
        try {
          final body = jsonDecode(resp.body);
          message = body['detail']?.toString() ?? resp.body;
        } catch (_) {
          message = 'Unexpected error (${resp.statusCode}).';
        }
      }

      if (mounted) {
        setState(() => _error = message);
      }
    } on SocketException catch (e) {
      _showFriendlyError(e);
    } on TimeoutException catch (e) {
      _showFriendlyError(e);
    } catch (e) {
      _showFriendlyError(e);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthForm(
      formKey: _formKey,
      emailCtrl: _emailCtrl,
      passCtrl: _passCtrl,
      buttonLabel: _loading ? '…' : 'Sign in →',
      onSubmit: _submit,
      showForgot: true,
      errorText: _error,
      accentColor: widget.accent,
      obscureText: _obscure,
      onToggleObscure: () => setState(() => _obscure = !_obscure),
      showRemember: true,
      rememberValue: _remember,
      onRememberChanged: (v) => setState(() => _remember = v ?? false),
    );
  }
}

// ── SIGN UP FORM ─────────────────────────────────────────────────────────

class _SignUpForm extends StatefulWidget {
  final Color accent;
  const _SignUpForm({required this.accent});

  @override
  __SignUpFormState createState() => __SignUpFormState();
}

class __SignUpFormState extends State<_SignUpForm> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  final _profanityFilter = ProfanityFilter();
  final _nameRegExp = RegExp(r'^[A-Za-z0-9_-]{3,30}$');

  bool _obscure = true;
  bool _loading = false;
  bool _nameAvailable = true;
  String? _error;
  Timer? _debounce;
  bool _emailExists = false;
  bool _acceptedTerms = false;

  static const String _termsUrl = 'https://anime-seek.com/terms';
  static const String _privacyUrl = 'https://anime-seek.com/privacy';

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open link')),
      );
    }
  }

  void _showFriendlyError(Object e) {
    String message = 'Something went wrong. Please try again.';

    if (e is SocketException) {
      message =
          'No internet connection. Please check your connection and try again.';
    } else if (e is TimeoutException) {
      message = 'Connection timed out. Please try again.';
    }

    if (mounted) {
      setState(() => _error = message);
    }
  }

  String? _displayNameValidator(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    final trimmed = v.trim();

    if (!_nameRegExp.hasMatch(trimmed)) {
      return '3–30 chars: letters, numbers, _ or - only';
    }

    final lower = trimmed.toLowerCase();

    const banned = [
      'fuck',
      'shit',
      'bitch',
      'asshole',
      '@sshole',
      'assh0le',
      'damn',
      'hell',
      'arsehole',
      'balls',
      'b@lls',
      'bastard',
      'b!tch',
      'b1tch',
      'bloody',
      'bollocks',
      'bugger',
      'cock',
      'cunt',
      'crap',
      'dick',
      'dickhead',
      'fanny',
      'goddamn',
      'git',
      'motherfucker',
      'piss',
      'prick',
      'shag',
      'slut',
      'sod',
      'tits',
      'twat',
      'wanker',
      'faggot',
      'fagg@t',
      'fag',
      'f@ggot',
      'whore',
      'wh0re',
      'wh@re',
      'creator',
      'administrator',
      'administr@tor',
    ];

    for (final bad in banned) {
      if (lower.contains(bad)) return 'Please choose a less offensive name';
    }
    if (_profanityFilter.hasProfanity(trimmed)) {
      return 'Please choose a less offensive name';
    }

    if (!_nameAvailable) return 'Display name is already taken';

    return null;
  }

  void _onNameChanged(String val) {
    _debounce?.cancel();
    setState(() => _nameAvailable = true);

    _debounce = Timer(const Duration(milliseconds: 500), () async {
      final trimmed = val.trim();
      if (!_nameRegExp.hasMatch(trimmed)) return;
      final ok = await AuthService.checkDisplayName(trimmed);
      if (mounted) {
        setState(() => _nameAvailable = ok);
      }
    });
  }

  @override
  void dispose() {
    _displayNameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_acceptedTerms) {
      _showSnack('Please accept the Terms and Privacy Policy to continue.');
      return;
    }

    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _emailExists = false;
      });
    }

    try {
      final success = await AuthService.signup(
        displayName: _displayNameCtrl.text.trim(),
        email: _emailCtrl.text.trim().toLowerCase(),
        password: _passCtrl.text.trim(),
      );

      if (success && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const VerifyEmailPage()),
        );
        return;
      }
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      if (mounted) {
        if (msg.contains('already registered')) {
          setState(() => _emailExists = true);
        } else {
          setState(() => _error = e.message);
        }
      }
    } on SocketException catch (e) {
      _showFriendlyError(e);
    } on TimeoutException catch (e) {
      _showFriendlyError(e);
    } catch (e) {
      _showFriendlyError(e);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canSubmit = !_loading && _nameAvailable && _acceptedTerms;

    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _displayNameCtrl,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              decoration: InputDecoration(
                labelText: 'Display Name',
                prefixIcon: Icon(Icons.person, color: widget.accent),
                border: const OutlineInputBorder(),
                suffixIcon: _displayNameCtrl.text.isEmpty
                    ? null
                    : (_nameAvailable
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : const Icon(Icons.error, color: Colors.red)),
              ),
              validator: _displayNameValidator,
              onChanged: _onNameChanged,
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _emailCtrl,
              decoration: InputDecoration(
                labelText: 'Email Address',
                prefixIcon: Icon(Icons.email, color: widget.accent),
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
                if (_emailExists) return 'This email is already registered';
                return null;
              },
              onChanged: (_) {
                if (_emailExists) {
                  setState(() => _emailExists = false);
                }
              },
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _passCtrl,
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: Icon(Icons.lock, color: widget.accent),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility_off : Icons.visibility,
                    color: widget.accent,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
                border: const OutlineInputBorder(),
              ),
              obscureText: _obscure,
              validator: (v) =>
                  (v == null || v.length < 6) ? 'Min 6 characters' : null,
            ),
            const SizedBox(height: 12),

            CheckboxListTile(
              value: _acceptedTerms,
              onChanged: (v) => setState(() => _acceptedTerms = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Wrap(
                children: [
                  const Text('I agree to the '),
                  InkWell(
                    onTap: () => _openUrl(_termsUrl),
                    child: Text(
                      'Terms of Service',
                      style: TextStyle(
                        color: widget.accent,
                        decoration: TextDecoration.underline,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Text(' and '),
                  InkWell(
                    onTap: () => _openUrl(_privacyUrl),
                    child: Text(
                      'Privacy Policy',
                      style: TextStyle(
                        color: widget.accent,
                        decoration: TextDecoration.underline,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Text('.'),
                ],
              ),
            ),
            const SizedBox(height: 8),

            if (_error != null) ...[
              Text(_error!, style: TextStyle(color: scheme.error)),
              const SizedBox(height: 12),
            ],

            ElevatedButton(
              onPressed: canSubmit ? _submit : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.accent,
                foregroundColor: scheme.onPrimary,
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
                  : const Text('Next →'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── INTERNAL AUTH FORM ────────────────────────────────────────────────────

class _AuthForm extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController emailCtrl;
  final TextEditingController passCtrl;
  final String buttonLabel;
  final VoidCallback onSubmit;
  final bool showForgot;
  final String? errorText;
  final Color accentColor;
  final bool obscureText;
  final VoidCallback onToggleObscure;
  final bool showRemember;
  final bool rememberValue;
  final ValueChanged<bool?>? onRememberChanged;

  const _AuthForm({
    required this.formKey,
    required this.emailCtrl,
    required this.passCtrl,
    required this.buttonLabel,
    required this.onSubmit,
    required this.showForgot,
    this.errorText,
    required this.accentColor,
    required this.obscureText,
    required this.onToggleObscure,
    this.showRemember = false,
    this.rememberValue = false,
    this.onRememberChanged,
  });

  String? _validateEmail(String? v) =>
      (v == null || !v.contains('@')) ? 'Enter valid email' : null;

  String? _validatePassword(String? v) =>
      (v == null || v.length < 6) ? 'Min 6 chars' : null;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: emailCtrl,
            decoration: InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.email, color: accentColor),
              border: const OutlineInputBorder(),
            ),
            keyboardType: TextInputType.emailAddress,
            validator: _validateEmail,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: passCtrl,
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: Icon(Icons.lock, color: accentColor),
              suffixIcon: IconButton(
                icon: Icon(
                  obscureText ? Icons.visibility_off : Icons.visibility,
                  color: accentColor,
                ),
                onPressed: onToggleObscure,
              ),
              border: const OutlineInputBorder(),
            ),
            obscureText: obscureText,
            validator: _validatePassword,
          ),
          if (showRemember) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Checkbox(
                  value: rememberValue,
                  activeColor: accentColor,
                  onChanged: onRememberChanged,
                ),
                const Text('Remember me'),
              ],
            ),
          ],
          if (showForgot) ...[
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () =>
                    Navigator.pushNamed(context, '/forgot-password'),
                child: const Text('Forgot Password?'),
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (errorText != null)
            Text(errorText!, style: TextStyle(color: scheme.error)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: onSubmit,
            style: ElevatedButton.styleFrom(
              backgroundColor: accentColor,
              foregroundColor: scheme.onPrimary,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
            child: Text(buttonLabel),
          ),
        ],
      ),
    );
  }
}

// ── FORGOT PASSWORD ──────────────────────────────────────────────────────

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({Key? key}) : super(key: key);

  @override
  _ForgotPasswordPageState createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _emailCtrl = TextEditingController();
  bool _loading = false;
  bool _sent = false;
  String? _error;

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      if (mounted) setState(() => _error = 'Enter a valid email');
      return;
    }

    if (mounted) {
      setState(() {
        _error = null;
        _loading = true;
      });
    }

    try {
      final resp = await AuthService.forgotPassword(
        email: email.toLowerCase(),
      );

      if (!mounted) return;

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        setState(() => _sent = true);
      } else {
        setState(() => _error = 'Failed to send reset email');
      }
    } on SocketException {
      if (mounted) {
        setState(() => _error =
            'No internet connection. Please check your connection and try again.');
      }
    } on TimeoutException {
      if (mounted) {
        setState(() => _error = 'Connection timed out. Please try again.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Reset Password')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _sent
            ? Center(
                child: Text(
                  'Check your inbox for reset link',
                  style: text.bodyLarge,
                ),
              )
            : Column(
                children: [
                  TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      errorText: _error,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: scheme.primary,
                      foregroundColor: scheme.onPrimary,
                    ),
                    child: _loading
                        ? const CircularProgressIndicator()
                        : const Text('Send Reset Link'),
                  ),
                ],
              ),
      ),
    );
  }
}