import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:app_links/app_links.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:http/http.dart' as http;
import 'package:anime_finder/models/scene_history_model.dart';
import 'app_theme.dart';
import 'screens/discover_profiles_page.dart';
import 'screens/reset_password_page.dart';
import 'screens/sign_up_page.dart';
import 'screens/subscription_screen.dart';
import 'screens/main_recognition_page.dart';
import 'screens/swipe_tab_page.dart';
import 'screens/verify_email_page.dart';
import 'screens/my_account_page.dart';
import 'screens/feed_page.dart';
import 'screens/notifications_page.dart';
import 'screens/profile_page.dart';
import 'services/api_client.dart';
import 'services/audio_service.dart';
import 'models/favorites_model.dart';
import 'models/playlist_model.dart';
import 'services/auth_service.dart';
import 'services/api_service.dart';
import 'screens/guess_scene_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  Stripe.publishableKey =
      'pk_live_51NbBcWEPXcmiHjwxDzuZg9PySEcHYAhGQ08IyOYnb3erBriUcqgBMUf7sgOspVtHPObrJpx7e433eyIfdCAbxECQ00o9x0KVRL';

  ApiService.configure(
    baseUrl: 'https://anime-seek.com/fastapi',
    authToken: '',
  );

  runApp(
    Provider<ApiClient>(
      create: (_) => ApiClient(baseUrl: 'https://anime-seek.com/fastapi'),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final AppLinks _appLinks;

  @override
  void initState() {
    super.initState();
    _appLinks = AppLinks();

    _appLinks.uriLinkStream.listen((Uri? uri) {
      if (!mounted || uri == null) return;

      if (uri.path.endsWith('/verify-email')) {
        final token = uri.queryParameters['token'];
        if (token != null && token.isNotEmpty) {
          Navigator.of(context).pushNamed('/verify', arguments: token);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AudioService()),
        ChangeNotifierProvider(create: (_) => FavoritesModel()),
        ChangeNotifierProvider(create: (_) => SceneHistoryModel()),
        ChangeNotifierProvider(
          create: (_) {
            final model = PlaylistsModel();
            model.load();
            return model;
          },
        ),
      ],
      child: SceneHistoryScopeBootstrapper(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Anime Seek',
          theme: AppTheme.theme,
          initialRoute: '/signup',
          routes: {
            '/signup': (_) => const SignUpPage(),
            '/': (_) => const MainRecognitionPage(),
            '/tabs': (_) => const SwipeTabPage(),
            '/feed': (_) => const FeedPage(),
            '/account': (_) => const MyAccountPage(),
            '/notifications': (_) => const NotificationsPage(),
            '/myaccount': (_) => const SubscriptionScreen(),
            '/forgot-password': (_) => const ForgotPasswordPage(),
            '/verify': (_) => const VerifyEmailPage(),
            '/discover-profiles': (_) => const DiscoverProfilesPage(),
          },
          onGenerateRoute: (settings) {
            if (settings.name == '/profile') {
              final args = settings.arguments as Map<String, dynamic>?;
              return MaterialPageRoute(
                builder: (_) => ProfilePage(userId: args?['userId'] ?? 0),
              );
            }
            return null;
          },
        ),
      ),
    );
  }
}

/// Runs once after providers are mounted to set SceneHistoryModel scope
/// to the current user's api_key (or "guest" if unauthenticated).
class SceneHistoryScopeBootstrapper extends StatefulWidget {
  final Widget child;

  const SceneHistoryScopeBootstrapper({
    Key? key,
    required this.child,
  }) : super(key: key);

  @override
  State<SceneHistoryScopeBootstrapper> createState() =>
      _SceneHistoryScopeBootstrapperState();

  static Future<void> refresh(BuildContext context) async {
    await _setHistoryScope(context);
  }

  static Future<void> _setHistoryScope(BuildContext context) async {
    try {
      final headers = await AuthService.authHeaders;

      final authHeader = (headers['Authorization'] ?? '').toString();
      final token =
          authHeader.startsWith('Bearer ') ? authHeader.substring(7) : '';

      ApiService.configure(
        baseUrl: 'https://anime-seek.com/fastapi',
        authToken: token,
      );

      final res = await http.get(
        Uri.parse('https://anime-seek.com/fastapi/auth/me'),
        headers: headers,
      );

      final model = context.read<SceneHistoryModel>();

      if (res.statusCode == 200) {
        final me = jsonDecode(res.body) as Map<String, dynamic>;
        final apiKey = (me['api_key'] ?? '').toString();
        await model.setActiveApiKeyScope(apiKey);
      } else {
        await model.setActiveApiKeyScope(null);
      }
    } catch (_) {
      if (context.mounted) {
        await context.read<SceneHistoryModel>().setActiveApiKeyScope(null);
      }
    }
  }
}

class _SceneHistoryScopeBootstrapperState
    extends State<SceneHistoryScopeBootstrapper> {
  bool _didRun = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didRun) return;
    _didRun = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          SceneHistoryScopeBootstrapper._setHistoryScope(context);
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}