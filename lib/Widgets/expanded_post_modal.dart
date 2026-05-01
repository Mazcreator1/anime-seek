import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../services/auth_service.dart';
import '../screens/profile_page.dart'; // fallback navigation if no callback provided

class ExpandedPostModal extends StatefulWidget {
  final int postId;
  final String username;
  final String avatarUrl;
  final String content;
  final String? imageUrl;

  /// Optional: caller can handle navigation to profile (preferred).
  final void Function(int userId)? onAvatarTap;

  const ExpandedPostModal({
    super.key,
    required this.postId,
    required this.username,
    required this.avatarUrl,
    required this.content,
    this.imageUrl,
    this.onAvatarTap,
  });

  @override
  State<ExpandedPostModal> createState() => _ExpandedPostModalState();
}

class _ExpandedPostModalState extends State<ExpandedPostModal> {
  List<dynamic> comments = [];
  final TextEditingController _commentController = TextEditingController();
  final Map<int, bool> _showReplyBox = {};
  final Map<int, TextEditingController> _replyCtrls = {};

  // NEW: current user id for owner checks
  int? _currentUserId;

  String _fullAvatarUrl(String url) {
    if (url.startsWith('/uploads')) {
      return 'https://anime-seek.com$url';
    }
    return url;
  }

  int _toIntId(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  void _openProfile(int userId) {
    if (userId <= 0) return;
    // Close the bottom sheet first, then navigate.
    Navigator.of(context).pop();
    if (widget.onAvatarTap != null) {
      widget.onAvatarTap!(userId);
    } else {
      // Fallback: navigate directly if no callback is provided.
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ProfilePage(userId: userId)),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final me = await AuthService.getCurrentUser();
      setState(() {
        _currentUserId = _toIntId(me['id']);
      });
    } catch (_) {}
    await _fetchComments();
  }

  @override
  void dispose() {
    _commentController.dispose();
    for (final c in _replyCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _fetchComments() async {
    final headers = await AuthService.authHeaders;
    final res = await http.get(
      Uri.parse('https://anime-seek.com/fastapi/posts/${widget.postId}/comments'),
      headers: headers,
    );

    if (res.statusCode == 200) {
      setState(() {
        comments = json.decode(res.body);
        _showReplyBox.clear();
        _replyCtrls.clear();
      });
    }
  }

  Future<void> _submitComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    final headers = await AuthService.authHeaders; // has Bearer token
    headers['Content-Type'] = 'application/json';

    final res = await http.post(
      Uri.parse('https://anime-seek.com/fastapi/posts/${widget.postId}/comments-json'),
      headers: headers,
      body: json.encode({"content": text}),
    );

    if (res.statusCode == 200) {
      _commentController.clear();
      _fetchComments();
    } else {
      debugPrint('Failed to comment: ${res.statusCode} ${res.body}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to comment: ${res.statusCode}")),
      );
    }
  }

  Future<List<dynamic>> _fetchReplies(int commentId) async {
    final headers = await AuthService.authHeaders;
    final uri = Uri.parse('https://anime-seek.com/fastapi/comments/$commentId/replies');
    final res = await http.get(uri, headers: headers);
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as List<dynamic>;
    }
    return [];
  }

  Future<void> _postReply(int commentId, String replyText) async {
    if (replyText.trim().isEmpty) return;

    final headers = await AuthService.authHeaders;
    final uri = Uri.parse('https://anime-seek.com/fastapi/comments/$commentId/replies');

    var request = http.MultipartRequest('POST', uri);
    request.headers.addAll(headers);
    request.fields['content'] = replyText.trim();

    final res = await request.send();
    if (res.statusCode == 200 || res.statusCode == 201) {
      _fetchComments();
    } else {
      debugPrint('Failed to post reply: ${res.statusCode}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to post reply (${res.statusCode})')),
      );
    }
  }

  // -------- NEW: edit/delete comments --------

  Future<void> _editCommentDialog(int commentId, String initial) async {
    final ctrl = TextEditingController(text: initial);
    final newText = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit Comment'),
        content: TextField(
          controller: ctrl,
          maxLines: null,
          decoration: const InputDecoration(hintText: 'Update your comment'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (newText == null || newText.isEmpty || newText == initial) return;
    await _saveEditComment(commentId, newText);
  }

  Future<void> _saveEditComment(int commentId, String content) async {
    try {
      final headers = await AuthService.authHeaders;
      final uri = Uri.parse('https://anime-seek.com/fastapi/comments/$commentId');
      final res = await http.patch(
        uri,
        headers: {...headers, 'Content-Type': 'application/json'},
        body: json.encode({'content': content}),
      );
      if (res.statusCode == 200) {
        await _fetchComments();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Comment updated')));
      } else {
        throw Exception('HTTP ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('Edit comment failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to update comment')));
    }
  }

  Future<void> _deleteComment(int commentId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Comment'),
        content: const Text('Are you sure you want to delete this comment? Replies will be removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final headers = await AuthService.authHeaders;
      final uri = Uri.parse('https://anime-seek.com/fastapi/comments/$commentId');
      final res = await http.delete(uri, headers: headers);
      if (res.statusCode == 200) {
        await _fetchComments();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Comment deleted')));
      } else {
        throw Exception('HTTP ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('Delete comment failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to delete comment')));
    }
  }

  // -------- NEW: edit/delete replies --------

  Future<void> _editReplyDialog(int replyId, String initial, int commentIdForRefresh) async {
    final ctrl = TextEditingController(text: initial);
    final newText = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit Reply'),
        content: TextField(
          controller: ctrl,
          maxLines: null,
          decoration: const InputDecoration(hintText: 'Update your reply'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (newText == null || newText.isEmpty || newText == initial) return;
    await _saveEditReply(replyId, newText, commentIdForRefresh);
  }

  Future<void> _saveEditReply(int replyId, String content, int commentIdForRefresh) async {
    try {
      final headers = await AuthService.authHeaders;
      final uri = Uri.parse('https://anime-seek.com/fastapi/replies/$replyId');
      final res = await http.patch(
        uri,
        headers: {...headers, 'Content-Type': 'application/json'},
        body: json.encode({'content': content}),
      );
      if (res.statusCode == 200) {
        setState(() {}); // triggers FutureBuilder to refetch
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reply updated')));
      } else {
        throw Exception('HTTP ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('Edit reply failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to update reply')));
    }
  }

  Future<void> _deleteReply(int replyId, int commentIdForRefresh) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Reply'),
        content: const Text('Are you sure you want to delete this reply?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final headers = await AuthService.authHeaders;
      final uri = Uri.parse('https://anime-seek.com/fastapi/replies/$replyId');
      final res = await http.delete(uri, headers: headers);
      if (res.statusCode == 200) {
        setState(() {}); // refresh replies FutureBuilder
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reply deleted')));
      } else {
        throw Exception('HTTP ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('Delete reply failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to delete reply')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (_, scrollController) => Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Post header
            Row(
              children: [
                CircleAvatar(
                  backgroundImage: widget.avatarUrl.isNotEmpty
                      ? NetworkImage(_fullAvatarUrl(widget.avatarUrl))
                      : null,
                  child: widget.avatarUrl.isEmpty
                      ? const Icon(Icons.person)
                      : null,
                ),
                const SizedBox(width: 8),
                Text(widget.username,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Post content
            Text(widget.content),

            // Post image (optional)
            if (widget.imageUrl != null && widget.imageUrl!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Image.network(
                widget.imageUrl!.startsWith('http')
                    ? widget.imageUrl!
                    : 'https://anime-seek.com${widget.imageUrl!}',
                fit: BoxFit.cover,
              ),
            ],

            const Divider(),

            // Comments & replies
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                itemCount: comments.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final c = comments[i] as Map<String, dynamic>;
                  final user = (c['user'] ?? {}) as Map<String, dynamic>;
                  final uid = _toIntId(user['id']);
                  final displayName = (user['display_name'] ?? 'User').toString();
                  final avatarUrl = _fullAvatarUrl((user['avatar_url'] ?? '').toString());
                  final content = (c['content'] ?? '').toString();
                  final commentId = _toIntId(c['id']);

                  _showReplyBox.putIfAbsent(commentId, () => false);
                  _replyCtrls.putIfAbsent(commentId, () => TextEditingController());

                  return KeyedSubtree(
                    key: ValueKey('post_${widget.postId}_comment_$commentId'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Comment row
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              onTap: () => _openProfile(uid),
                              child: CircleAvatar(
                                radius: 16,
                                backgroundImage: (avatarUrl.isNotEmpty)
                                    ? NetworkImage(avatarUrl)
                                    : null,
                                child: avatarUrl.isEmpty
                                    ? const Icon(Icons.person, size: 16)
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: () => _openProfile(uid),
                                          child: Text(
                                            displayName,
                                            style: const TextStyle(fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ),
                                      if (_currentUserId != null && _currentUserId == uid)
                                        PopupMenuButton<String>(
                                          onSelected: (v) {
                                            if (v == 'edit') {
                                              _editCommentDialog(commentId, content);
                                            } else if (v == 'delete') {
                                              _deleteComment(commentId);
                                            }
                                          },
                                          itemBuilder: (_) => const [
                                            PopupMenuItem(
                                              value: 'edit',
                                              child: Text('Edit'),
                                            ),
                                            PopupMenuItem(
                                              value: 'delete',
                                              child: Text('Delete'),
                                            ),
                                          ],
                                        ),
                                    ],
                                  ),
                                  Text(content),
                                  TextButton(
                                    onPressed: () {
                                      setState(() {
                                        _showReplyBox[commentId] =
                                        !(_showReplyBox[commentId] ?? false);
                                      });
                                    },
                                    style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      minimumSize: const Size(0, 0),
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: Text(
                                      (_showReplyBox[commentId] ?? false) ? 'Cancel' : 'Reply',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        // Reply box
                        if (_showReplyBox[commentId] ?? false)
                          Padding(
                            padding: const EdgeInsets.only(left: 40.0, top: 6.0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _replyCtrls[commentId],
                                    decoration: const InputDecoration(
                                      hintText: 'Write a reply...',
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.send),
                                  onPressed: () async {
                                    final text = _replyCtrls[commentId]!.text.trim();
                                    if (text.isEmpty) return;
                                    await _postReply(commentId, text);
                                    _replyCtrls[commentId]!.clear();
                                  },
                                ),
                              ],
                            ),
                          ),

                        // Replies list
                        Padding(
                          padding: const EdgeInsets.only(left: 40.0, top: 6.0),
                          child: FutureBuilder<List<dynamic>>(
                            future: _fetchReplies(commentId),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState == ConnectionState.waiting) {
                                return const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(strokeWidth: 1.5),
                                );
                              }
                              final replies = snapshot.data ?? [];
                              if (replies.isEmpty) {
                                return const SizedBox.shrink();
                              }
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: replies.map((r) {
                                  final rUser = (r['user'] ?? {}) as Map<String, dynamic>;
                                  final rUid = _toIntId(rUser['id']);
                                  final rName = (rUser['display_name'] ?? 'User').toString();
                                  final rAvatar =
                                  _fullAvatarUrl((rUser['avatar_url'] ?? '').toString());
                                  final rText = (r['content'] ?? '').toString();
                                  final rId = _toIntId(r['id']);

                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8.0),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        GestureDetector(
                                          onTap: () => _openProfile(rUid),
                                          child: CircleAvatar(
                                            radius: 14,
                                            backgroundImage: (rAvatar.isNotEmpty)
                                                ? NetworkImage(rAvatar)
                                                : null,
                                            child: rAvatar.isEmpty
                                                ? const Icon(Icons.person, size: 14)
                                                : null,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: GestureDetector(
                                                      onTap: () => _openProfile(rUid),
                                                      child: Text(
                                                        rName,
                                                        style: const TextStyle(
                                                            fontWeight: FontWeight.bold),
                                                      ),
                                                    ),
                                                  ),
                                                  if (_currentUserId != null &&
                                                      _currentUserId == rUid)
                                                    PopupMenuButton<String>(
                                                      onSelected: (v) {
                                                        if (v == 'edit') {
                                                          _editReplyDialog(rId, rText, commentId);
                                                        } else if (v == 'delete') {
                                                          _deleteReply(rId, commentId);
                                                        }
                                                      },
                                                      itemBuilder: (_) => const [
                                                        PopupMenuItem(
                                                          value: 'edit',
                                                          child: Text('Edit'),
                                                        ),
                                                        PopupMenuItem(
                                                          value: 'delete',
                                                          child: Text('Delete'),
                                                        ),
                                                      ],
                                                    ),
                                                ],
                                              ),
                                              Text(rText),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Comment input
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    decoration: const InputDecoration(
                      hintText: "Write a comment...",
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _submitComment,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
