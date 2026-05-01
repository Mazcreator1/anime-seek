import 'package:flutter/material.dart';
import 'package:anime_finder/services/auth_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({Key? key}) : super(key: key);

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  List<dynamic> notifications = [];
  bool isLoading = false;

  Future<void> fetchNotifications() async {
    setState(() => isLoading = true);
    final headers = await AuthService.authHeaders;
    final resp = await http.get(
      Uri.parse('https://anime-seek.com/fastapi/notifications'),
      headers: headers,
    );
    if (resp.statusCode == 200) {
      notifications = json.decode(resp.body);
    }
    setState(() => isLoading = false);
  }

  Future<void> markAsRead(int notificationId) async {
    final headers = await AuthService.authHeaders;
    await http.post(
      Uri.parse('https://anime-seek.com/fastapi/notifications/$notificationId/mark-read'),
      headers: headers,
    );
    fetchNotifications();
  }

  @override
  void initState() {
    super.initState();
    fetchNotifications();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Notifications")),
      body: RefreshIndicator(
        onRefresh: fetchNotifications,
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : notifications.isEmpty
            ? const Center(child: Text("No notifications"))
            : ListView.builder(
          itemCount: notifications.length,
          itemBuilder: (ctx, i) {
            final notif = notifications[i];
            return Dismissible(
              key: Key(notif['id'].toString()),
              direction: DismissDirection.endToStart,
              background: Container(
                color: Colors.green,
                alignment: Alignment.centerRight,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Icon(Icons.done, color: Colors.white),
                ),
              ),
              onDismissed: (_) => markAsRead(notif['id']),
              child: ListTile(
                leading: Icon(Icons.notifications),
                title: Text(notif['message'] ?? ""),
                subtitle: Text(notif['created_at'] ?? ""),
                trailing: notif['is_read'] == true ? null : const Icon(Icons.circle, color: Colors.red, size: 12),
              ),
            );
          },
        ),
      ),
    );
  }
}
