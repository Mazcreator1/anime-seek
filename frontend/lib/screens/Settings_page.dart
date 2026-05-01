// lib/screens/settings_page.dart

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';


class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _versionLabel = '...';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      setState(() {
        _versionLabel = '${info.version} (${info.buildNumber})';
      });
    } catch (_) {
      setState(() {
        _versionLabel = 'Unknown';
      });
    }
  }

  void _openDetail(String title, String body) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _SettingsDetailPage(title: title, body: body),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const aboutText = '''
Anime Seek is an anime discovery app that helps you find anime scenes from images and explore anime metadata, while also offering social features like profiles, posts, likes, follows, and favorites.

Core features may include:
• Scene search (image-based anime scene matching)
• Anime metadata and discovery
• User profiles and community feed
• Favorites, history, and analytics


App Backstory

Anime Seek was created by me (EZ) devrecapz@gmail.com with a simple goal: to build a space where anime fans can connect, share, and celebrate what they love.

Over time, many online platforms have evolved in ways that make meaningful interaction harder to find. I personally felt a growing disconnect from the major streaming platforms which names I will void due to legal reasons — fewer opportunities to share moments, reactions, and excitement with others who genuinely care about anime.

Two years ago, I decided to build something different.

Anime Seek was created to foster community first — a place where fans can post discoveries, relive iconic scenes, share personal stories, and hype each other up. Anime has shaped many of our lives in powerful ways, and this app exists to provide a respectful, welcoming environment where that passion can thrive.

The goal isn’t to replace other platforms — it’s to create a dedicated space designed specifically for anime fans who want connection, conversation, and community.

Welcome to Anime Seek.
''';

    const creditsText = '''
This app uses third-party services for anime data and scene search workflows.

Credits:
• AniList — anime metadata and related information.
• Soruly — inspiration and/or API workflows for anime scene searching / Scene search engine powered by trace.moe (Soruly) — self-hosted
• Apple - 30-second preview courtesy of Apple Music/iTunes

All trademarks and content belong to their respective owners.


       We are not affiliated with AniList or trace.moe

       All anime content belongs to their respective rights holders

       Scene previews are used for identification purposes only

       Users may not download, redistribute, or extract content


All anime titles, images, and related media belong to their respective copyright holders.
Anime Seek does not host or distribute full episodes or video content.
Scene matching is performed using internal vector indexing technology.
Displayed metadata and images are provided via third-party APIs.

''';

    const privacyText = '''
📄 PRIVACY POLICY – Anime Seek

Effective Date: 2/21/2026

Welcome to Anime Seek. This Privacy Policy explains how we collect, use, store, and protect your information when you use the Anime Seek mobile application and related services.

By using the app, you agree to this Privacy Policy.

2. Information We Collect
A. Account Information

When you create an account, we collect:

Username

Email address

B. User-Generated Content

We store content you voluntarily upload, including:

Images (e.g., JPG, GIF)

Posts

Likes

Follows

Favorites

Profile data

C. Payment & Subscription Information

Anime Seek uses Stripe as a third-party payment processor for subscriptions and monetization.

When you purchase a subscription:

Payment information (such as credit/debit card details) is processed directly by Stripe

We do not store full payment card details on our servers

We may store limited billing-related metadata such as:

Stripe customer ID

Subscription status

Subscription tier

Billing period expiration dates

Stripe’s Privacy Policy can be found at:
https://stripe.com/privacy

D. Usage & Analytics Data

We may collect:

Feature usage data (searches, favorites, activity)

Device and app performance logs

IP address (for security and fraud prevention)

E. Third-Party Data Sources

Anime Seek retrieves anime metadata from third-party services, including:

AniList (anime metadata)

Scene search APIs inspired by or integrated with Soruly-style search systems

These third-party services operate under their own privacy policies.

3. How We Use Your Information

We use your information to:

Provide account functionality

Enable subscriptions and billing

Deliver anime search and discovery features

Support social interactions (posts, follows, likes)

Improve performance and stability

Prevent fraud and abuse

Enforce Terms of Service

We do not sell your personal information.

4. Subscription & Billing

If you subscribe to a paid tier:

Payments are securely processed by Stripe.

Subscription management (renewals, cancellations) is handled via Stripe infrastructure.

Refund policies may depend on platform rules (e.g., App Store / Play Store) or Stripe terms.

5. Data Retention

We retain your information as long as your account remains active.

If you delete your account:

Your personal account data may be deleted or anonymized

Uploaded content may be removed

Certain data may remain in backups for a limited period

6. Data Security

We implement reasonable technical safeguards to protect user data. However, no internet-based service can guarantee absolute security.

7. Your Rights

Depending on your jurisdiction, you may have the right to:

Request access to your personal data

Request correction of inaccurate data

Request deletion of your account

Withdraw consent where applicable

To exercise these rights, contact:

📧 devrecapz@gmail.com

8. Children’s Privacy

Anime Seek is not intended for children under 13. We do not knowingly collect personal information from children.

9. International Users

If you access Anime Seek from outside the country where our servers are located, your data may be transferred and processed internationally.

10. Changes to This Policy

We may update this Privacy Policy periodically. Updates will be reflected by revising the Effective Date.

11. Contact

If you have questions about this Privacy Policy:

📧 devrecapz@gmail.com
''';

    const termsText = '''
Terms of Use (Summary)

By using Anime Seek, you agree to the following:

1) Eligibility & Accounts
• You are responsible for your account and activity.
• You must provide accurate information and keep credentials secure.

2) Acceptable Use
You agree not to:
• Upload illegal content or content that violates others’ rights
• Harass, abuse, or impersonate others
• Attempt to reverse engineer, disrupt, or overload the service
• Use automation to scrape or abuse endpoints without permission

3) User Content (Uploads & Posts)
• You retain ownership of your content.
• By uploading, you grant the app a license to host, display, and process your content for app functionality (e.g., showing posts, serving uploaded media).
• You are responsible for ensuring you have rights to upload any content.

4) Third-Party Services
• The app may display information provided by third parties (e.g., AniList).
• Third-party services may have their own terms and policies.

5) Availability & Changes
• Features may change, be removed, or be temporarily unavailable.
• We may update these Terms from time to time.

6) Termination
• We may suspend or terminate accounts that violate these Terms or harm the platform/community.

7) Disclaimers
• The service is provided “as is” without warranties of uninterrupted or error-free operation.
• We are not liable for losses arising from use of the service, to the maximum extent permitted by law.

Support:
• devrecapz@gmail.com
''';

    const supportText = '''
Contact / Support

Email:
devrecapz@gmail.com

If you’re reporting a bug, include:
• What you expected vs what happened
• Steps to reproduce
• Screenshots (if relevant)
• Device model + OS version
''';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        centerTitle: true,
      ),
      body: ListView(
        children: [
          const SizedBox(height: 8),

          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About'),
            subtitle: const Text('What this app is'),
            onTap: () => _openDetail('About', aboutText),
          ),
          const Divider(height: 1),

          ListTile(
            leading: const Icon(Icons.workspace_premium_outlined),
            title: const Text('Credits'),
            subtitle: const Text('Third-party services and acknowledgements'),
            onTap: () => _openDetail('Credits', creditsText),
          ),
          const Divider(height: 1),

          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy Policy'),
            subtitle: const Text('What data we retain and why'),
            onTap: () => _openDetail('Privacy Policy', privacyText),
          ),
          const Divider(height: 1),

          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Terms'),
            subtitle: const Text('Usage rules and disclaimers'),
            onTap: () => _openDetail('Terms', termsText),
          ),
          const Divider(height: 1),

          ListTile(
            leading: const Icon(Icons.support_agent_outlined),
            title: const Text('Contact / Support'),
            subtitle: const Text('devrecapz@gmail.com'),
            onTap: () => _openDetail('Contact / Support', supportText),
          ),

          const SizedBox(height: 16),
          const Divider(height: 1),

          ListTile(
            leading: const Icon(Icons.tag),
            title: const Text('Version'),
            subtitle: Text(_versionLabel),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SettingsDetailPage extends StatelessWidget {
  final String title;
  final String body;

  const _SettingsDetailPage({
    Key? key,
    required this.title,
    required this.body,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: SelectableText(
            body,
            style: const TextStyle(height: 1.35),
          ),
        ),
      ),
    );
  }
}