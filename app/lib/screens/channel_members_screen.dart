import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../models/channel.dart';
import '../theme/privio_colors.dart';
import '../widgets/avatar.dart';
import '../widgets/privio_back_button.dart';

/// Who is in a channel, and what each of them may do.
///
/// The two rules the server enforces are shown rather than hidden: an admin can
/// only grant permissions they hold themselves, so anything they lack is greyed
/// out here instead of being offered and then refused.
class ChannelMembersScreen extends StatefulWidget {
  const ChannelMembersScreen({required this.channel, super.key});

  final ChannelInfo channel;

  @override
  State<ChannelMembersScreen> createState() => _ChannelMembersScreenState();
}

class _ChannelMembersScreenState extends State<ChannelMembersScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => PrivioScope.of(context).channels.loadMembers(widget.channel.id),
    );
  }

  Future<void> _edit(ChannelMember member) async {
    final result = await showModalBottomSheet<_RoleChange>(
      context: context,
      backgroundColor: PrivioColors.surface,
      isScrollControlled: true,
      builder: (_) => _RoleSheet(member: member, actor: widget.channel.permissions),
    );
    if (result == null || !mounted) return;

    final controller = PrivioScope.of(context).channels;
    final ok = result.remove
        ? await controller.removeMember(widget.channel.id, member.id)
        : await controller.setRole(
            channelId: widget.channel.id,
            member: member,
            role: result.role,
            permissions: result.permissions,
          );
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(controller.error ?? 'Could not change that member')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = PrivioScope.of(context);
    final controller = state.channels;
    final canManage = widget.channel.permissions.canManageMembers;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final members = controller.membersOf(widget.channel.id);
        final complete = controller.membersAreComplete(widget.channel.id);

        return Scaffold(
          appBar: AppBar(
            leading: const PrivioBackButton(),
            title: Text(complete ? 'Members' : 'Who runs this channel'),
          ),
          body: ListView.builder(
            // The note is a row of its own so it scrolls with the list rather
            // than sitting above it as a banner nobody reads twice.
            itemCount: members.length + (complete ? 0 : 1),
            itemBuilder: (context, index) {
              if (!complete && index == members.length) return const _AudienceNote();
              final member = members[index];
              final editable = canManage && !member.isOwner && member.id != state.accountId;

              return ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: PrivioSpacing.gutter,
                  vertical: PrivioSpacing.xs,
                ),
                leading: PrivioAvatar(label: member.label, seed: member.id.hashCode.abs()),
                title: Text(member.label),
                subtitle: Text(
                  _describe(member),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                trailing: editable
                    ? IconButton(
                        onPressed: () => _edit(member),
                        icon: const Icon(Icons.tune_rounded, size: 20),
                        tooltip: 'Role and permissions',
                      )
                    : null,
              );
            },
          ),
        );
      },
    );
  }

  /// A role name alone says nothing: two admins can hold entirely different
  /// powers, so the list spells out what each one actually has.
  static String _describe(ChannelMember member) {
    if (member.isOwner) return 'Owner · everything';
    final granted = <String>[
      if (member.permissions.canPost) 'post',
      if (member.permissions.canEditChannel) 'edit',
      if (member.permissions.canDeletePosts) 'delete posts',
      if (member.permissions.canManageMembers) 'manage members',
      if (member.permissions.canDeleteChannel) 'delete channel',
    ];
    if (granted.isEmpty) return 'Subscriber · read only';
    return '${member.role == 'admin' ? 'Admin' : 'Subscriber'} · ${granted.join(', ')}';
  }
}

class _RoleChange {
  const _RoleChange({required this.role, required this.permissions, this.remove = false});

  final String role;
  final ChannelPermissions permissions;
  final bool remove;
}

class _RoleSheet extends StatefulWidget {
  const _RoleSheet({required this.member, required this.actor});

  final ChannelMember member;

  /// What the person doing the editing holds. Anything missing here cannot be
  /// granted, and the server would refuse it anyway.
  final ChannelPermissions actor;

  @override
  State<_RoleSheet> createState() => _RoleSheetState();
}

class _RoleSheetState extends State<_RoleSheet> {
  late String _role = widget.member.role == 'owner' ? 'admin' : widget.member.role;
  late bool _canPost = widget.member.permissions.canPost;
  late bool _canEditChannel = widget.member.permissions.canEditChannel;
  late bool _canDeletePosts = widget.member.permissions.canDeletePosts;
  late bool _canManageMembers = widget.member.permissions.canManageMembers;
  late bool _canDeleteChannel = widget.member.permissions.canDeleteChannel;

  ChannelPermissions get _permissions => _role == 'subscriber'
      ? const ChannelPermissions()
      : ChannelPermissions(
          canPost: _canPost,
          canEditChannel: _canEditChannel,
          canDeletePosts: _canDeletePosts,
          canManageMembers: _canManageMembers,
          canDeleteChannel: _canDeleteChannel,
        );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAdmin = _role == 'admin';

    // Admin adds five toggles, which on a small screen is more than the sheet
    // has room for. The toggles scroll; Save and Remove stay pinned, because a
    // button you have to go looking for is a button that gets missed.
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  PrivioSpacing.gutter,
                  PrivioSpacing.gutter,
                  PrivioSpacing.gutter,
                  0,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.member.label, style: theme.textTheme.titleMedium),
                    const SizedBox(height: PrivioSpacing.lg),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'subscriber', label: Text('Subscriber')),
                        ButtonSegment(value: 'admin', label: Text('Admin')),
                      ],
                      selected: {_role},
                      onSelectionChanged: (selected) => setState(() => _role = selected.first),
                    ),
                    const SizedBox(height: PrivioSpacing.lg),
                    if (isAdmin) ...[
                      _Toggle(
                        label: 'Post',
                        value: _canPost,
                        allowed: widget.actor.canPost,
                        onChanged: (v) => setState(() => _canPost = v),
                      ),
                      _Toggle(
                        label: 'Edit the channel',
                        value: _canEditChannel,
                        allowed: widget.actor.canEditChannel,
                        onChanged: (v) => setState(() => _canEditChannel = v),
                      ),
                      _Toggle(
                        label: 'Delete posts',
                        value: _canDeletePosts,
                        allowed: widget.actor.canDeletePosts,
                        onChanged: (v) => setState(() => _canDeletePosts = v),
                      ),
                      _Toggle(
                        label: 'Manage members',
                        value: _canManageMembers,
                        allowed: widget.actor.canManageMembers,
                        onChanged: (v) => setState(() => _canManageMembers = v),
                      ),
                      _Toggle(
                        label: 'Delete the channel',
                        value: _canDeleteChannel,
                        allowed: widget.actor.canDeleteChannel,
                        onChanged: (v) => setState(() => _canDeleteChannel = v),
                      ),
                      const SizedBox(height: PrivioSpacing.sm),
                      Text(
                        'Greyed-out permissions are ones you do not hold yourself. '
                        'Nobody can hand out more than they have.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ] else
                      Text(
                        'A subscriber reads the channel and nothing else.',
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(PrivioSpacing.gutter),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(
                      _RoleChange(role: _role, permissions: _permissions),
                    ),
                    child: const Text('Save'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(
                      const _RoleChange(
                        role: 'subscriber',
                        permissions: ChannelPermissions(),
                        remove: true,
                      ),
                    ),
                    style: TextButton.styleFrom(foregroundColor: PrivioColors.danger),
                    child: const Text('Remove from channel'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.value,
    required this.allowed,
    required this.onChanged,
  });

  final String label;
  final bool value;

  /// False when the editor lacks this permission themselves.
  final bool allowed;

  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: value && allowed,
      onChanged: allowed ? onChanged : null,
      contentPadding: EdgeInsets.zero,
      dense: true,
      activeThumbColor: PrivioColors.accent,
      title: Text(
        label,
        style: TextStyle(
          color: allowed ? PrivioColors.textPrimary : PrivioColors.textTertiary,
        ),
      ),
    );
  }
}

/// Why a subscriber is not shown everybody.
///
/// Saying nothing would be the worse choice: a short list of admins looks like
/// a small channel, and a reader deciding whether to post something personal
/// deserves to know the roster is not on offer to the person beside them either.
class _AudienceNote extends StatelessWidget {
  const _AudienceNote();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(
          PrivioSpacing.gutter,
          PrivioSpacing.lg,
          PrivioSpacing.gutter,
          PrivioSpacing.xl,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.shield_outlined, size: 18, color: PrivioColors.textSecondary),
            const SizedBox(width: PrivioSpacing.sm),
            Expanded(
              child: Text(
                'Only the people who run this channel are listed. Who reads it '
                'is not shown to other readers — including you.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: PrivioColors.textSecondary),
              ),
            ),
          ],
        ),
      );
}
