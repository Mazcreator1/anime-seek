// lib/services/auth_service.dart

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// Kept (you had this import; leaving it to avoid breaking anything that relies on side effects)
import 'package:anime_finder/screens/sign_up_page.dart';

/// Thrown when an auth endpoint returns an error status.
class AuthException implements Exception {
  final int statusCode;
  final String message;
  AuthException(this.statusCode, this.message);
  @override
  String toString() => 'AuthException($statusCode): $message';
}

/// Quota info (stubbed as unlimited with quota disabled)
class QuotaInfo {
  final String tier;
  final int tierId;
  final int quota;
  final int usedToday;
  final int remaining;
  final String keySource;
  final DateTime? resetsAt;

  const QuotaInfo({
    this.tier = 'Unlimited',
    this.tierId = 3,
    this.quota = 2147483647,
    this.usedToday = 0,
    this.remaining = 2147483647,
    this.keySource = 'disabled',
    this.resetsAt,
  });
}

class AuthService {
  // Base API (FastAPI)
  static const String _baseUrl = 'https://anime-seek.com/fastapi';

  // Refresh endpoint path (relative to _baseUrl)
  static const String _refreshPath = '/auth/refresh';

  // Storage keys
  static const String _kAccessTokenKey = 'access_token';
  static const String _kRefreshTokenKey = 'refresh_token';
  static const String _kTokenExpiresAtMs = 'token_expires_at_ms';
  static const String _kApiKeyKey = 'api_key';

  // Core headers
  static const Map<String, String> _jsonHeaders = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };
  static Map<String, String> get jsonHeaders => _jsonHeaders;

  // In-memory cache for /auth/me
  static Map<String, dynamic>? _currentUser;

  // =========================
  // NEW: Shared Dio + auto-refresh
  // =========================

  static Dio? _dio;

  /// Use this Dio everywhere (AnalyticsModel, feed, etc.) to get consistent auth + refresh behavior.
  static Dio get dio {
    _dio ??= Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      headers: {
        'Accept': 'application/json',
      },
    ))
      ..interceptors.add(_AuthDioInterceptor())
      ..interceptors.add(LogInterceptor(
        request: true,
        requestHeader: true,
        responseHeader: true,
        responseBody: true,
        error: true,
      ));

    return _dio!;
  }

  // ----- Display-name check -----
  static Future<bool> checkDisplayName(String name) async {
    final uri = Uri.parse(
      '$_baseUrl/auth/check-display-name?display_name=${Uri.encodeQueryComponent(name)}',
    );
    final resp = await http.get(uri, headers: jsonHeaders);
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return data['available'] as bool;
    }
    throw Exception('Failed to check display name (status: ${resp.statusCode})');
  }

  // Cached fields
  static int? get currentUserId => _currentUser?['id'] as int?;
  static String? get currentUserName => _currentUser?['display_name'] as String?;
  static String get currentUserAvatar {
    final url = _currentUser?['avatar_url'] as String?;
    if (url == null || url.isEmpty || url == '/') {
      return 'https://anime-seek.com/uploads/user_avatars/default_avatar.jpg';
    }
    if (url.startsWith('http')) return url;
    return 'https://anime-seek.com$url';
  }

  /// Fetches and caches `/auth/me`.
  /// Also persists `api_key` (if present) so the network layer can include it on future requests.
  static Future<Map<String, dynamic>> getCurrentUser() async {
    if (_currentUser != null) return _currentUser!;
    final resp = await me();
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      _currentUser = data;

      final apiKey = (data['api_key'] as String?)?.trim();
      if (apiKey != null && apiKey.isNotEmpty) {
        await saveApiKey(apiKey);
      }

      return data;
    } else {
      throw AuthException(resp.statusCode, readError(resp));
    }
  }

  /// Extract a readable error message from a FastAPI-style response.
  static String readError(http.Response resp) {
    try {
      final decoded = jsonDecode(resp.body);

      if (decoded is Map<String, dynamic>) {
        final detail = decoded['detail'];
        if (detail is String && detail.isNotEmpty) return detail;

        final err = decoded['error'];
        if (err is String && err.isNotEmpty) return err;

        if (err is Map<String, dynamic>) {
          final msg = err['message'];
          if (msg is String && msg.isNotEmpty) return msg;
        }

        final message = decoded['message'];
        if (message is String && message.isNotEmpty) return message;
      }
    } catch (_) {
      // fall through
    }
    return resp.body.isNotEmpty ? resp.body : 'Request failed (status ${resp.statusCode})';
  }

  // =========================
  // Auth headers (http package)
  // =========================

  static Future<Map<String, String>> get authHeaders async {
    // Proactive refresh if near expiry
    await _ensureFreshAccessToken();

    final token = await getToken();
    final apiKey = await getApiKey();
    return {
      ..._jsonHeaders,
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      if (apiKey != null && apiKey.isNotEmpty) 'x-api-key': apiKey,
      if (apiKey != null && apiKey.isNotEmpty) 'X-API-Key': apiKey,
    };
  }

  // =========================
  // Token lifecycle tools
  // =========================

  /// Decode JWT exp -> DateTime.
  /// This is the critical fix: your backend does NOT return expires_in, so we must read exp from the JWT.
  static DateTime? _jwtExp(String jwtToken) {
    try {
      final parts = jwtToken.split('.');
      if (parts.length != 3) return null;

      String payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
      while (payload.length % 4 != 0) {
        payload += '=';
      }

      final decoded = jsonDecode(utf8.decode(base64Decode(payload)));
      if (decoded is! Map<String, dynamic>) return null;

      final exp = decoded['exp'];
      if (exp is int) return DateTime.fromMillisecondsSinceEpoch(exp * 1000);
      if (exp is num) return DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000);
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _saveTokensFromBody(Map<String, dynamic> body) async {
    final access = (body['access_token'] as String?)?.trim();
    final refresh = (body['refresh_token'] as String?)?.trim();

    if (access != null && access.isNotEmpty) {
      await saveToken(access); // saveToken also stores exp if present in JWT
    }
    if (refresh != null && refresh.isNotEmpty) {
      await saveRefreshToken(refresh);
    }

    // If backend ever adds these fields, still support them
    int? expiresInSeconds;
    final ei = body['expires_in'];
    final aei = body['access_expires_in'];
    if (ei is int) expiresInSeconds = ei;
    if (aei is int) expiresInSeconds = aei;

    final exp = body['exp'];
    if (expiresInSeconds != null && expiresInSeconds > 0) {
      final expiresAt = DateTime.now().add(Duration(seconds: expiresInSeconds));
      await saveTokenExpiresAt(expiresAt);
    } else if (exp is int && exp > 0) {
      await saveTokenExpiresAt(DateTime.fromMillisecondsSinceEpoch(exp * 1000));
    } else if (access != null && access.isNotEmpty) {
      // Fallback: decode exp from JWT (main path for your backend)
      final expiresAt = _jwtExp(access);
      if (expiresAt != null) {
        await saveTokenExpiresAt(expiresAt);
      }
    }
  }

  /// If token is near expiry, refresh it (no-op if we don't have refresh token or expiry info).
  static Future<void> _ensureFreshAccessToken() async {
    final refresh = await getRefreshToken();
    if (refresh == null || refresh.isEmpty) return;

    final expiresAt = await getTokenExpiresAt();
    if (expiresAt == null) return;

    // Refresh early (2 minutes)
    final now = DateTime.now();
    if (expiresAt.isAfter(now.add(const Duration(minutes: 2)))) return;

    await refreshSession();
  }

  /// Force refresh using refresh token via JSON body (mobile-safe; avoids cookie dependencies).
  static Future<void> refreshSession() async {
    final refresh = await getRefreshToken();
    if (refresh == null || refresh.isEmpty) {
      throw AuthException(401, 'No refresh token available');
    }

    final uri = Uri.parse('$_baseUrl$_refreshPath');
    final resp = await http
        .post(uri, headers: _jsonHeaders, body: jsonEncode({'refresh_token': refresh}))
        .timeout(const Duration(seconds: 10));

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      await _saveTokensFromBody(body);
      _currentUser = null;
      return;
    }

    await logout();
    throw AuthException(resp.statusCode, readError(resp));
  }

  /// Auto-refresh on 401 ONCE for package:http calls, then retry.
  static Future<http.Response> _authedRequest(
    Future<http.Response> Function(Map<String, String> headers) requestFn,
  ) async {
    http.Response resp = await requestFn(await authHeaders);

    if (resp.statusCode != 401) return resp;

    try {
      await refreshSession();
    } catch (_) {
      return resp;
    }

    resp = await requestFn(await authHeaders);
    return resp;
  }

  // =========================
  // Registration
  // =========================
  static Future<bool> signup({
    required String displayName,
    required String email,
    required String password,
  }) async {
    final uri = Uri.parse('$_baseUrl/auth/register');
    final providerUid = await getProviderUid();
    final resp = await http.post(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode({
        'display_name': displayName,
        'email': email,
        'password': password,
        'provider_uid': providerUid,
      }),
    );

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      final body = jsonDecode(resp.body) as Map<String, dynamic>;

      // Keep original behavior (some flows used verification_token)
      final token = (body['access_token'] as String?) ?? (body['verification_token'] as String?);
      if (token == null) {
        throw AuthException(resp.statusCode, 'Missing token in signup response');
      }

      await saveToken(token);
      await _saveTokensFromBody(body); // stores refresh + expiry if present
      await getCurrentUser();
      return true;
    } else {
      throw AuthException(resp.statusCode, readError(resp));
    }
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAccessTokenKey);
    await prefs.remove(_kRefreshTokenKey);
    await prefs.remove(_kTokenExpiresAtMs);
    await prefs.remove(_kApiKeyKey);
    _currentUser = null;
  }

  // =========================
  // Login
  // =========================
  static Future<http.Response> login({
    required String email,
    required String password,
  }) async {
    final uri = Uri.parse('$_baseUrl/auth/token');
    final headers = {'Content-Type': 'application/x-www-form-urlencoded'};
    final body = {'grant_type': 'password', 'username': email, 'password': password};
    final resp = await http.post(uri, headers: headers, body: body).timeout(const Duration(seconds: 10));
    return resp;
  }

  static Future<http.Response> signIn(String email, String password) async {
    final resp = await login(email: email, password: password);
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      final body = jsonDecode(resp.body) as Map<String, dynamic>;

      final token = body['access_token'] as String?;
      if (token == null) {
        throw AuthException(resp.statusCode, 'Missing access_token in response');
      }

      // saveToken now also persists exp from JWT
      await saveToken(token);

      // store refresh token + (fallback) expiry
      await _saveTokensFromBody(body);

      await getCurrentUser();
      return resp;
    }
    throw AuthException(resp.statusCode, readError(resp));
  }

  // Forgot / Reset Password
  static Future<http.Response> forgotPassword({required String email}) {
    final uri = Uri.parse('$_baseUrl/auth/forgot-password');
    return http.post(uri, headers: _jsonHeaders, body: jsonEncode({'email': email}));
  }

  static Future<http.Response> resetPassword({
    required String token,
    required String newPassword,
  }) {
    final uri = Uri.parse('$_baseUrl/auth/reset-password');
    return http.post(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode({'token': token, 'new_password': newPassword}),
    );
  }

  // =========================
  // Me & token storage
  // =========================
  static Future<http.Response> me() async {
    final uri = Uri.parse('$_baseUrl/auth/me');
    return _authedRequest((headers) => http.get(uri, headers: headers));
  }

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAccessTokenKey, token);

    // Critical: store expiry from JWT exp so refresh logic actually runs
    final exp = _jwtExp(token);
    if (exp != null) {
      await saveTokenExpiresAt(exp);
    }
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kAccessTokenKey);
  }

  static Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAccessTokenKey);
  }

  // Refresh token persistence
  static Future<void> saveRefreshToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kRefreshTokenKey, token);
  }

  static Future<String?> getRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kRefreshTokenKey);
  }

  static Future<void> clearRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kRefreshTokenKey);
  }

  // Token expiry persistence
  static Future<void> saveTokenExpiresAt(DateTime expiresAt) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kTokenExpiresAtMs, expiresAt.millisecondsSinceEpoch);
  }

  static Future<DateTime?> getTokenExpiresAt() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_kTokenExpiresAtMs);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static Future<void> clearTokenExpiresAt() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kTokenExpiresAtMs);
  }

  // API key persistence/helpers
  static Future<void> saveApiKey(String apiKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kApiKeyKey, apiKey);
  }

  static Future<String?> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kApiKeyKey);
  }

  static Future<void> clearApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kApiKeyKey);
  }

  // =========================
  // Subscription / account
  // =========================
  static Future<http.Response> deleteAccount() async {
    final token = await getToken();
    if (token == null) throw Exception('Not signed in');

    final url = Uri.parse('$_baseUrl/auth/delete-me');
    final resp = await _authedRequest((headers) => http.delete(url, headers: headers));

    if (resp.statusCode == 200 || resp.statusCode == 204) {
      await clearToken();
      await clearRefreshToken();
      await clearTokenExpiresAt();
      await clearApiKey();
      _currentUser = null;
    }
    return resp;
  }

  static Future<http.Response> createCheckout(String tier) async {
    final token = await getToken();
    if (token == null) throw Exception('Not signed in');

    final uri = Uri.parse('$_baseUrl/subscribe');
    return _authedRequest((headers) {
      final merged = {
        ...headers,
        'Content-Type': 'application/json',
      };
      return http.post(uri, headers: merged, body: jsonEncode({'tier': tier}));
    });
  }

  static Future<http.Response> cancelSubscription() async {
    final token = await getToken();
    if (token == null) throw Exception('Not signed in');

    final url = Uri.parse('$_baseUrl/cancel-subscription');
    return _authedRequest((headers) => http.delete(url, headers: headers));
  }

  // Quota (DISABLED: always unlimited)
  static Future<QuotaInfo> getQuota() async => const QuotaInfo();
  static Future<int> getQuotaRemaining() async => 2147483647;
}

/// Dio interceptor that:
/// - attaches current auth headers
/// - on 401, refreshes once and retries the original request
class _AuthDioInterceptor extends Interceptor {
  bool _refreshing = false;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    try {
      // Proactively refresh if near expiry
      await AuthService._ensureFreshAccessToken();
      final token = await AuthService.getToken();
      final apiKey = await AuthService.getApiKey();

      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      if (apiKey != null && apiKey.isNotEmpty) {
        options.headers['x-api-key'] = apiKey;
        options.headers['X-API-Key'] = apiKey;
      }
    } catch (_) {
      // Let request proceed; 401 handler will deal with refresh failures
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final status = err.response?.statusCode;

    // Only attempt refresh on 401 and only once per request.
    final alreadyRetried = err.requestOptions.extra['__retried'] == true;

    if (status == 401 && !alreadyRetried) {
      // Prevent multiple simultaneous refresh storms
      if (_refreshing) {
        // Small wait for in-flight refresh; then retry once with new token.
        await Future.delayed(const Duration(milliseconds: 250));
      }

      try {
        _refreshing = true;
        await AuthService.refreshSession();
      } catch (e) {
        _refreshing = false;
        return handler.next(err);
      } finally {
        _refreshing = false;
      }

      try {
        final newReq = err.requestOptions;
        newReq.extra['__retried'] = true;

        final token = await AuthService.getToken();
        final apiKey = await AuthService.getApiKey();

        if (token != null && token.isNotEmpty) {
          newReq.headers['Authorization'] = 'Bearer $token';
        }
        if (apiKey != null && apiKey.isNotEmpty) {
          newReq.headers['x-api-key'] = apiKey;
          newReq.headers['X-API-Key'] = apiKey;
        }

        final response = await AuthService.dio.fetch(newReq);
        return handler.resolve(response);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Dio retry after refresh failed: $e');
        }
        return handler.next(err);
      }
    }

    handler.next(err);
  }
}

/// Dummy for provider UID if you rely on it somewhere else.
Future<String> getProviderUid() async {
  return 'provider_uid_placeholder';
}