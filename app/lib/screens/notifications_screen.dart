import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/edition.dart';
import '../services/wake_up.dart';
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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) PrivioScope.of(context).wakeUp.refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final wakeUp = PrivioScope.of(context).wakeUp;

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: PrivioSpacing.xxxl),
        children: [
          if (wakeUp.isOffered)
            ListenableBuilder(
              listenable: wakeUp,
              builder: (context, _) => _Delivery(wakeUp: wakeUp),
            ),
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
              'A push carries no content — only a wake-up. The message is fetched '
              'and decrypted on this device, so nobody in the middle, including '
              'whoever runs the service that woke it, sees who wrote to you.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// Which wake-up path this device uses.
///
/// Only shown where there is a choice to make. The store builds are woken by
/// the platform's own service and have nothing to pick.
class _Delivery extends StatelessWidget {
  const _Delivery({required this.wakeUp});

  final WakeUpController wakeUp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unified = wakeUp.method == WakeUpMethod.unifiedPush;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSection(
          caption: 'Delivery',
          children: [
            SettingsRow(
              icon: Icons.bolt_outlined,
              label: 'UnifiedPush',
              value: unified ? 'On' : null,
              trailing: Switch(
                value: unified,
                onChanged: wakeUp.busy
                    ? null
                    : (value) => value ? wakeUp.useUnifiedPush() : wakeUp.useSocketOnly(),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            PrivioSpacing.xxl,
            PrivioSpacing.sm,
            PrivioSpacing.xxl,
            PrivioSpacing.lg,
          ),
          child: Text(
            wakeUp.error ??
                (wakeUp.distributorAvailable
                    ? 'A distributor app on this phone holds one connection for '
                        'every app that uses it, and forwards a contentless ping. '
                        '${PrivioEdition.current.name} needs no Google service for it, '
                        'and you can run the distributor yourself.'
                    : 'No distributor found. Install one — ntfy, for example — to be '
                        'woken while Privio is closed. Without one, messages arrive '
                        'while the app is open.'),
            style: theme.textTheme.labelSmall?.copyWith(
              color: wakeUp.error != null ? PrivioColors.danger : PrivioColors.textTertiary,
            ),
          ),
        ),
      ],
    );
  }
}
