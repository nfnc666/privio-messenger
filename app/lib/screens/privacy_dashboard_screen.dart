import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../l10n/app_localizations.dart';
import '../l10n/chat_text.dart' show formatEventTime;
import '../network/proxy_controller.dart';
import '../services/backup_service.dart';
import '../theme/accent.dart';
import '../theme/privio_colors.dart';
import '../widgets/privio_back_button.dart';
import '../widgets/settings_row.dart';

/// Where this account actually stands, in one screen.
///
/// **Every value here is read from something.** The two-factor row is what the
/// server last said, the device count is the list the Devices screen shows, the
/// verified-contacts count is recomputed against the keys pinned right now, and
/// a value that has not arrived yet is drawn as "—" rather than guessed. A
/// dashboard that says "Protected" because someone typed "Protected" into it is
/// worse than no dashboard: it is a reassurance with nothing behind it, on the
/// one screen people open when they are worried.
///
/// Two rows state architecture rather than settings — messages and calls are
/// end-to-end encrypted because of how Privio is built, not because of a switch.
/// Both carry the exception rather than a clean tick: bot conversations are not
/// encrypted (`docs/bots.md`), and a call is only as good as the safety number
/// behind it.
class PrivacyDashboardScreen extends StatefulWidget {
  const PrivacyDashboardScreen({super.key});

  @override
  State<PrivacyDashboardScreen> createState() => _PrivacyDashboardScreenState();
}

class _PrivacyDashboardScreenState extends State<PrivacyDashboardScreen> {
  int? _verifiedContacts;
  RemoteBackup? _remoteBackup;
  bool _backupAsked = false;
  DateTime? _lastBackupAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_load()));
  }

  Future<void> _load() async {
    if (!mounted) return;
    final state = PrivioScope.of(context);
    final account = state.accountId;

    // Everything the settings screens already load, loaded here too: this is
    // often the first security screen somebody opens, and it must not show a
    // row of dashes because another screen happened not to have been visited.
    unawaited(state.security.load());
    unawaited(state.security.loadDevices());
    if (account != null && state.phone.accountId != account) {
      unawaited(state.phone.load(account));
    }

    final verified = await state.services.crypto.verifiedContactCount();
    if (!mounted) return;
    setState(() => _verifiedContacts = verified);

    final last = await state.services.backup.lastBackupAt();
    // A dashboard must not fall over because one row's source is unreachable.
    // A backup that cannot be asked about reads as "none on the server", which
    // is the cautious answer: it never draws protection that may not be there.
    RemoteBackup? remote;
    try {
      remote = await state.services.backup.remote();
    } on Object {
      remote = null;
    }
    if (!mounted) return;
    setState(() {
      _lastBackupAt = last;
      _remoteBackup = remote;
      _backupAsked = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final state = PrivioScope.of(context);

    return Scaffold(
      backgroundColor: PrivioColors.background,
      appBar: AppBar(
        backgroundColor: PrivioColors.background,
        leading: const PrivioBackButton(),
        title: Text(text.privacyDashboardTitle),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([
          state.security,
          state.phone,
          state.conversations,
          ProxyController.instance,
        ]),
        builder: (context, _) => ListView(
          padding: const EdgeInsets.only(bottom: PrivioSpacing.xxxl),
          children: [
            SettingsSection(
              caption: text.privacyDashboardContent,
              children: [
                _Row(
                  label: text.privacyDashboardMessages,
                  value: text.privacyDashboardEndToEnd,
                  tone: _Tone.good,
                  // Not a clean tick. The one exception is real and is on the
                  // row rather than in a footnote nobody reads.
                  subtitle: text.privacyDashboardBotsExcepted,
                ),
                _Row(
                  label: text.privacyDashboardCalls,
                  value: text.privacyDashboardEndToEnd,
                  tone: _Tone.good,
                  subtitle: state.services.calls.requireVerified
                      ? text.privacyDashboardVerifiedCallsOnly
                      : text.privacyDashboardAnyCaller,
                ),
              ],
            ),
            SettingsSection(
              caption: text.privacyDashboardAccount,
              children: [
                _Row(
                  label: text.privacyTwoFactor,
                  // Null means the server has not answered. A dash, not "Off":
                  // telling somebody their second factor is off when it is on
                  // is the exact failure this screen replaced.
                  value: switch (state.security.twoFactorEnabled) {
                    true => text.commonOn,
                    false => text.commonOff,
                    null => null,
                  },
                  tone: switch (state.security.twoFactorEnabled) {
                    true => _Tone.good,
                    false => _Tone.warn,
                    null => _Tone.unknown,
                  },
                ),
                _Row(
                  label: text.privacyDashboardDevices,
                  value: state.security.devices?.length.toString(),
                  tone: state.security.devices == null ? _Tone.unknown : _Tone.neutral,
                ),
                _Row(
                  label: text.privacyDashboardBackup,
                  value: _backupValue(text),
                  tone: !_backupAsked
                      ? _Tone.unknown
                      : _remoteBackup == null
                          ? _Tone.neutral
                          : _Tone.good,
                  subtitle: _backupSubtitle(text),
                ),
              ],
            ),
            SettingsSection(
              caption: text.privacyDashboardFinding,
              children: [
                _Row(
                  label: text.privacyDashboardPhone,
                  value: state.phone.loaded
                      ? (state.phone.link.linked
                          ? (state.phone.link.hint ?? text.privacyDashboardLinked)
                          : text.privacyDashboardNotLinked)
                      : null,
                  tone: state.phone.loaded ? _Tone.neutral : _Tone.unknown,
                ),
                _Row(
                  label: text.privacyDashboardDiscovery,
                  value: state.phone.loaded
                      ? (state.phone.link.discoverable ? text.commonOn : text.commonOff)
                      : null,
                  tone: state.phone.loaded ? _Tone.neutral : _Tone.unknown,
                ),
                _Row(
                  label: text.privacyDashboardContactSync,
                  value: state.phone.loaded
                      ? (state.phone.link.contactSync ? text.commonOn : text.commonOff)
                      : null,
                  tone: state.phone.loaded ? _Tone.neutral : _Tone.unknown,
                ),
              ],
            ),
            SettingsSection(
              caption: text.privacyDashboardIdentityAndRouting,
              children: [
                _Row(
                  label: text.privacyDashboardVerifiedContacts,
                  value: _verifiedContacts?.toString(),
                  tone: _verifiedContacts == null
                      ? _Tone.unknown
                      : _verifiedContacts! > 0
                          ? _Tone.good
                          : _Tone.neutral,
                  subtitle: text.privacyDashboardVerifiedNote,
                ),
                _Row(
                  label: text.proxyTitle,
                  value: ProxyController.instance.enabled
                      ? text.privacyDashboardProxySocks
                      : text.privacyDashboardProxyDirect,
                  tone: _Tone.neutral,
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                PrivioSpacing.gutter,
                PrivioSpacing.lg,
                PrivioSpacing.gutter,
                PrivioSpacing.sm,
              ),
              child: Text(
                text.privacyDashboardMetadataNote,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: PrivioColors.textTertiary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _backupValue(AppText text) {
    if (!_backupAsked) return null;
    return _remoteBackup == null
        ? text.privacyDashboardNoBackup
        : text.privacyDashboardBackupSealed;
  }

  String? _backupSubtitle(AppText text) {
    final remote = _remoteBackup;
    if (remote != null) return formatEventTime(text, remote.updatedAt);
    final last = _lastBackupAt;
    // A backup was made on this device but the server holds nothing — it went
    // to a file the user keeps. Worth saying rather than reading as "never".
    return last == null ? null : text.privacyDashboardLocalOnly;
  }
}

/// How a value reads at a glance. Deliberately four, including "not known":
/// a dashboard with only good and bad has to pick one for a value it does not
/// have, and picking is how it ends up lying.
enum _Tone { good, neutral, warn, unknown }

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    required this.tone,
    this.subtitle,
  });

  final String label;
  final String? value;
  final _Tone tone;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final colour = switch (tone) {
      _Tone.good => context.accents.accent,
      _Tone.warn => PrivioColors.warning,
      _Tone.neutral => PrivioColors.textSecondary,
      _Tone.unknown => PrivioColors.textTertiary,
    };
    return SettingsRow(
      label: label,
      subtitle: subtitle,
      // An em dash, not a blank and not a guess: the value has not arrived.
      trailing: Text(
        value ?? '—',
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: colour, fontWeight: FontWeight.w600),
      ),
    );
  }
}
