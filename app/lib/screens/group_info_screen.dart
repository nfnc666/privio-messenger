import 'dart:async';

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../models/models.dart';
import '../l10n/app_localizations.dart';
import '../l10n/failure_text.dart';
import '../l10n/notice_text.dart';
import '../data/message_store.dart';
import '../theme/accent.dart';
import '../theme/privio_colors.dart';
import '../widgets/avatar.dart';
import '../widgets/disappearing_timer_sheet.dart';
import '../widgets/privio_back_button.dart';
import '../widgets/settings_row.dart';
import 'contact_profile_screen.dart';

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
  /// Whether the member list could be read. A flag, not a sentence: the
  /// sentence belongs to whoever is reading the screen.
  bool _loadFailed = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_load()));
  }

  Future<void> _load() async {
    final state = PrivioScope.of(context);
    // The picture is fetched beside the members and not awaited with them: a
    // slow or missing picture must not hold up the list of who is here.
    unawaited(_loadAvatar(state));
    try {
      final members = await state.conversations.groupMembers(widget.groupId);
      if (!mounted) return;
      setState(() {
        _members = members;
        _loadFailed = false;
        _loading = false;
      });
    } on Object {
      if (!mounted) return;
      // The list is the server's answer, so no answer means no list — not an
      // empty one, which would read as a group with nobody in it.
      setState(() {
        _loadFailed = true;
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
  /// Admins only, and this is a real restriction rather than a greyed-out row:
  /// a change is announced in its own payload, and every device that receives
  /// one asks the server for the group's member list before applying it. A
  /// member who patched their client can send the payload; nobody acts on it.
  ///
  /// It has to be enforced that way round, because the timer is the group's
  /// setting: it decides when everybody else's messages vanish, not only the
  /// sender's own.
  Future<void> _chooseTimer(AppState state) async {
    if (!state.conversations.mayChangeDisappearAfter(widget.groupId)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppText.of(context).groupAdminOnly)),
      );
      return;
    }
    final chosen = await DisappearingTimerSheet.choose(
      context,
      current: state.conversations.chatTimer(widget.groupId),
      accountDefault: state.conversations.defaultDisappearAfter,
      isGroup: true,
    );
    if (chosen == null || !mounted) return;
    final changed = await state.conversations.setChatTimer(widget.groupId, chosen.value);
    if (!changed && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppText.of(context).groupAdminOnly)),
      );
    }
  }

  /// The group's picture, fetched once the screen knows there is one.
  Uint8List? _avatar;
  bool _busyAvatar = false;

  Future<void> _loadAvatar(AppState state) async {
    final bytes = await state.conversations.groupAvatar(widget.groupId);
    if (!mounted) return;
    setState(() => _avatar = bytes);
  }

  /// Offers to change or remove the picture. Admins only — a member's tap does
  /// nothing here and the server would refuse it anyway.
  Future<void> _pictureActions(AppState state) async {
    final text = AppText.of(context);
    final hasOne = state.conversations.groupInfo(widget.groupId)?.avatarMediaId != null;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: PrivioColors.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(text.groupPictureChoose),
              onTap: () => Navigator.of(sheetContext).pop('pick'),
            ),
            if (hasOne)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: PrivioColors.danger),
                title: Text(
                  text.groupPictureRemove,
                  style: const TextStyle(color: PrivioColors.danger),
                ),
                onTap: () => Navigator.of(sheetContext).pop('remove'),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'remove') {
      setState(() => _busyAvatar = true);
      final ok = await state.conversations.clearGroupAvatar(widget.groupId);
      if (!mounted) return;
      setState(() {
        _busyAvatar = false;
        if (ok) _avatar = null;
      });
      if (!ok) _say(state.conversations.failure?.words(text) ?? text.groupPictureFailed);
      return;
    }

    PlatformFile? picked;
    try {
      picked = await FilePicker.pickFile(type: FileType.image)
          .timeout(const Duration(minutes: 2));
    } on Object {
      if (mounted) _say(text.groupPictureFailed);
      return;
    }
    if (picked == null || !mounted) return;
    final Uint8List bytes;
    try {
      bytes = await picked.readAsBytes();
    } on Object {
      if (mounted) _say(text.groupPictureFailed);
      return;
    }
    if (!mounted) return;

    setState(() => _busyAvatar = true);
    final ok = await state.conversations.setGroupAvatar(widget.groupId, bytes);
    if (!mounted) return;
    setState(() => _busyAvatar = false);
    if (!ok) {
      _say(state.conversations.failure?.words(text) ?? text.groupPictureFailed);
      return;
    }
    await _loadAvatar(state);
  }

  /// Edits what the group says it is for.
  Future<void> _describe(AppState state) async {
    final text = AppText.of(context);
    final controller = TextEditingController(
      text: state.conversations.groupInfo(widget.groupId)?.description ?? '',
    );
    final written = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PrivioColors.surface,
        title: Text(text.groupDescriptionTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 4,
              maxLength: groupDescriptionMaxLength,
              decoration: InputDecoration(hintText: text.groupDescriptionHint),
            ),
            // Said here rather than assumed: the text is sealed with the
            // group's key, like its name and its messages.
            Text(
              text.groupDescriptionSealed,
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(text.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(text.commonSave),
          ),
        ],
      ),
    );
    if (written == null || !mounted) return;
    final ok = await state.conversations.describeGroup(widget.groupId, written);
    if (!mounted) return;
    _say(
      ok
          ? text.groupDescriptionSaved
          : state.conversations.failure?.words(text) ?? text.groupDescriptionFailed,
    );
  }

  void _say(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _rename(AppState state) async {
    final text = AppText.of(context);
    final controller = TextEditingController(
      text: state.conversations.groupInfo(widget.groupId)?.name ?? '',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PrivioColors.surface,
        title: Text(text.groupRename),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: text.groupName),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(text.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(text.groupRenameAction),
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
              ? text.groupRenamed
              : state.conversations.failure?.words(text) ?? text.groupCouldNotRename,
        ),
      ),
    );
  }

  Future<void> _confirmRemove(AppState state, GroupMember member) async {
    final text = AppText.of(context);
    final yes = await _confirm(
      title: text.groupRemoveTitle(member.label),
      body: text.groupRemoveBody,
      action: text.commonRemove,
    );
    if (!yes || !mounted) return;
    final ok = await state.conversations.removeFromGroup(
      widget.groupId,
      member.accountId,
    );
    if (ok) await _load();
    if (!mounted || ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(state.conversations.failure?.words(text) ?? text.groupCouldNotRemove),
      ),
    );
  }

  Future<void> _confirmLeave(AppState state) async {
    final text = AppText.of(context);
    final yes = await _confirm(
      title: text.groupLeaveTitle,
      body: text.groupLeaveBody,
      action: text.groupLeave,
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
    final text = AppText.of(context);
    final yes = await _confirm(
      title: text.groupDeleteTitle,
      body: text.groupDeleteBody,
      action: text.commonDelete,
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
            child: Text(AppText.of(dialogContext).commonCancel),
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

  /// "You · admin", "@bruno", and the two in between.
  static String _memberLine(AppText text, GroupMember member, {required bool mine}) {
    final who = mine ? text.groupYouSuffix : '@${member.username}';
    return member.isAdmin ? '$who · ${text.groupAdminSuffix}' : who;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = PrivioScope.of(context);
    final group = state.conversations.groupInfo(widget.groupId);
    final members = _members ?? const <GroupMember>[];
    final admin = _amAdmin(state);
    final text = AppText.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: const PrivioBackButton(),
        title: Text(text.chatGroupInfo),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: context.accents.accent))
          : ListView(
              padding: const EdgeInsets.only(bottom: PrivioSpacing.xxxl),
              children: [
                const SizedBox(height: PrivioSpacing.xl),
                Center(
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      PrivioAvatar(
                        label: group?.name ?? text.chatsGroupFallbackName,
                        isGroup: true,
                        size: 88,
                        seed: widget.groupId.hashCode.abs(),
                        imageBytes: _avatar,
                      ),
                      // Only an admin is offered the camera. A member sees the
                      // picture and nothing suggesting they can change it,
                      // which is what the server would tell them anyway.
                      if (admin)
                        Material(
                          color: context.accents.accent,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _busyAvatar
                                ? null
                                : () => unawaited(_pictureActions(state)),
                            child: Padding(
                              padding: const EdgeInsets.all(PrivioSpacing.xs),
                              child: _busyAvatar
                                  ? SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: context.accents.onAccent,
                                      ),
                                    )
                                  : Icon(
                                      Icons.photo_camera_outlined,
                                      size: 16,
                                      color: context.accents.onAccent,
                                    ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: PrivioSpacing.md),
                Center(
                  child: Text(
                    group?.name ?? text.chatsGroupFallbackName,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                // What the group is for, when somebody has said. Shown to
                // every member; only an admin has the row that changes it.
                if ((group?.description ?? '').isNotEmpty) ...[
                  const SizedBox(height: PrivioSpacing.sm),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xxl),
                    child: Text(
                      group!.description!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: PrivioColors.textSecondary),
                    ),
                  ),
                ],
                const SizedBox(height: PrivioSpacing.xxl),
                if (_loadFailed)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.gutter),
                    child: Text(
                      text.groupInfoCouldNotRead,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: PrivioColors.danger),
                    ),
                  ),
                SettingsSection(
                  caption: text.channelMembers(members.length),
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
                          _memberLine(text, member, mine: member.accountId == state.accountId),
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
                        // The other way into a member's profile, for somebody
                        // who came here to find out who is in the group rather
                        // than arriving at a message they wanted to trace.
                        onTap: () => unawaited(
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ContactProfileScreen(
                                accountId: member.accountId,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: PrivioSpacing.xl),
                SettingsSection(
                  children: [
                    SettingsRow(
                      icon: Icons.timer_outlined,
                      label: text.disappearingTitle,
                      // The effective duration — what messages sent here
                      // actually get — rather than the group's own field,
                      // which may be "whatever the account says".
                      value: switch (state.conversations.disappearAfter(widget.groupId)) {
                        final timer? => describeDuration(text, timer),
                        null => text.disappearingOff,
                      },
                      // And where that number comes from, because the two
                      // read identically otherwise: a group showing "1 hour"
                      // because it was set to one hour and a group showing it
                      // because the account default says so behave
                      // differently the next time that default changes.
                      subtitle: state.conversations.chatTimer(widget.groupId).explicit
                          ? null
                          : text.disappearingFollowsDefault,
                      // Still tappable for a member, and it says why rather
                      // than doing nothing: a row that ignores a tap reads as
                      // a bug, and the reason is worth one line.
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
                        label: text.groupRename,
                        onTap: () => unawaited(_rename(state)),
                      ),
                    if (admin)
                      SettingsRow(
                        icon: Icons.notes_rounded,
                        label: text.groupDescriptionRow,
                        // The current text as the value, so an admin can see
                        // what is there without opening the editor to find out.
                        value: (group?.description ?? '').isEmpty
                            ? text.groupDescriptionNone
                            : group!.description!,
                        onTap: () => unawaited(_describe(state)),
                      ),
                    SettingsRow(
                      label: text.groupLeaveRow,
                      destructive: true,
                      onTap: () => unawaited(_confirmLeave(state)),
                    ),
                    if (admin)
                      SettingsRow(
                        label: text.groupDeleteRow,
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
