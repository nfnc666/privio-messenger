import 'package:flutter/material.dart';

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
        ],
      ),
    );
  }
}
