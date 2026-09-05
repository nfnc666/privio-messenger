import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/conversation_controller.dart';
import '../data/message_store.dart';
import '../theme/privio_colors.dart';
import '../widgets/avatar.dart';
import '../widgets/disappearing_timer_sheet.dart';
import '../widgets/privio_back_button.dart';
import '../widgets/settings_row.dart';

/// Who is in a group, and the way out of it.
///
/// A group could be created and joined and never left: the chat header counted
/// members and nothing listed them, the API client carried a `leaveGroup` with
/// no caller, and the server's rename and delete were unreachable. This is the
/// screen those were waiting for.
class GroupInfoScreen extends StatefulWidget {
  const GroupInfoScreen({required this.groupId, super.key});

  final String groupId;

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  List<GroupMember>? _members;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_load()));
  }

  Future<void> _load() async {
    final state = PrivioScope.of(context);
    try {
      final members = await state.conversations.groupMembers(widget.groupId);
      if (!mounted) return;
      setState(() {
        _members = members;
        _error = null;
        _loading = false;
      });
    } on Object {
      if (!mounted) return;
      // The list is the server's answer, so no answer means no list — not an
      // empty one, which would read as a group with nobody in it.
      setState(() {
        _error = 'Could not read who is in this group.';
        _loading = false;
      });
    }
  }

  bool _amAdmin(AppState state) {
    final me = state.accountId;
    final mine = _members?.where((m) => m.accountId == me);
    if (mine != null && mine.isNotEmpty) return mine.first.isAdmin;
    return state.conversations.groupInfo(widget.groupId)?.role == 'admin';
  }

  /// Sets the group's disappearing-message timer.
  ///
  /// Any member, not only an admin: the machinery is the sender's number riding
  /// inside each sealed payload, so a member who wants their own messages to go
  /// can already make that happen — and a permission the protocol cannot
  /// enforce is a lock drawn on the screen with nothing behind it. Everyone is
  /// told when it changes, which is the honest version of the same protection.
  Future<void> _chooseTimer(AppState state) async {
    final chosen = await DisappearingTimerSheet.choose(
      context,
      current: state.conversations.disappearAfter(widget.groupId),
      isGroup: true,
    );
    if (chosen == null || !mounted) return;
    state.conversations.setDisappearAfter(widget.groupId, chosen.value);
  }

  Future<void> _rename(AppState state) async {
    final controller = TextEditingController(
      text: state.conversations.groupInfo(widget.groupId)?.name ?? '',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PrivioColors.surface,
        title: const Text('Rename group'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Group name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    final ok = await state.conversations.renameGroup(widget.groupId, name);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Renamed. Everyone else opens the new name with the key they '
                  'already have.'
              : state.conversations.error ?? 'Could not rename the group.',
        ),
      ),
    );
  }

  Future<void> _confirmRemove(AppState state, GroupMember member) async {
    final yes = await _confirm(
      title: 'Remove ${member.label}?',
      body: 'They stop receiving what is sent from now on. What they already '
          'received stays on their device — nothing here can reach it.',
      action: 'Remove',
    );
    if (!yes || !mounted) return;
    final ok = await state.conversations.removeFromGroup(
      widget.groupId,
      member.accountId,
    );
    if (ok) await _load();
    if (!mounted || ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(state.conversations.error ?? 'Could not remove them.')),
    );
  }

  Future<void> _confirmLeave(AppState state) async {
    final yes = await _confirm(
      title: 'Leave this group?',
      body: 'You stop receiving what is sent to it, and the conversation goes '
          'from this device with everything in it. Nobody is told; the others '
          'see you disappear from the member list.',
      action: 'Leave',
    );
    if (!yes || !mounted) return;
    if (await state.conversations.leaveGroup(widget.groupId) && mounted) {
      // Out of the group, out of the chat, back to the list.
      Navigator.of(context)
        ..pop()
        ..pop();
    }
  }

  Future<void> _confirmDelete(AppState state) async {
    final yes = await _confirm(
      title: 'Delete this group?',
      body: 'It goes for everyone: nobody can send to it again. What has '
          'already been delivered stays on the devices that received it, which '
          'is every message anyone has read.',
      action: 'Delete',
    );
    if (!yes || !mounted) return;
    if (await state.conversations.deleteGroup(widget.groupId) && mounted) {
      Navigator.of(context)
        ..pop()
        ..pop();
    }
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
  }) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PrivioColors.surface,
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: PrivioColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return yes ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = PrivioScope.of(context);
    final group = state.conversations.groupInfo(widget.groupId);
    final members = _members ?? const <GroupMember>[];
    final admin = _amAdmin(state);

    return Scaffold(
      appBar: AppBar(
        leading: const PrivioBackButton(),
        title: const Text('Group info'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: PrivioColors.accent))
          : ListView(
              padding: const EdgeInsets.only(bottom: PrivioSpacing.xxxl),
              children: [
                const SizedBox(height: PrivioSpacing.xl),
                Center(
                  child: PrivioAvatar(
                    label: group?.name ?? 'Group',
                    isGroup: true,
                    size: 88,
                    seed: widget.groupId.hashCode.abs(),
                  ),
                ),
                const SizedBox(height: PrivioSpacing.md),
                Center(
                  child: Text(
                    group?.name ?? 'Group',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                const SizedBox(height: PrivioSpacing.xxl),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.gutter),
                    child: Text(
                      _error!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: PrivioColors.danger),
                    ),
                  ),
                SettingsSection(
                  caption: members.length == 1 ? '1 member' : '${members.length} members',
                  children: [
                    for (final member in members)
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: PrivioSpacing.gutter,
                        ),
                        leading: PrivioAvatar(
                          label: member.label,
                          seed: member.accountId.hashCode.abs(),
                        ),
                        title: Text(member.label, style: theme.textTheme.titleSmall),
                        subtitle: Text(
                          member.accountId == state.accountId
                              ? 'You${member.isAdmin ? ' · admin' : ''}'
                              : '@${member.username}'
                                  '${member.isAdmin ? ' · admin' : ''}',
                          style: theme.textTheme.bodySmall,
                        ),
                        trailing: admin && member.accountId != state.accountId
                            ? IconButton(
                                icon: const Icon(
                                  Icons.person_remove_outlined,
                                  color: PrivioColors.textTertiary,
                                ),
                                onPressed: () => unawaited(_confirmRemove(state, member)),
                              )
                            : null,
                      ),
                  ],
                ),
                const SizedBox(height: PrivioSpacing.xl),
                SettingsSection(
                  children: [
                    SettingsRow(
                      icon: Icons.timer_outlined,
                      label: 'Disappearing messages',
                      value: switch (state.conversations.disappearAfter(widget.groupId)) {
                        final timer? => ConversationController.describeTimer(timer),
                        null => 'Off',
                      },
                      onTap: () => unawaited(_chooseTimer(state)),
                    ),
                  ],
                ),
                const SizedBox(height: PrivioSpacing.xl),
                SettingsSection(
                  children: [
                    if (admin)
                      SettingsRow(
                        icon: Icons.drive_file_rename_outline_rounded,
                        label: 'Rename group',
                        onTap: () => unawaited(_rename(state)),
                      ),
                    SettingsRow(
                      label: 'Leave group',
                      destructive: true,
                      onTap: () => unawaited(_confirmLeave(state)),
                    ),
                    if (admin)
                      SettingsRow(
                        label: 'Delete group for everyone',
                        destructive: true,
                        onTap: () => unawaited(_confirmDelete(state)),
                      ),
                  ],
                ),
              ],
            ),
    );
  }
}
