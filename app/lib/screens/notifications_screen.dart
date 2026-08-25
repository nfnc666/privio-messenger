import 'package:flutter/material.dart';

import '../theme/privio_colors.dart';
import '../widgets/settings_row.dart';

/// Screen 17: notification settings.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final Map<String, bool> _toggles = {
    'Message Notifications': true,
    'Group Notifications': true,
    'Call Notifications': true,
    'In-App Sounds': true,
    'LED Indicator': true,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: PrivioSpacing.xxxl),
        children: [
          SettingsSection(
            children: [
              for (final entry in _toggles.entries)
                SettingsRow(
                  label: entry.key,
                  trailing: Switch(
                    value: entry.value,
                    onChanged: (value) => setState(() => _toggles[entry.key] = value),
                  ),
                ),
            ],
          ),
          SettingsSection(
            caption: 'Preview',
            children: [
              SettingsRow(label: 'Vibrate', value: 'Default', onTap: () {}),
              SettingsRow(label: 'Preview Message', value: 'When Unlocked', onTap: () {}),
            ],
          ),
          const SizedBox(height: PrivioSpacing.lg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xxl),
            child: Text(
              'Push notifications carry no content. Privio wakes the app and the '
              'message is decrypted on this device, so neither Apple nor Google '
              'ever sees who wrote to you.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
