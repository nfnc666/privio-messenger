import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/security_controller.dart';
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
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PrivioColors.surface,
        title: Text('Unblock ${user.label}?'),
        content: const Text('They will be able to send you messages again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Unblock'),
          ),
        ],
      ),
    );
    if (yes ?? false) await security.unblock(user.accountId);
  }

  @override
  Widget build(BuildContext context) {
    final security = PrivioScope.of(context).security;

    return Scaffold(
      appBar: AppBar(
        leading: const PrivioBackButton(),
        title: const Text('Blocked Users'),
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
                      value: 'Unblock',
                      onTap: () => _confirmUnblock(security, user),
                    ),
                ],
              ),
              const SizedBox(height: PrivioSpacing.lg),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xxl),
                child: Text(
                  'Blocking is invisible: their messages are dropped and they are '
                  'told nothing, so a block cannot be used to find out that they '
                  'have been blocked.',
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

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.block_rounded, size: 40, color: PrivioColors.textTertiary),
            const SizedBox(height: PrivioSpacing.lg),
            Text('Nobody is blocked', style: theme.textTheme.titleMedium),
            const SizedBox(height: PrivioSpacing.sm),
            Text(
              'Block someone from their chat, and they turn up here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
