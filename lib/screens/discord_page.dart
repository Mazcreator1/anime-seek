// lib/screens/discord_page.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class DiscordPage extends StatelessWidget {
  const DiscordPage({Key? key}) : super(key: key);

  static const _inviteUrl = 'https://discord.gg/your‑invite‑code';

  Future<void> _joinDiscord() async {
    final uri = Uri.parse(_inviteUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      throw 'Could not launch $_inviteUrl';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton.icon(
        icon: const Icon(Icons.chat),
        label: const Text('Join our Discord'),
        onPressed: _joinDiscord,
      ),
    );
  }
}
