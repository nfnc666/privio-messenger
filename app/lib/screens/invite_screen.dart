import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/app_state.dart';
import '../theme/privio_colors.dart';
import '../widgets/privio_back_button.dart';

/// Screen 10: how someone reaches you without ever learning your phone number.
class InviteScreen extends StatefulWidget {
  const InviteScreen({super.key});

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  int _tab = 0;

  /// Puts [text] on the clipboard and says so. Used by both the icon and the
  /// button below it, so there is one copy of what copying means.
  static Future<void> _copy(BuildContext context, String text, String said) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(said)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final username = PrivioScope.of(context).username ?? 'privio_user';
    final inviteUrl = 'https://privio.app/u/$username';
    final deepLink = 'privio://u/$username';

    return Scaffold(
      appBar: AppBar(
        leading: const PrivioBackButton(),
        title: const Text('Invite'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(PrivioSpacing.gutter),
        children: [
          _SegmentedTabs(
            labels: const ['Invite Link', 'QR Code'],
            selectedIndex: _tab,
            onSelected: (index) => setState(() => _tab = index),
          ),
          const SizedBox(height: PrivioSpacing.xxl),
          if (_tab == 0) ...[
            Text('Your invite link', style: theme.textTheme.bodySmall),
            const SizedBox(height: PrivioSpacing.sm),
            Container(
              padding: const EdgeInsets.all(PrivioSpacing.lg),
              decoration: const BoxDecoration(
                color: PrivioColors.surface,
                borderRadius: BorderRadius.all(PrivioRadius.card),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      inviteUrl,
                      style: theme.textTheme.bodyMedium?.copyWith(color: PrivioColors.accent),
                    ),
                  ),
                  IconButton(
                    onPressed: () =>
                        unawaited(_copy(context, inviteUrl, 'Invite link copied')),
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    tooltip: 'Copy link',
                  ),
                ],
              ),
            ),
            const SizedBox(height: PrivioSpacing.md),
            Text(
              'Share this link with others to invite them to Privio. It reveals '
              'your username and nothing else.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: PrivioSpacing.xl),
            // It said "Share Link" and did nothing. There is no share sheet
            // here — that is a platform plugin Privio does not carry — so the
            // button does what the app can actually do, which is what the
            // small icon above already does, in the place a thumb reaches.
            FilledButton(
              onPressed: () => unawaited(_copy(context, inviteUrl, 'Invite link copied')),
              child: const Text('Copy invite link'),
            ),
          ] else ...[
            Center(
              child: Container(
                padding: const EdgeInsets.all(PrivioSpacing.lg),
                decoration: const BoxDecoration(
                  color: PrivioColors.textPrimary,
                  borderRadius: BorderRadius.all(PrivioRadius.card),
                ),
                child: QrImageView(
                  data: deepLink,
                  version: QrVersions.auto,
                  size: 200,
                  backgroundColor: PrivioColors.textPrimary,
                  // Generated on-device: the code is never sent anywhere to be
                  // rendered.
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: PrivioColors.background,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: PrivioColors.background,
                  ),
                ),
              ),
            ),
            const SizedBox(height: PrivioSpacing.xl),
            Center(
              child: Text('Scan to connect with @$username', style: theme.textTheme.bodySmall),
            ),
            // "Save to Photos" used to sit here and do nothing. Writing an
            // image to the gallery needs a platform plugin this app does not
            // have, and the code is on screen: a screenshot is the way, and
            // the link tab copies the same invite as text.
          ],
        ],
      ),
    );
  }
}

class _SegmentedTabs extends StatelessWidget {
  const _SegmentedTabs({
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(PrivioSpacing.xs),
      decoration: const BoxDecoration(
        color: PrivioColors.surface,
        borderRadius: BorderRadius.all(PrivioRadius.card),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onSelected(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: PrivioSpacing.md),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == selectedIndex ? PrivioColors.surfaceHigh : Colors.transparent,
                    borderRadius: const BorderRadius.all(Radius.circular(9)),
                  ),
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: i == selectedIndex
                          ? PrivioColors.textPrimary
                          : PrivioColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
