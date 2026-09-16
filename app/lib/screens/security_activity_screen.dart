import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../l10n/app_localizations.dart';
import '../l10n/chat_text.dart' show formatEventTime;
import '../l10n/security_event_text.dart';
import '../models/security_event.dart';
import '../theme/privio_colors.dart';
import '../widgets/privio_back_button.dart';

/// What has happened to this account's security, on this device.
///
/// Two things this screen is not, both of them deliberate and both written on
/// the screen itself rather than only here:
///
/// * **It is not a server-side audit log.** Nothing on this list has ever left
///   the phone. A log the server kept would be a record of when each account's
///   owner changed a password, linked a number or verified somebody — held by
///   the one party the rest of Privio is built not to trust. The cost is that
///   an event another of your devices saw appears there and not here, and the
///   note says so instead of leaving somebody to assume the list is complete.
/// * **It records no addresses and no location.** "Signed in from Zurich, IP
///   1.2.3.4" is the shape every other messenger's security log takes, and it
///   is a movement history that happens to be filed under security.
class SecurityActivityScreen extends StatefulWidget {
  const SecurityActivityScreen({super.key});

  @override
  State<SecurityActivityScreen> createState() => _SecurityActivityScreenState();
}

class _SecurityActivityScreenState extends State<SecurityActivityScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = PrivioScope.of(context);
      final account = state.accountId;
      if (account != null) state.securityEvents.load(account);
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final theme = Theme.of(context);
    final events = PrivioScope.of(context).securityEvents;

    return Scaffold(
      backgroundColor: PrivioColors.background,
      appBar: AppBar(
        backgroundColor: PrivioColors.background,
        leading: const PrivioBackButton(),
        title: Text(text.securityActivityTitle),
      ),
      body: ListenableBuilder(
        listenable: events,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.only(bottom: PrivioSpacing.xxxl),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                PrivioSpacing.gutter,
                PrivioSpacing.md,
                PrivioSpacing.gutter,
                PrivioSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text.securityActivityNote,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: PrivioColors.textSecondary),
                  ),
                  const SizedBox(height: PrivioSpacing.sm),
                  Text(
                    text.securityActivityNothingSensitive,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: PrivioColors.textTertiary),
                  ),
                ],
              ),
            ),
            // Nothing recorded, and nothing claimed either way, until the log
            // has actually answered.
            if (events.loaded && events.events.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.gutter),
                child: Text(
                  text.securityActivityEmpty,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: PrivioColors.textSecondary),
                ),
              ),
            for (final event in events.events) _EventRow(event: event),
          ],
        ),
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});

  final SecurityEvent event;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final theme = Theme.of(context);
    final warning = event.isWarning;

    return ListTile(
      leading: Icon(
        warning ? Icons.gpp_maybe_outlined : _iconFor(event.kind),
        color: warning ? PrivioColors.danger : PrivioColors.textSecondary,
      ),
      title: Text(
        describeSecurityEvent(text, event),
        style: theme.textTheme.bodyMedium?.copyWith(
          color: warning ? PrivioColors.danger : null,
        ),
      ),
      subtitle: Text(
        formatEventTime(text, event.at),
        style: theme.textTheme.bodySmall?.copyWith(color: PrivioColors.textTertiary),
      ),
    );
  }

  static IconData _iconFor(SecurityEventKind kind) => switch (kind) {
        SecurityEventKind.deviceAdded => Icons.phonelink_outlined,
        SecurityEventKind.deviceRemoved => Icons.phonelink_erase_outlined,
        SecurityEventKind.passwordChanged => Icons.password_rounded,
        SecurityEventKind.twoFactorEnabled ||
        SecurityEventKind.twoFactorDisabled =>
          Icons.shield_outlined,
        SecurityEventKind.backupRestored => Icons.restore_rounded,
        SecurityEventKind.phoneLinked || SecurityEventKind.phoneRemoved => Icons.phone_outlined,
        SecurityEventKind.proxyEnabled || SecurityEventKind.proxyDisabled => Icons.lan_outlined,
        SecurityEventKind.contactKeyChanged => Icons.gpp_maybe_outlined,
        SecurityEventKind.contactVerified => Icons.verified_user_outlined,
        SecurityEventKind.contactVerificationCleared => Icons.remove_moderator_outlined,
        SecurityEventKind.screenLockChanged => Icons.lock_outline_rounded,
        SecurityEventKind.duressCodeChanged => Icons.warning_amber_rounded,
      };
}
