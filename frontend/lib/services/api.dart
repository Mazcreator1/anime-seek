// lib/services/api.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_service.dart';

class Api {
  static Future<dynamic> get(String path) async {
    final api = ApiService.instance;

    final res = await http.get(
      Uri.parse('${api.baseUrl}$path'),
      headers: {
        ...api.headers,
        'Content-Type': 'application/json',
      },
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
    final api = ApiService.instance;

    final res = await http.post(
      Uri.parse('${api.baseUrl}$path'),
      headers: {
        ...api.headers,
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );

    if (res.statusCode >= 400) {
      throw Exception(res.body);
    }
  }
}
