import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../models/channel.dart';
import '../services/channel_service.dart';
import '../theme/privio_colors.dart';
import '../widgets/avatar.dart';
import '../widgets/privio_back_button.dart';
import '../widgets/search_field.dart';

/// Who is subscribed to a channel.
///
/// **The list is not public.** The server hands the whole roster only to an
/// admin who may manage members; everybody else gets the channel's staff and
/// themselves, and is told so rather than being shown a short list that looks
/// like the whole thing. That is the `complete` flag, and the notice at the top
/// of this screen is what it looks like.
///
/// It pages rather than truncating. The old call took the first five hundred
/// and said nothing about the rest, which reads on screen exactly like a
/// complete list of a channel with five hundred people in it.
class ChannelSubscribersScreen extends StatefulWidget {
  const ChannelSubscribersScreen({required this.channel, super.key});

  final ChannelInfo channel;

  @override
  State<ChannelSubscribersScreen> createState() => _ChannelSubscribersScreenState();
}

class _ChannelSubscribersScreenState extends State<ChannelSubscribersScreen> {
  final TextEditingController _search = TextEditingController();
  final ScrollController _scroll = ScrollController();
  Timer? _debounce;
  String _query = '';
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = PrivioScope.of(context).channels;
      unawaited(controller.loadMembers(widget.channel.id));
      if (widget.channel.permissions.canManageMembers) {
        unawaited(controller.loadBans(widget.channel.id));
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    _search.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels < _scroll.position.maxScrollExtent - 400) return;
    final controller = PrivioScope.of(context).channels;
    if (controller.loading || !controller.hasMoreMembers(widget.channel.id)) return;
    unawaited(controller.loadMoreMembers(widget.channel.id, query: _query));
  }

  /// Typing runs a server-side search, so a large channel is not downloaded to
  /// be filtered. Debounced, because every keystroke would otherwise be a
  /// request.
  void _onQuery(String value) {
    setState(() => _query = value);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      unawaited(
        PrivioScope.of(context).channels.loadMembers(widget.channel.id, query: value),
      );
    });
  }

  ChannelInfo get _channel =>
      PrivioScope.of(context).channels.channelById(widget.channel.id) ?? widget.channel;

  Future<void> _add() async {
    final state = PrivioScope.of(context);
    final contacts = state.conversations.contacts;
    if (contacts.isEmpty) {
      _say('No contacts to add yet.');
      return;
    }
    final already = {for (final m in state.channels.membersOf(_channel.id)) m.id};

    final chosen = await showModalBottomSheet<List<String>>(
      context: context,
      backgroundColor: PrivioColors.surface,
      isScrollControlled: true,
      builder: (_) => _PickPeopleSheet(
        people: [
          for (final contact in contacts)
            if (!already.contains(contact.id))
              (
                id: contact.id,
                label: contact.displayName.isNotEmpty
                    ? contact.displayName
                    : contact.username,
              ),
        ],
      ),
    );
    if (chosen == null || chosen.isEmpty || !mounted) return;

    final result = await state.channels.addMembers(_channel.id, chosen);
    if (!mounted) return;
    if (result == null) {
      _say(state.channels.error ?? 'Could not add anybody.');
      return;
    }
    if (result.invite.isEmpty) {
      _say(result.added.length == 1 ? 'Added.' : 'Added ${result.added.length} people.');
      return;
    }
    // The honest half: their own privacy setting refused, so a link is the only
    // way in. Never reported as a plain success.
    await _offerInvite(result.added.length, result.invite.length);
  }

  Future<void> _offerInvite(int added, int needInvite) async {
    final link = ChannelService.shareLinkFor(_channel);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PrivioColors.surface,
        title: Text(added == 0 ? 'Nobody could be added' : 'Added $added'),
        content: Text(
          '$needInvite ${needInvite == 1 ? 'person has' : 'people have'} set '
          'their account so only their own contacts can add them to things. '
          'Send them the link instead and let them decide.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
          if (link != null)
            FilledButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: link));
                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                _say('Link copied.');
              },
              child: const Text('Copy the link'),
            ),
        ],
      ),
    );
  }

  Future<void> _actOn(ChannelMember member) async {
    final channel = _channel;
    if (!channel.permissions.canManageMembers) return;
    if (member.isOwner) {
      _say('The owner cannot be removed.');
      return;
    }

    final controller = PrivioScope.of(context).channels;
    final silenced = controller.bansIn(channel.id).any((b) => b.accountId == member.id);

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: PrivioColors.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(PrivioSpacing.gutter),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(member.label, style: Theme.of(sheetContext).textTheme.titleMedium),
                  Text('@${member.username}',
                      style: Theme.of(sheetContext).textTheme.bodySmall),
                ],
              ),
            ),
            ListTile(
              leading: Icon(
                silenced ? Icons.volume_up_rounded : Icons.volume_off_rounded,
              ),
              title: Text(silenced ? 'Let them speak again' : 'Silence them'),
              subtitle: Text(
                silenced
                    ? 'They can comment again'
                    : 'They stay subscribed and stop being able to comment',
              ),
              onTap: () => Navigator.of(sheetContext).pop(silenced ? 'unsilence' : 'silence'),
            ),
            ListTile(
              leading: const Icon(Icons.person_remove_outlined, color: PrivioColors.danger),
              title: const Text(
                'Remove from the channel',
                style: TextStyle(color: PrivioColors.danger),
              ),
              subtitle: const Text(
                'The channel moves to a new key, so they cannot read what comes next',
              ),
              onTap: () => Navigator.of(sheetContext).pop('remove'),
            ),
            const SizedBox(height: PrivioSpacing.sm),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    final ok = switch (action) {
      'remove' => await controller.removeMember(channel.id, member.id),
      'silence' => await controller.setBanned(channel.id, member.id, banned: true),
      _ => await controller.setBanned(channel.id, member.id, banned: false),
    };
    if (!mounted) return;
    if (!ok) {
      _say(controller.error ?? 'Could not do that.');
      return;
    }
    await controller.loadBans(channel.id);
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
        final members = controller.membersOf(channel.id);
        final complete = controller.membersAreComplete(channel.id);
        final mayManage = channel.permissions.canManageMembers;

        // The template's two sections: people already in the address book, then
        // everybody else. It is a real distinction — the first group is who you
        // know is here.
        final contacts = [for (final m in members) if (m.isContact) m];
        final others = [for (final m in members) if (!m.isContact) m];

        return Scaffold(
          backgroundColor: PrivioColors.background,
          appBar: AppBar(
            backgroundColor: PrivioColors.background,
            leading: const PrivioBackButton(),
            title: const Text('Subscribers'),
            actions: [
              if (mayManage)
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
            onRefresh: () => controller.loadMembers(channel.id, query: _query),
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.only(bottom: PrivioSpacing.xxl),
              children: [
                PrivioSearchField(
                  controller: _search,
                  hintText: 'Search subscribers',
                  onChanged: _onQuery,
                ),
                if (mayManage) ...[
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: PrivioSpacing.gutter),
                    child: _Card(
                      children: [
                        ListTile(
                          leading: const Icon(
                            Icons.person_add_alt_1_rounded,
                            color: PrivioColors.accent,
                          ),
                          title: const Text(
                            'Add subscribers',
                            style: TextStyle(color: PrivioColors.accent),
                          ),
                          onTap: () => unawaited(_add()),
                        ),
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
                      'Only channel administrators see this list.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: PrivioColors.textSecondary),
                    ),
                  ),
                ] else
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: PrivioSpacing.xl,
                      vertical: PrivioSpacing.sm,
                    ),
                    child: Text(
                      complete
                          ? 'Everybody in this channel.'
                          : 'This is not the whole list. Only channel '
                              'administrators can see who is subscribed — what '
                              'you see here is the people running it, and you.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: PrivioColors.textSecondary),
                    ),
                  ),

                if (members.isEmpty && !controller.loading)
                  const Padding(
                    padding: EdgeInsets.all(PrivioSpacing.xxl),
                    child: Center(
                      child: Text(
                        'Nobody found.',
                        style: TextStyle(color: PrivioColors.textTertiary),
                      ),
                    ),
                  ),

                if (contacts.isNotEmpty) ...[
                  const _SectionLabel(text: 'CONTACTS IN THIS CHANNEL'),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: PrivioSpacing.gutter),
                    child: _Card(
                      children: [
                        for (var i = 0; i < contacts.length; i++) ...[
                          if (i > 0) const _Hairline(),
                          _MemberRow(
                            member: contacts[i],
                            editing: _editing && mayManage,
                            silenced: controller
                                .bansIn(channel.id)
                                .any((b) => b.accountId == contacts[i].id),
                            onTap: mayManage ? () => unawaited(_actOn(contacts[i])) : null,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],

                if (others.isNotEmpty) ...[
                  _SectionLabel(text: contacts.isEmpty ? 'SUBSCRIBERS' : 'OTHER SUBSCRIBERS'),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: PrivioSpacing.gutter),
                    child: _Card(
                      children: [
                        for (var i = 0; i < others.length; i++) ...[
                          if (i > 0) const _Hairline(),
                          _MemberRow(
                            member: others[i],
                            editing: _editing && mayManage,
                            silenced: controller
                                .bansIn(channel.id)
                                .any((b) => b.accountId == others[i].id),
                            onTap: mayManage ? () => unawaited(_actOn(others[i])) : null,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],

                if (controller.hasMoreMembers(channel.id))
                  const Padding(
                    padding: EdgeInsets.all(PrivioSpacing.xl),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(
          PrivioSpacing.xl,
          PrivioSpacing.lg,
          PrivioSpacing.xl,
          PrivioSpacing.sm,
        ),
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: PrivioColors.textSecondary, letterSpacing: 0.6),
        ),
      );
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.editing,
    required this.silenced,
    this.onTap,
  });

  final ChannelMember member;
  final bool editing;
  final bool silenced;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final presence = member.presenceLabel();
    return ListTile(
      onTap: onTap,
      leading: PrivioAvatar(label: member.label, size: 40),
      title: Text(member.label),
      // Nothing rather than a guess where they do not share it: not knowing is
      // not the same as knowing it was a long time ago.
      subtitle: silenced
          ? const Text('Silenced', style: TextStyle(color: PrivioColors.warning))
          : presence.isEmpty
              ? null
              : Text(
                  presence,
                  style: TextStyle(
                    color: presence == 'online'
                        ? PrivioColors.accent
                        : PrivioColors.textSecondary,
                  ),
                ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (member.isAdmin) _RoleBadge(owner: member.isOwner),
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
    final colour = owner ? const Color(0xFFA855F7) : PrivioColors.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(owner ? 'Owner' : 'Admin', style: TextStyle(color: colour, fontSize: 12)),
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

/// Choose several people at once.
class _PickPeopleSheet extends StatefulWidget {
  const _PickPeopleSheet({required this.people});

  final List<({String id, String label})> people;

  @override
  State<_PickPeopleSheet> createState() => _PickPeopleSheetState();
}

class _PickPeopleSheetState extends State<_PickPeopleSheet> {
  final Set<String> _chosen = {};

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(PrivioSpacing.gutter),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Add subscribers',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  TextButton(
                    onPressed: _chosen.isEmpty
                        ? null
                        : () => Navigator.of(context).pop(_chosen.toList()),
                    child: Text('Add ${_chosen.length}'),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  if (widget.people.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(PrivioSpacing.xl),
                      child: Text(
                        'Everybody in your contacts is already here.',
                        style: TextStyle(color: PrivioColors.textTertiary),
                      ),
                    ),
                  for (final person in widget.people)
                    CheckboxListTile(
                      value: _chosen.contains(person.id),
                      title: Text(person.label),
                      onChanged: (on) => setState(() {
                        if (on ?? false) {
                          _chosen.add(person.id);
                        } else {
                          _chosen.remove(person.id);
                        }
                      }),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
}
