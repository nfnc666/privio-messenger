import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/security_controller.dart';
import '../l10n/app_localizations.dart';
import '../theme/privio_colors.dart';
import '../widgets/privio_back_button.dart';
import '../widgets/settings_row.dart';

/// Who this account has blocked, and how to stop.
///
/// The server has enforced blocking all along — a blocked sender's messages are
/// dropped and they are told nothing — but nothing in the app could see the
/// list, so the Privacy screen showed the number 3 no matter who was blocked.
class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) PrivioScope.of(context).security.loadBlocks();
    });
  }

  Future<void> _confirmUnblock(SecurityController security, BlockedUser user) async {
    final text = AppText.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PrivioColors.surface,
        title: Text(text.blockedUnblockTitle(user.label)),
        content: Text(text.blockedUnblockBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(text.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(text.blockedUnblock),
          ),
        ],
      ),
    );
    if (yes ?? false) await security.unblock(user.accountId);
  }

  @override
  Widget build(BuildContext context) {
    final security = PrivioScope.of(context).security;
    final text = AppText.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: const PrivioBackButton(),
        title: Text(text.privacyBlockedUsers),
      ),
      body: ListenableBuilder(
        listenable: security,
        builder: (context, _) {
          final blocked = security.blocked;
          if (blocked == null) {
            return const Center(child: CircularProgressIndicator(strokeWidth: 2));
          }
          if (blocked.isEmpty) return const _Empty();

          return ListView(
            padding: const EdgeInsets.only(bottom: PrivioSpacing.xxxl),
            children: [
              SettingsSection(
                children: [
                  for (final user in blocked)
                    SettingsRow(
                      label: user.label,
                      value: text.blockedUnblock,
                      onTap: () => _confirmUnblock(security, user),
                    ),
                ],
              ),
              const SizedBox(height: PrivioSpacing.lg),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xxl),
                child: Text(
                  text.blockedInvisibleNote,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = AppText.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.block_rounded, size: 40, color: PrivioColors.textTertiary),
            const SizedBox(height: PrivioSpacing.lg),
            Text(text.blockedNobody, style: theme.textTheme.titleMedium),
            const SizedBox(height: PrivioSpacing.sm),
            Text(
              text.blockedEmptyNote,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
