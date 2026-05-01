import 'package:flutter/material.dart';
import 'package:anime_finder/services/api_service.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  bool loading = true;
  List<dynamic> items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // ✅ key fix: dynamic
      final dynamic res = await ApiService.instance.getJson('/notifications');

      if (!mounted) return;
      setState(() {
        items = (res is List) ? List<dynamic>.from(res) : <dynamic>[];
        loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Notifications")),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? const Center(child: Text("No notifications yet"))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final n = items[i];
                      final title = (n is Map && n['title'] != null)
                          ? n['title'].toString()
                          : 'Notification';
                      final body = (n is Map && n['body'] != null)
                          ? n['body'].toString()
                          : (n is Map && n['message'] != null)
                              ? n['message'].toString()
                              : '';
                      return ListTile(
                        title: Text(title),
                        subtitle: body.isEmpty ? null : Text(body),
                      );
                    },
                  ),
                ),
    );
  }
}
