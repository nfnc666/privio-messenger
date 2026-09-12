import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../l10n/app_localizations.dart';
import '../core/edition.dart';
import '../services/wake_up.dart';
import '../theme/privio_colors.dart';
import '../widgets/privio_back_button.dart';
import '../widgets/settings_row.dart';

/// Screen 17: how this device gets told that something arrived.
///
/// Only the delivery path is Privio's to decide. How a notification then looks
/// — sound, vibration, the lock screen — is the operating system's own setting
/// for this app, and the five switches that used to imply otherwise set nothing
/// at all.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
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
    final text = AppText.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: const PrivioBackButton(),
        title: Text(text.settingsNotifications),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: PrivioSpacing.xxxl),
        children: [
          if (wakeUp.isOffered)
            ListenableBuilder(
              listenable: wakeUp,
              builder: (context, _) => _Delivery(wakeUp: wakeUp),
            ),
          const SizedBox(height: PrivioSpacing.lg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xxl),
            child: Text(
              text.notificationsPushNote,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: PrivioSpacing.lg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xxl),
            child: Text(
              text.notificationsPhoneNote,
              style: Theme.of(context).textTheme.labelSmall,
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
    final text = AppText.of(context);
    final unified = wakeUp.method == WakeUpMethod.unifiedPush;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSection(
          caption: text.notificationsDelivery,
          children: [
            SettingsRow(
              icon: Icons.bolt_outlined,
              label: 'UnifiedPush',
              value: unified ? text.commonOn : null,
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
                    ? text.notificationsDistributorFound(PrivioEdition.current.name)
                    : text.notificationsNoDistributor),
            style: theme.textTheme.labelSmall?.copyWith(
              color: wakeUp.error != null ? PrivioColors.danger : PrivioColors.textTertiary,
            ),
          ),
        ),
      ],
    );
  }
}
