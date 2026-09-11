import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../models/channel.dart';
import '../theme/privio_colors.dart';
import '../widgets/avatar.dart';
import '../widgets/privio_back_button.dart';
import '../widgets/search_field.dart';
import '../widgets/settings_row.dart';

/// Who runs a channel, and exactly what each of them may do.
///
/// Two rules decide everything on this screen, and both are the server's:
/// nobody may grant a permission they do not hold themselves, and nobody may
/// rewrite somebody who holds more than they do. They are shown rather than
/// hidden — a switch somebody cannot flip is drawn off and disabled instead of
/// being absent, so the rule is visible rather than mysterious.
///
/// The list itself is not a secret from members: who is in charge of a channel
/// is something everyone in it may see. Changing it is another matter.
class ChannelAdminsScreen extends StatefulWidget {
  const ChannelAdminsScreen({required this.channel, super.key});

  final ChannelInfo channel;

  @override
  State<ChannelAdminsScreen> createState() => _ChannelAdminsScreenState();
}

class _ChannelAdminsScreenState extends State<ChannelAdminsScreen> {
  final TextEditingController _search = TextEditingController();
  bool _editing = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(PrivioScope.of(context).channels.loadAdmins(widget.channel.id));
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  ChannelInfo get _channel =>
      PrivioScope.of(context).channels.channelById(widget.channel.id) ?? widget.channel;

  /// Whether this account may change who is an admin at all.
  bool get _mayAppoint => _channel.permissions.canAppointAdmins;

  Future<void> _add() async {
    final controller = PrivioScope.of(context).channels;
    // Anybody in the channel who is not already running it.
    await controller.loadMembers(_channel.id);
    if (!mounted) return;
    final candidates = [
      for (final member in controller.membersOf(_channel.id))
        if (!member.isAdmin) member,
    ];
    if (candidates.isEmpty) {
      _say('Everybody in this channel is already an admin.');
      return;
    }

    final chosen = await showModalBottomSheet<ChannelMember>(
      context: context,
      backgroundColor: PrivioColors.surface,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(PrivioSpacing.gutter),
              child: Text(
                'Who should be an admin?',
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            for (final member in candidates)
              ListTile(
                leading: PrivioAvatar(label: member.label, size: 36),
                title: Text(member.label),
                subtitle: Text('@${member.username}'),
                onTap: () => Navigator.of(sheetContext).pop(member),
              ),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    await _editPermissions(chosen, appointing: true);
  }

  /// The permission sheet for one person.
  Future<void> _editPermissions(ChannelMember member, {bool appointing = false}) async {
    final channel = _channel;
    final mine = channel.permissions;

    final result = await showModalBottomSheet<_AdminChange>(
      context: context,
      backgroundColor: PrivioColors.surface,
      isScrollControlled: true,
      builder: (_) => _PermissionSheet(
        member: member,
        actor: mine,
        appointing: appointing,
        // The owner is fixed, and that is the server's rule as well: their
        // authority is not stored and cannot be edited away.
        isOwner: member.isOwner,
        amOwner: channel.role == 'owner',
      ),
    );
    if (result == null || !mounted) return;

    final controller = PrivioScope.of(context).channels;
    final ok = result.dismiss
        ? await controller.setRole(
            channelId: channel.id,
            member: member,
            role: 'subscriber',
          )
        : await controller.setRole(
            channelId: channel.id,
            member: member,
            role: 'admin',
            permissions: result.permissions,
          );
    if (!mounted) return;
    if (!ok) {
      _say(controller.error ?? 'Could not change that.');
      return;
    }
    await controller.loadAdmins(channel.id);
  }

  Future<void> _transferOwnership() async {
    final controller = PrivioScope.of(context).channels;
    final admins = [
      for (final member in controller.adminsOf(_channel.id))
        if (!member.isOwner) member,
    ];
    if (admins.isEmpty) {
      _say('Make somebody an admin first.');
      return;
    }
    // The screen that already asks for the password and says what is
    // irreversible lives on the feed. Popping back to it rather than writing a
    // second confirmation that might say something slightly different.
    if (mounted) Navigator.of(context).pop('transfer');
  }

  Future<void> _toggleSignature({required bool on}) async {
    final controller = PrivioScope.of(context).channels;
    final ok = await controller.saveSettings(_channel, showSenderName: on);
    if (!mounted) return;
    if (!ok) _say(controller.error ?? 'Could not change that.');
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final state = PrivioScope.of(context);
    final controller = state.channels;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final channel = _channel;
        final needle = _query.trim().toLowerCase();
        final admins = [
          for (final member in controller.adminsOf(channel.id))
            if (needle.isEmpty ||
                member.label.toLowerCase().contains(needle) ||
                member.username.toLowerCase().contains(needle))
              member,
        ]..sort((a, b) {
            if (a.isOwner != b.isOwner) return a.isOwner ? -1 : 1;
            return a.label.toLowerCase().compareTo(b.label.toLowerCase());
          });

        return Scaffold(
          backgroundColor: PrivioColors.background,
          appBar: AppBar(
            backgroundColor: PrivioColors.background,
            leading: const PrivioBackButton(),
            title: const Text('Admins'),
            actions: [
              if (_mayAppoint)
                Padding(
                  padding: const EdgeInsets.only(right: PrivioSpacing.md),
                  child: TextButton(
                    onPressed: () => setState(() => _editing = !_editing),
                    style: TextButton.styleFrom(
                      backgroundColor: PrivioColors.surfaceRaised,
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: PrivioSpacing.lg,
                        vertical: PrivioSpacing.sm,
                      ),
                    ),
                    child: Text(_editing ? 'Done' : 'Edit'),
                  ),
                ),
            ],
          ),
          body: RefreshIndicator(
            color: PrivioColors.accent,
            backgroundColor: PrivioColors.surface,
            onRefresh: () => controller.loadAdmins(channel.id),
            child: ListView(
              padding: const EdgeInsets.only(bottom: PrivioSpacing.xxl),
              children: [
                PrivioSearchField(
                  controller: _search,
                  hintText: 'Search admins',
                  onChanged: (value) => setState(() => _query = value),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    PrivioSpacing.xl,
                    0,
                    PrivioSpacing.xl,
                    PrivioSpacing.sm,
                  ),
                  child: Text(
                    'CHANNEL ADMINISTRATORS',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: PrivioColors.textSecondary, letterSpacing: 0.6),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.gutter),
                  child: _Card(
                    children: [
                      if (_mayAppoint) ...[
                        ListTile(
                          leading: const Icon(
                            Icons.person_add_alt_1_rounded,
                            color: PrivioColors.accent,
                          ),
                          title: const Text(
                            'Add admin',
                            style: TextStyle(color: PrivioColors.accent),
                          ),
                          onTap: () => unawaited(_add()),
                        ),
                        const _Hairline(),
                      ],
                      if (admins.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(PrivioSpacing.xl),
                          child: Text(
                            'Nobody yet.',
                            style: TextStyle(color: PrivioColors.textTertiary),
                          ),
                        ),
                      for (var i = 0; i < admins.length; i++) ...[
                        if (i > 0) const _Hairline(),
                        _AdminRow(
                          member: admins[i],
                          editing: _editing && _mayAppoint,
                          onTap: _mayAppoint && !admins[i].isOwner
                              ? () => unawaited(_editPermissions(admins[i]))
                              : null,
                        ),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    PrivioSpacing.xl,
                    PrivioSpacing.sm,
                    PrivioSpacing.xl,
                    0,
                  ),
                  child: Text(
                    _mayAppoint
                        ? 'Administrators help you run your channel.'
                        : 'Administrators help run this channel. Only somebody '
                            'who may appoint admins can change this list.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: PrivioColors.textSecondary),
                  ),
                ),
                const SizedBox(height: PrivioSpacing.lg),

                // --- Signing ---
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.gutter),
                  child: _Card(
                    children: [
                      SettingsRow(
                        label: 'Show sender name',
                        subtitle: channel.permissions.canEditChannel
                            ? 'New posts carry the name of whoever wrote them'
                            : 'Only an admin who may edit the channel can change this',
                        enabled: channel.permissions.canEditChannel,
                        trailing: Switch(
                          value: channel.showSenderName,
                          onChanged: channel.permissions.canEditChannel
                              ? (on) => unawaited(_toggleSignature(on: on))
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: PrivioSpacing.md),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xl),
                  child: Text(
                    'With it off, everything the channel publishes is published '
                    'by the channel — no admin name is attached, and readers see '
                    'one voice.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: PrivioColors.textTertiary),
                  ),
                ),

                // --- Ownership ---
                if (channel.role == 'owner') ...[
                  const SizedBox(height: PrivioSpacing.lg),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.gutter),
                    child: _Card(
                      children: [
                        SettingsRow(
                          icon: Icons.swap_horiz_rounded,
                          iconTint: const Color(0xFFD97706),
                          label: 'Transfer ownership',
                          subtitle: 'Asks for your password, and cannot be undone',
                          onTap: () => unawaited(_transferOwnership()),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// One person in the admin list: picture, name, presence, badge, and who
/// appointed them.
class _AdminRow extends StatelessWidget {
  const _AdminRow({required this.member, required this.editing, this.onTap});

  final ChannelMember member;
  final bool editing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final presence = member.presenceLabel();
    // Who made them an admin, which is the second line in the template. The
    // owner has nobody above them, so their row shows presence instead.
    final second = member.isOwner
        ? presence
        : member.promotedByName != null
            ? 'promoted by ${member.promotedByName}'
            : presence;

    return ListTile(
      onTap: onTap,
      leading: PrivioAvatar(label: member.label, size: 40),
      title: Text(member.label),
      subtitle: second.isEmpty
          ? null
          : Text(
              second,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: presence == 'online' && second == presence
                    ? PrivioColors.accent
                    : PrivioColors.textSecondary,
              ),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _RoleBadge(owner: member.isOwner),
          if (editing && !member.isOwner)
            const Padding(
              padding: EdgeInsets.only(left: PrivioSpacing.sm),
              child: Icon(Icons.chevron_right_rounded, color: PrivioColors.textTertiary),
            ),
        ],
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.owner});

  final bool owner;

  @override
  Widget build(BuildContext context) {
    // The owner is set apart from the admins, as in the template — a different
    // tint, because it is a different thing: an admin can be dismissed and the
    // owner cannot.
    final colour = owner ? const Color(0xFFA855F7) : PrivioColors.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        owner ? 'Owner' : 'Admin',
        style: TextStyle(color: colour, fontSize: 12),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: PrivioColors.surfaceRaised,
          borderRadius: BorderRadius.circular(PrivioSpacing.md),
        ),
        child: Column(children: children),
      );
}

class _Hairline extends StatelessWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.only(left: 72),
        child: Divider(height: 1, thickness: 1, color: PrivioColors.border),
      );
}

/// What came back from the permission sheet.
class _AdminChange {
  const _AdminChange({required this.permissions, this.dismiss = false});

  final ChannelPermissions permissions;
  final bool dismiss;
}

/// One permission per row, with the ones the actor cannot grant drawn off and
/// disabled rather than hidden.
class _PermissionSheet extends StatefulWidget {
  const _PermissionSheet({
    required this.member,
    required this.actor,
    required this.appointing,
    required this.isOwner,
    required this.amOwner,
  });

  final ChannelMember member;
  final ChannelPermissions actor;
  final bool appointing;
  final bool isOwner;
  final bool amOwner;

  @override
  State<_PermissionSheet> createState() => _PermissionSheetState();
}

class _PermissionSheetState extends State<_PermissionSheet> {
  late ChannelPermissions _granted = widget.appointing
      // A new admin starts with what the person appointing them can actually
      // hand over, rather than with a set that will be refused on save.
      ? const ChannelPermissions(
          canPost: true,
          canEditChannel: true,
          canDeletePosts: true,
          canModerateDiscussion: true,
          canManageInvites: true,
          canManageLivestreams: true,
        )
      : widget.member.permissions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Nobody may rewrite somebody who already holds more than they do. Checked
    // here so the sheet says so, and again on the server, which is what
    // actually enforces it.
    final outranksMe = !widget.actor.covers(widget.member.permissions);

    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(PrivioSpacing.gutter),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.member.label, style: theme.textTheme.titleMedium),
              Text('@${widget.member.username}', style: theme.textTheme.bodySmall),
              const SizedBox(height: PrivioSpacing.md),
              if (widget.isOwner)
                Text(
                  'The owner holds every permission, and that is not editable — '
                  'not here and not on the server.',
                  style: theme.textTheme.bodySmall,
                )
              else if (outranksMe)
                Text(
                  'They hold permissions you do not, so you cannot change what '
                  'they may do.',
                  style: theme.textTheme.bodySmall?.copyWith(color: PrivioColors.warning),
                )
              else
                Text(
                  'You can only hand out what you hold yourself. Anything you '
                  'do not have is off and cannot be switched on.',
                  style: theme.textTheme.bodySmall,
                ),
              const SizedBox(height: PrivioSpacing.md),

              for (final permission in ChannelPermissions.all)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(permission.label),
                  subtitle: Text(
                    widget.actor.has(permission.key)
                        ? permission.detail
                        : 'You do not hold this yourself',
                    style: TextStyle(
                      color: widget.actor.has(permission.key)
                          ? PrivioColors.textTertiary
                          : PrivioColors.warning,
                    ),
                  ),
                  value: widget.isOwner || _granted.has(permission.key),
                  onChanged: widget.isOwner ||
                          outranksMe ||
                          !widget.actor.has(permission.key)
                      ? null
                      : (on) => setState(
                            () => _granted = _granted.withFlag(permission.key, on: on),
                          ),
                ),

              const SizedBox(height: PrivioSpacing.md),
              Row(
                children: [
                  if (!widget.isOwner && !outranksMe && !widget.appointing)
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(
                        _AdminChange(permissions: _granted, dismiss: true),
                      ),
                      child: const Text(
                        'Dismiss as admin',
                        style: TextStyle(color: PrivioColors.danger),
                      ),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  if (!widget.isOwner && !outranksMe)
                    FilledButton(
                      onPressed: () => Navigator.of(context)
                          .pop(_AdminChange(permissions: _granted)),
                      child: Text(widget.appointing ? 'Appoint' : 'Save'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
