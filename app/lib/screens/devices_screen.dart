import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/security_controller.dart';
import '../l10n/app_localizations.dart';
import '../theme/privio_colors.dart';
import '../widgets/privio_back_button.dart';
import '../widgets/settings_row.dart';

/// Screen 20: the devices signed in to this account, with remote logout.
///
/// It used to render four devices out of `DemoData` — an iPhone, a MacBook, an
/// iPad and a Windows PC — on the one screen whose entire job is answering "is
/// anyone else signed in to my account". The server has always been able to
/// answer that. This asks it.
class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) PrivioScope.of(context).security.loadDevices();
    });
  }

  Future<void> _confirmRevoke(SecurityController security, LinkedDevice device) async {
    final text = AppText.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PrivioColors.surface,
        title: Text(text.devicesRevokeTitle(device.name)),
        content: Text(text.devicesRevokeBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(text.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: PrivioColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(text.devicesSignItOut),
          ),
        ],
      ),
    );
    if (!(yes ?? false)) return;
    final ok = await security.revokeDevice(device.id);
    if (!mounted || !ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text.devicesSignedOut(device.name))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final security = PrivioScope.of(context).security;
    final text = AppText.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: const PrivioBackButton(),
        title: Text(text.settingsDevices),
      ),
      body: ListenableBuilder(
        listenable: security,
        builder: (context, _) {
          final devices = security.devices;
          if (devices == null) {
            return const Center(child: CircularProgressIndicator(strokeWidth: 2));
          }
          final current = devices.where((device) => device.current).toList();
          final others = devices.where((device) => !device.current).toList();

          return ListView(
            padding: const EdgeInsets.only(bottom: PrivioSpacing.xxxl),
            children: [
              if (current.isNotEmpty)
                SettingsSection(
                  caption: text.devicesThisDevice,
                  children: [
                    for (final device in current)
                      SettingsRow(
                        icon: Icons.smartphone_rounded,
                        label: device.name,
                        value: device.platform,
                      ),
                  ],
                ),
              SettingsSection(
                caption: others.isEmpty
                    ? text.devicesOthers
                    : text.devicesOthersTapToSignOut,
                children: [
                  if (others.isEmpty)
                    SettingsRow(
                      icon: Icons.devices_other_rounded,
                      label: text.devicesNone,
                      value: text.devicesOnlyThisOne,
                    )
                  else
                    for (final device in others)
                      SettingsRow(
                        icon: Icons.devices_other_rounded,
                        label: device.name,
                        value: _lastSeen(text, device),
                        onTap: () => _confirmRevoke(security, device),
                      ),
                ],
              ),
              if (security.error != null) ...[
                const SizedBox(height: PrivioSpacing.lg),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xxl),
                  child: Text(
                    security.error!,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: PrivioColors.danger),
                  ),
                ),
              ],
              const SizedBox(height: PrivioSpacing.lg),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xxl),
                child: Text(
                  text.devicesSignOutNote,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const _LicenceAllowance(),
            ],
          );
        },
      ),
    );
  }

  /// Coarse on purpose. "Last active: 14:32" on a device you do not recognise
  /// invites a precision this list cannot honestly offer — the server records
  /// when it last spoke, not when someone last read anything.
  static String _lastSeen(AppText text, LinkedDevice device) {
    final at = device.lastSeenAt;
    if (at == null) return text.devicesSignedIn;
    final ago = DateTime.now().difference(at);
    if (ago.inMinutes < 5) return text.devicesActiveNow;
    if (ago.inHours < 1) return text.devicesActiveMinutes(ago.inMinutes);
    if (ago.inDays < 1) return text.devicesActiveHours(ago.inHours);
    if (ago.inDays == 1) return text.devicesActiveYesterday;
    return text.devicesActiveDays(ago.inDays);
  }
}

/// How many devices the licence covers, when the server has said.
///
/// Rendered from the licence rather than from the list above, and only when
/// the numbers are actually known: an older server does not report them, and
/// inventing a limit the server does not enforce would be worse than silence.
class _LicenceAllowance extends StatelessWidget {
  const _LicenceAllowance();

  @override
  Widget build(BuildContext context) {
    final licence = PrivioScope.of(context).license;

    return ListenableBuilder(
      listenable: licence,
      builder: (context, _) {
        final state = licence.state;
        final limit = state?.maxDevices;
        if (state == null || !state.licensed || limit == null) {
          return const SizedBox.shrink();
        }
        final used = state.devices;

        return Padding(
          padding: const EdgeInsets.fromLTRB(
            PrivioSpacing.xxl,
            PrivioSpacing.md,
            PrivioSpacing.xxl,
            0,
          ),
          child: Text(
            used == null
                ? AppText.of(context).devicesLicenseCovers(limit)
                : AppText.of(context).devicesLicenseCoversUsed(limit, used),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: state.atDeviceLimit
                      ? PrivioColors.warning
                      : PrivioColors.textTertiary,
                ),
          ),
        );
      },
    );
  }
}
