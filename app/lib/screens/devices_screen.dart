import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../data/demo_data.dart';
import '../theme/privio_colors.dart';
import '../widgets/settings_row.dart';

/// Screen 20: connected devices, with remote logout.
class DevicesScreen extends StatelessWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const devices = DemoData.devices;
    final current = devices.where((d) => d.isCurrent).toList();
    final others = devices.where((d) => !d.isCurrent).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Devices')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: PrivioSpacing.xxxl),
        children: [
          SettingsSection(
            caption: 'This device',
            children: [
              for (final device in current)
                SettingsRow(
                  icon: Icons.smartphone_rounded,
                  label: device.name,
                  value: device.lastActive,
                ),
            ],
          ),
          SettingsSection(
            caption: 'Other devices',
            children: [
              for (final device in others)
                SettingsRow(
                  icon: Icons.devices_other_rounded,
                  label: device.name,
                  value: device.lastActive,
                  onTap: () {},
                ),
            ],
          ),
          const SizedBox(height: PrivioSpacing.lg),
          SettingsSection(
            children: [
              SettingsRow(label: 'Log Out All Devices', destructive: true, onTap: () {}),
            ],
          ),
          const SizedBox(height: PrivioSpacing.lg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xxl),
            child: Text(
              'Removing a device revokes its session and deletes anything still '
              'queued for it. It can only rejoin by logging in again.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const _LicenceAllowance(),
        ],
      ),
    );
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
                ? 'Your license covers $limit devices.'
                : 'Your license covers $limit devices. $used in use.',
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
