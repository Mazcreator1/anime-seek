// lib/services/api.dart

import 'dart:convert';
import 'package:http/http.dart' as http;

class Api {
  static const String baseUrl = "https://anime-seek.com/fastapi";

  static Map<String, String> _headers() => {
    "Content-Type": "application/json",
    // TODO: replace with real token when auth wiring is ready
    "Authorization": "Bearer YOUR_TOKEN",
  };

  static Future<dynamic> get(String path) async {
    final res = await http.get(
      Uri.parse("$baseUrl$path"),
      headers: _headers(),
    );

    if (res.statusCode >= 400) {
      throw Exception(res.body);
    }

    return jsonDecode(res.body);
  }

  static Future<void> post(
      String path,
      Map<String, dynamic> body,
      ) async {
    final res = await http.post(
      Uri.parse("$baseUrl$path"),
      headers: _headers(),
      body: jsonEncode(body),
    );

    if (res.statusCode >= 400) {
      throw Exception(res.body);
    }
  }
}
