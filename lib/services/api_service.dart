// lib/services/api_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/post.dart';

class ApiService {
  /// Host only (no trailing slash)
  static const String defaultBaseUrl = 'http://anime-seek.com';

  /// If your FastAPI is mounted at /fastapi (e.g. /fastapi/docs), keep this.
  /// If your FastAPI is mounted at root (e.g. /docs), set to '' in configure().
  static const String defaultApiPrefix = '/fastapi';

  final String baseUrl;
  final String apiPrefix;
  final String authToken;

  ApiService(this.baseUrl, this.authToken, {this.apiPrefix = defaultApiPrefix});

  // ---- singleton wiring
  static ApiService? _instance;

  static void configure({
    String baseUrl = defaultBaseUrl,
    String apiPrefix = defaultApiPrefix,
    required String authToken,
  }) {
    _instance = ApiService(baseUrl, authToken, apiPrefix: apiPrefix);
  }

  static ApiService get instance {
    final i = _instance;
    if (i == null) {
      throw StateError(
        'ApiService.instance is not configured. '
            'Call ApiService.configure(...) at app startup.',
      );
    }
    return i;
  }
  // ----------------------

  Map<String, String> get headers => {
    'Authorization': 'Bearer $authToken',
    'Accept': 'application/json',
  };

  Uri _uri(String path, {required bool useApiPrefix}) {
    final p = path.startsWith('/') ? path : '/$path';
    final prefix = (useApiPrefix && apiPrefix.isNotEmpty) ? apiPrefix : '';
    return Uri.parse('$baseUrl$prefix$p');
  }

  // ============================================================
  // JSON helpers for FastAPI (/markets, /admin/markets, /me/wallet, etc.)
  // ============================================================
  Future<Map<String, dynamic>> getJson(String path) async {
    final r = await http.get(_uri(path, useApiPrefix: true), headers: headers);
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception(jsonDecodeSafe(r.body) ?? r.body);
    }
    final decoded = jsonDecode(r.body);
    return (decoded as Map).cast<String, dynamic>();
  }

  Future<List<dynamic>> getJsonList(String path) async {
    final r = await http.get(_uri(path, useApiPrefix: true), headers: headers);
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception(jsonDecodeSafe(r.body) ?? r.body);
    }
    final decoded = jsonDecode(r.body);
    return decoded as List<dynamic>;
  }

  Future<Map<String, dynamic>> postJson(String path, Map<String, dynamic> body) async {
    final r = await http.post(
      _uri(path, useApiPrefix: true),
      headers: {...headers, 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception(jsonDecodeSafe(r.body) ?? r.body);
    }
    final decoded = jsonDecode(r.body);
    return (decoded as Map).cast<String, dynamic>();
  }

  static String? jsonDecodeSafe(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map && j['detail'] != null) return j['detail'].toString();
      return body;
    } catch (_) {
      return null;
    }
  }

  // ============================================================
  // Existing Feed methods (no /fastapi prefix)
  // ============================================================
  Future<List<Post>> fetchGlobalFeed() async {
    final r = await http.get(_uri('/feed/global', useApiPrefix: false), headers: headers);
    if (r.statusCode != 200) {
      throw Exception('Feed error ${r.statusCode}: ${r.body}');
    }
    final List<dynamic> arr = jsonDecode(r.body) as List<dynamic>;
    return arr.map((e) => Post.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Post> voteInPoll({required int postId, required List<int> optionIds}) async {
    final uri = _uri('/posts/$postId/poll/vote', useApiPrefix: false);
    final r = await http.post(
      uri,
      headers: {...headers, 'Content-Type': 'application/json'},
      body: jsonEncode({'option_ids': optionIds}),
    );
    if (r.statusCode != 200) {
      throw Exception('Vote error ${r.statusCode}: ${r.body}');
    }
    final Map<String, dynamic> j = jsonDecode(r.body);
    return Post.fromJson(j['post'] as Map<String, dynamic>);
  }

  Future<Post> createPoll({
    required String question,
    required List<String> options,
    bool multiple = false,
    bool allowChange = true,
    DateTime? closesAt,
  }) async {
    final uri = _uri('/posts', useApiPrefix: false);
    final body = {
      'type': 'poll',
      'poll': {
        'question': question,
        'options': options,
        'multiple': multiple,
        'allow_change': allowChange,
        if (closesAt != null) 'closes_at': closesAt.toUtc().toIso8601String(),
      },
      'text': question,
    };
    final r = await http.post(
      uri,
      headers: {...headers, 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (r.statusCode != 200) {
      throw Exception('Create poll error ${r.statusCode}: ${r.body}');
    }
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return Post.fromJson(j['post'] as Map<String, dynamic>);
  }
}
