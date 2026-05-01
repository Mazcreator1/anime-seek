import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TokenStore {
  static const _kToken = 'auth_token';

  static Future<void> set(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kToken, token);
  }

  static Future<String?> get() async {
    final prefs = await SharedPreferences.getInstance();
    final t = prefs.getString(_kToken);
    if (t == null || t.trim().isEmpty) return null;
    return t.trim();
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kToken);
  }
}

class CommentsPage {
  CommentsPage({
    required this.items,
    required this.totalCount,
    required this.hasMore,
    required this.nextBeforeId,
    required this.commentsLocked,
    required this.lockAfterAt,
  });

  final List<Map<String, dynamic>> items;
  final int totalCount;
  final bool hasMore;
  final int? nextBeforeId;
  final bool commentsLocked;
  final String lockAfterAt;

  factory CommentsPage.fromJson(Map<String, dynamic> j) => CommentsPage(
        items: List<Map<String, dynamic>>.from(j['items'] ?? const []),
        totalCount: j['total_count'] ?? 0,
        hasMore: j['has_more'] ?? false,
        nextBeforeId: j['next_before_id'],
        commentsLocked: j['comments_locked'] ?? false,
        lockAfterAt: j['lock_after_at'] ?? '',
      );
}

class ApiClient {
  ApiClient({required String baseUrl})
      : _dio = Dio(BaseOptions(baseUrl: baseUrl)) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await TokenStore.get();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          } else {
            options.headers.remove('Authorization');
          }
          handler.next(options);
        },
      ),
    );
  }

  final Dio _dio;

  Future<CommentsPage> fetchComments({
    required int postId,
    int? beforeId,
    int limit = 50,
  }) async {
    final res = await _dio.get(
      '/posts/$postId/comments',
      queryParameters: {
        'limit': limit,
        if (beforeId != null) 'before_id': beforeId,
      },
    );
    return CommentsPage.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> deleteCommentItem(int itemId) async {
    try {
      await _dio.delete('/comment-items/$itemId');
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final data = e.response?.data;

      if (code == 403 && data is Map && data['detail'] is Map) {
        throw Exception('Not allowed: only the item author or the post author can delete.');
      }
      if (code == 404) {
        throw Exception('Item not found (it may have been deleted).');
      }
      throw Exception('Delete failed ($code): $data');
    }
  }
}
