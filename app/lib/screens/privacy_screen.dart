import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../theme/privio_colors.dart';
import '../widgets/settings_row.dart';

/// Privacy and security.
///
/// The two messaging switches are real: they are read from the account and
/// written back to it, and turning one off stops this device sending that thing
/// — and stops it showing other people's, because a setting that takes without
/// giving would be a different feature wearing this one's name.
class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({super.key});

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => PrivioScope.of(context).conversations.loadPrivacy(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final conversations = PrivioScope.of(context).conversations;
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy & Security')),
      body: ListenableBuilder(
        listenable: conversations,
        builder: (context, _) => ListView(
        padding: const EdgeInsets.only(bottom: PrivioSpacing.xxxl),
        children: [
          SettingsSection(
            caption: 'Who can see',
            children: [
              SettingsRow(label: 'Last Seen', value: 'My Contacts', onTap: () {}),
              SettingsRow(label: 'Profile Photo', value: 'My Contacts', onTap: () {}),
              SettingsRow(label: 'About', value: 'My Contacts', onTap: () {}),
            ],
          ),
          SettingsSection(
            caption: 'Messaging',
            children: [
              SettingsRow(
                label: 'Read Receipts',
                trailing: Switch(
                  value: conversations.readReceiptsEnabled,
                  onChanged: (value) => conversations.setReadReceipts(value),
                ),
              ),
              SettingsRow(
                label: 'Typing Indicators',
                trailing: Switch(
                  value: conversations.typingIndicatorsEnabled,
                  onChanged: (value) => conversations.setTypingIndicators(value),
                ),
              ),
              // Per chat rather than global: a timer that applied to every
              // conversation at once would be a setting nobody could use.
              const SettingsRow(
                label: 'Disappearing Messages',
                value: 'Per chat',
              ),
            ],
          ),
          SettingsSection(
            caption: 'Access',
            children: [
              SettingsRow(label: 'Screen Lock', value: 'PIN', onTap: () {}),
              SettingsRow(label: 'Two-Factor Authentication', value: 'On', onTap: () {}),
              SettingsRow(label: 'Change Password', onTap: () {}),
              SettingsRow(label: 'Blocked Users', value: '3', onTap: () {}),
            ],
          ),
          const SizedBox(height: PrivioSpacing.xl),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xxl),
            child: Text(
              'Read receipts and typing indicators are mutual: turning them off '
              'also stops you from seeing other people’s.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          ],
        ),
      ),
    );
  }
}
