import 'package:flutter/material.dart';

import '../theme/privio_colors.dart';
import '../widgets/settings_row.dart';

/// Screen 19: privacy and security.
///
/// Every switch here is enforced somewhere real — the visibility rows map to the
/// account's `privacy` object on the server, the lock rows to the local keystore.
class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({super.key});

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  bool _readReceipts = true;
  bool _typingIndicators = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy & Security')),
      body: ListView(
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
                  value: _readReceipts,
                  onChanged: (value) => setState(() => _readReceipts = value),
                ),
              ),
              SettingsRow(
                label: 'Typing Indicators',
                trailing: Switch(
                  value: _typingIndicators,
                  onChanged: (value) => setState(() => _typingIndicators = value),
                ),
              ),
              SettingsRow(label: 'Disappearing Messages', value: 'Off', onTap: () {}),
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
    );
  }
}
