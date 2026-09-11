import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../core/app_state.dart';
import '../models/channel.dart';
import '../theme/privio_colors.dart';
import 'channel_members_screen.dart';
import 'channel_profile_screen.dart';
import 'channel_thread_screen.dart';
import '../widgets/channel_avatar.dart';
import '../widgets/linked_text.dart';
import '../widgets/privio_back_button.dart';

/// One channel's feed.
///
/// Posts are decrypted on this device with the channel key. A post that will
/// not open is shown as a padlock rather than dropped: a reader who is missing
/// the key should see that something is there and that they cannot read it,
/// which is a different problem from an empty channel.
class ChannelFeedScreen extends StatefulWidget {
  const ChannelFeedScreen({required this.channel, super.key});

  final ChannelInfo channel;

  @override
  State<ChannelFeedScreen> createState() => _ChannelFeedScreenState();
}

class _ChannelFeedScreenState extends State<ChannelFeedScreen> {
  final TextEditingController _composer = TextEditingController();
  final TextEditingController _search = TextEditingController();
  late ChannelInfo _channel = widget.channel;
  bool _sending = false;

  /// Drives the one jump this screen makes on its own: onto the newest post
  /// when the feed first arrives.
  final ItemScrollController _scroll = ItemScrollController();

  /// Whether that jump has happened. A feed that re-landed on every rebuild
  /// would yank the reader back down the moment anybody posted.
  bool _landed = false;

  /// The in-channel search, or null when the search bar is closed.
  ///
  /// Local, and it has to be: the posts are sealed on the server, so the only
  /// place a word can be looked for is among the ones this device has already
  /// opened. That is also the honest limit — see the empty state.
  String? _query;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _composer.dispose();
    _search.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      if (_query == null) {
        _query = '';
      } else {
        _query = null;
        _search.clear();
      }
    });
  }

  /// The feed as it is drawn: oldest at the top, newest at the bottom, with the
  /// date above the first post of each day.
  ///
  /// The controller hands them over newest-first, because that is the order the
  /// server pages through them in. Reading them is the other way round.
  List<_FeedEntry> _entries(List<ChannelPost> newestFirst) {
    final query = _query?.trim().toLowerCase() ?? '';
    final entries = <_FeedEntry>[];
    DateTime? lastDay;

    for (final post in newestFirst.reversed) {
      // A post nobody on this device can open has no text to match, and
      // silently dropping it from a search would suggest it was not there.
      if (query.isNotEmpty && !post.body.toLowerCase().contains(query)) continue;
      final day = DateUtils.dateOnly(post.createdAt);
      if (lastDay == null || day != lastDay) entries.add(_FeedEntry.day(day));
      entries.add(_FeedEntry.post(post));
      lastDay = day;
    }
    return entries;
  }

  /// Puts the first paint on the newest post rather than at the top of the
  /// history, once, when there is something to land on.
  void _landOnNewest(int count) {
    if (_landed || count == 0) return;
    _landed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.isAttached) return;
      _scroll.jumpTo(index: count - 1);
    });
  }

  /// Marks the channel read, once its posts are on screen.
  ///
  /// Sent to the server rather than kept here, so reading a channel on a phone
  /// clears its badge on a laptop. The server refuses to move the marker
  /// backwards, so a device that has been offline cannot un-read something.
  Future<void> _markRead() async {
    if (!mounted) return;
    await PrivioScope.of(context).channels.markRead(_channel.id);
  }

  Future<void> _load() async {
    final controller = PrivioScope.of(context).channels;
    if (_channel.isMember) await controller.loadPosts(_channel.id);
    final fresh = controller.channelById(_channel.id);
    if (fresh != null && mounted) setState(() => _channel = fresh);
    // A channel reached by a link is in neither list, so nothing has fetched
    // its picture yet. Unawaited: the feed should not wait on an image.
    unawaited(controller.loadAvatars([fresh ?? _channel]));
    // Opening a channel is reading it. Unawaited for the same reason: the badge
    // clearing is not something the feed should wait on.
    if (_channel.isMember) unawaited(_markRead());
  }

  /// Presses the key delivery again, and says what happened.
  ///
  /// Silence would be the worst answer here: the state this fixes already looks
  /// like nothing is happening, so a retry that also looks like nothing is
  /// indistinguishable from a broken button.
  Future<void> _retryKey(String channelId) async {
    final controller = PrivioScope.of(context).channels;
    final ok = await controller.retryKey(channelId);
    if (!mounted) return;
    final fresh = controller.channelById(channelId);
    if (fresh != null) setState(() => _channel = fresh);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          !ok
              ? controller.error ?? 'Could not ask for the key.'
              : fresh?.hasCurrentKey ?? false
                  ? 'The key arrived. You can post again.'
                  : 'Asked again. The key is delivered by another member, so it '
                      'arrives when one of them is online.',
        ),
      ),
    );
  }

  Future<void> _join() async {
    final controller = PrivioScope.of(context).channels;
    final ok = await controller.join(_channel);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(controller.error ?? 'Could not join')),
      );
      return;
    }
    final joined = controller.channelById(_channel.id);
    if (joined != null) setState(() => _channel = joined);
    await _load();
  }

  /// The file waiting to go with the next post, if any.
  ChannelUpload? _pending;

  /// Picks a file for the next post.
  ///
  /// Nothing is uploaded here. The bytes wait in memory until the post is
  /// published, because that is when the channel key is read — and reading it
  /// any earlier would risk sealing under a key that has since been rotated.
  Future<void> _attach() async {
    PlatformFile? picked;
    try {
      picked = await FilePicker.pickFile().timeout(const Duration(minutes: 2));
    } on Object catch (failure) {
      if (mounted) _say('Could not open the picker: $failure');
      return;
    }
    if (picked == null || !mounted) return;
    final Uint8List bytes;
    try {
      bytes = await picked.readAsBytes();
    } on Object catch (failure) {
      if (mounted) _say('Could not read ${picked.name}: $failure');
      return;
    }
    if (!mounted) return;
    setState(
      () => _pending = ChannelUpload(bytes: bytes, name: picked!.name),
    );
  }

  void _say(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  /// Asks for a day and a time, and publishes then instead of now.
  ///
  /// Two pickers rather than one, because Flutter ships one of each and a
  /// third-party combined one is a dependency for something that takes two
  /// taps. A time already past on the chosen day is refused here rather than
  /// silently becoming "now" on the server.
  Future<DateTime?> _askWhen() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 1, now.month, now.day),
    );
    if (day == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
    );
    if (time == null || !mounted) return null;

    final when = DateTime(day.year, day.month, day.day, time.hour, time.minute);
    if (!when.isAfter(now)) {
      _say('Pick a time that has not gone yet.');
      return null;
    }
    return when;
  }

  /// Asks the question, then publishes it as a post.
  ///
  /// The question and the answers go inside the sealed payload with the post's
  /// text. What reaches the server is three numbers: how many options, how many
  /// may be picked, when it closes.
  Future<void> _poll() async {
    final draft = await showDialog<ChannelPollDraft>(
      context: context,
      builder: (_) => const _NewPollDialog(),
    );
    if (draft == null || !mounted) return;

    setState(() => _sending = true);
    final controller = PrivioScope.of(context).channels;
    final ok = await controller.publish(_channel.id, '', poll: draft);
    if (!mounted) return;
    setState(() => _sending = false);
    if (!ok) _say(controller.error ?? 'Could not publish that poll.');
  }

  Future<void> _schedule() async {
    final when = await _askWhen();
    if (when == null) return;
    await _publish(publishAt: when);
  }

  Future<void> _publish({DateTime? publishAt}) async {
    final text = _composer.text.trim();
    // A picture with no caption is a post; an empty box is not.
    if (text.isEmpty && _pending == null) return;

    setState(() => _sending = true);
    final controller = PrivioScope.of(context).channels;
    final ok = await controller.publish(
      _channel.id,
      text,
      file: _pending,
      publishAt: publishAt,
    );
    if (!mounted) return;
    setState(() => _sending = false);

    if (ok) {
      _composer.clear();
      setState(() => _pending = null);
      if (publishAt != null) {
        // It is not in the feed, so without this the send looks like it failed.
        _say('Scheduled for ${_whenLabel(publishAt)}. It is under "Scheduled" '
            'until then.');
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(controller.error ?? 'Could not publish')),
      );
    }
  }

  Future<void> _share() async {
    final controller = PrivioScope.of(context).channels;

    final link = controller.inviteLink(_channel);
    if (!mounted) return;

    if (link == null) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _InviteDialog(
        link: link,
        channel: _channel,
        // Only somebody who decides who is in the channel gets to change what
        // the standing offer of membership does.
        onManage: _channel.permissions.canManageMembers ? _manageInvite : null,
      ),
    );
    if (mounted) await _load();
  }

  /// Changing what the link does, or replacing it.
  Future<void> _manageInvite() async {
    final controller = PrivioScope.of(context).channels;
    final action = await showModalBottomSheet<_InviteAction>(
      context: context,
      backgroundColor: PrivioColors.surface,
      isScrollControlled: true,
      builder: (_) => _InviteSettingsSheet(channel: _channel),
    );
    if (action == null || !mounted) return;

    final ok = action.rotate
        ? await controller.rotateInvite(_channel.id)
        : await controller.setInviteSettings(
            _channel.id,
            expiresAt: action.expiresAt,
            clearExpiry: action.clearExpiry,
            maxUses: action.maxUses,
            clearMaxUses: action.clearMaxUses,
            needsApproval: action.needsApproval,
          );
    if (!mounted) return;
    final fresh = controller.channelById(_channel.id);
    if (fresh != null) setState(() => _channel = fresh);
    _say(
      !ok
          ? controller.error ?? 'Could not change the link.'
          : action.rotate
              ? 'The old link is dead. Anyone holding it will need the new one.'
              : 'Saved.',
    );
  }

  /// Who is waiting at the door.
  Future<void> _openJoinRequests() async {
    final controller = PrivioScope.of(context).channels;
    await controller.loadJoinRequests(_channel.id);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _JoinRequestsScreen(channel: _channel),
      ),
    );
    if (mounted) await _load();
  }

  /// Lets an admin choose what the bar under a post offers.
  Future<void> _editReactions() async {
    final controller = PrivioScope.of(context).channels;
    final chosen = await showDialog<List<String>>(
      context: context,
      builder: (_) => _ReactionSetDialog(current: _channel.reactionEmojis),
    );
    if (chosen == null || !mounted) return;

    final ok = await controller.setReactionEmojis(_channel.id, chosen);
    if (!mounted) return;
    final fresh = controller.channelById(_channel.id);
    if (fresh != null) setState(() => _channel = fresh);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(controller.error ?? 'Could not change the reactions.')),
      );
    }
  }

  /// Rewrites one of this account's own posts.
  ///
  /// Only the author's: the server refuses anybody else, and the menu does not
  /// offer it. Every post carries a name, so editing somebody else's would be
  /// putting words in their mouth under their own byline.
  Future<void> _edit(ChannelPost post) async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => _EditPostDialog(post: post),
    );
    if (text == null || !mounted) return;

    final controller = PrivioScope.of(context).channels;
    final ok = await controller.editPost(_channel.id, post, text);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(controller.error ?? 'Could not change the post.')),
      );
    }
  }

  /// Publishes something that was waiting, straight away.
  Future<void> _publishNow(ChannelPost post) async {
    final controller = PrivioScope.of(context).channels;
    final ok = await controller.editPost(
      _channel.id,
      post,
      post.body,
      clearSchedule: true,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Published.' : controller.error ?? 'Could not publish it.'),
      ),
    );
  }

  /// The waiting room: what this account has queued and when it goes out.
  Future<void> _openScheduled() async {
    final controller = PrivioScope.of(context).channels;
    await controller.loadScheduled(_channel.id);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ScheduledScreen(
          channel: _channel,
          onPublishNow: _publishNow,
          onDelete: (post) => controller.deletePost(_channel.id, post.id),
        ),
      ),
    );
    if (mounted) await _load();
  }

  /// Turns threads under posts on or off for the whole channel.
  ///
  /// Turning them off hides the threads rather than deleting them — somebody
  /// who changes their mind twice should not have destroyed a conversation in
  /// between.
  Future<void> _toggleComments() async {
    final controller = PrivioScope.of(context).channels;
    final turningOn = !_channel.commentsEnabled;
    final ok = await controller.setCommentsEnabled(_channel.id, enabled: turningOn);
    if (!mounted) return;
    final fresh = controller.channelById(_channel.id);
    if (fresh != null) setState(() => _channel = fresh);
    _say(
      !ok
          ? controller.error ?? 'Could not change that.'
          : turningOn
              ? 'Readers can comment on posts now.'
              : 'Comments are off. Existing threads are hidden, not deleted.',
    );
  }

  void _openThread(ChannelPost post) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChannelThreadScreen(channel: _channel, post: post),
      ),
    );
  }

  Future<void> _openStats() async {
    final controller = PrivioScope.of(context).channels;
    await controller.loadStats(_channel.id);
    if (!mounted) return;
    final stats = controller.statsFor(_channel.id);
    if (stats == null) {
      _say(controller.error ?? 'Could not read the numbers.');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: PrivioColors.surface,
      isScrollControlled: true,
      builder: (_) => _StatsSheet(stats: stats),
    );
  }

  /// Hands the channel to another member.
  ///
  /// Two steps on purpose: who, then the password. The owner cannot undo this
  /// afterwards — they will be an admin in somebody else's channel — so a
  /// single tap is not enough, and neither is an unlocked phone.
  Future<void> _transfer() async {
    final controller = PrivioScope.of(context).channels;
    await controller.loadMembers(_channel.id);
    if (!mounted) return;

    final candidates = [
      for (final member in controller.membersOf(_channel.id))
        if (!member.isOwner) member,
    ];
    if (candidates.isEmpty) {
      _say('There is nobody else in this channel to hand it to.');
      return;
    }

    final chosen = await showModalBottomSheet<ChannelMember>(
      context: context,
      backgroundColor: PrivioColors.surface,
      isScrollControlled: true,
      builder: (_) => _PickNewOwnerSheet(members: candidates),
    );
    if (chosen == null || !mounted) return;

    final password = await showDialog<String>(
      context: context,
      builder: (_) => _ConfirmTransferDialog(member: chosen),
    );
    if (password == null || password.isEmpty || !mounted) return;

    final ok = await controller.transfer(
      channelId: _channel.id,
      toAccountId: chosen.id,
      currentPassword: password,
    );
    if (!mounted) return;
    final fresh = controller.channelById(_channel.id);
    if (fresh != null) setState(() => _channel = fresh);
    _say(
      ok
          ? '${chosen.label} owns this channel now. You are an admin in it.'
          : controller.error ?? 'Could not hand the channel on.',
    );
  }

  Future<void> _report() async {
    final reason = await showModalBottomSheet<ChannelReportReason>(
      context: context,
      backgroundColor: PrivioColors.surface,
      isScrollControlled: true,
      builder: (_) => _ReportSheet(channel: _channel),
    );
    if (reason == null || !mounted) return;

    final controller = PrivioScope.of(context).channels;
    final ok = await controller.report(_channel.id, reason);
    if (!mounted) return;
    _say(ok ? 'Reported. Thank you.' : controller.error ?? 'Could not send that.');
  }

  /// Gives the channel a picture, or takes the one it has away.
  ///
  /// Which of the two is offered depends on whether there is one, so a channel
  /// with no picture is not asked whether to remove it.
  Future<void> _editPicture() async {
    final channel = PrivioScope.of(context).channels.channelById(_channel.id) ?? _channel;
    if (!channel.hasAvatar) {
      await _pickPicture();
      return;
    }

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: PrivioColors.surfaceRaised,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Change picture'),
              onTap: () => Navigator.of(sheetContext).pop('change'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: PrivioColors.danger),
              title: const Text(
                'Remove picture',
                style: TextStyle(color: PrivioColors.danger),
              ),
              onTap: () => Navigator.of(sheetContext).pop('remove'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'change') {
      await _pickPicture();
      return;
    }

    final controller = PrivioScope.of(context).channels;
    final ok = await controller.clearAvatar(channel);
    if (!mounted) return;
    if (ok) {
      final updated = controller.lastAvatarChange;
      if (updated != null) setState(() => _channel = updated);
    }
    _say(ok ? 'Picture removed.' : controller.error ?? 'Could not remove the picture.');
  }

  Future<void> _pickPicture() async {
    PlatformFile? picked;
    try {
      picked = await FilePicker.pickFile(
        type: FileType.image,
      ).timeout(const Duration(minutes: 2));
    } on Object catch (failure) {
      if (mounted) _say('Could not open the picker: $failure');
      return;
    }
    if (picked == null || !mounted) return;

    final Uint8List bytes;
    try {
      bytes = await picked.readAsBytes();
    } on Object catch (failure) {
      if (mounted) _say('Could not read ${picked.name}: $failure');
      return;
    }
    if (!mounted) return;

    final controller = PrivioScope.of(context).channels;
    final channel = controller.channelById(_channel.id) ?? _channel;
    // A public channel's picture is not sealed — it is drawn on the invite page
    // and inside whatever messenger the link was pasted into, where nobody
    // holds a key. That is a real difference from everything else in this app
    // and it is said once, here, before it happens rather than after.
    if (channel.isPublic) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: PrivioColors.surfaceRaised,
          title: const Text('This picture will be public'),
          content: const Text(
            'A public channel\'s picture is shown on its web page and in link '
            'previews, so it is stored unencrypted — the same as its name, '
            'handle and description. Posts stay end-to-end encrypted.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Use it'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    final ok = await controller.setAvatar(channel, bytes);
    if (!mounted) return;
    if (!ok) {
      _say(controller.error ?? 'Could not set the picture.');
      return;
    }
    // Adopt the channel the controller handed back, the same way leaving,
    // joining and renaming already do. This screen keeps its own copy, and
    // without this line a picture that uploaded perfectly well went on showing
    // the placeholder — which is indistinguishable from a failure.
    final updated = controller.lastAvatarChange;
    if (updated != null) setState(() => _channel = updated);
    // Said out loud, because the whole failure mode here was silence.
    _say('Channel picture updated.');
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PrivioColors.surfaceRaised,
        title: const Text('Delete channel?'),
        content: const Text(
          'The channel and every post in it are removed for everyone. '
          'Nothing undoes this.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: PrivioColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final controller = PrivioScope.of(context).channels;
    final ok = await controller.delete(_channel.id);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(controller.error ?? 'Could not delete the channel')),
      );
    }
  }

  Future<void> _leave() async {
    final controller = PrivioScope.of(context).channels;
    final ok = await controller.leave(_channel.id);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(controller.error ?? 'Could not leave the channel')),
      );
    }
  }

  Future<void> _openMembers() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ChannelMembersScreen(channel: _channel)),
    );
  }

  /// The channel's own page, and what it hands back.
  ///
  /// The profile screen does not duplicate the sheets that already live here —
  /// invites, statistics, reporting, reactions — it pops with a name and this
  /// opens the one that exists. Two copies of a confirmation dialog are two
  /// chances for them to say different things, and the one that drifts is the
  /// one nobody is looking at.
  Future<void> _openProfile() async {
    final asked = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => ChannelProfileScreen(channel: _channel)),
    );
    if (!mounted) return;
    switch (asked) {
      case 'left':
        Navigator.of(context).pop();
      case 'search':
        _toggleSearch();
      case 'invite':
        await _manageInvite();
      case 'stats':
        await _openStats();
      case 'report':
        await _report();
      case 'reactions':
        await _editReactions();
      case 'transfer':
        await _transfer();
      case final jump? when jump.startsWith('post:'):
        // A link opened from the profile, jumped to where it was written.
        final id = int.tryParse(jump.substring(5));
        if (id != null) _jumpToPost(id);
      default:
        await _load();
    }
  }

  /// Scrolls the feed to one post, by id.
  void _jumpToPost(int postId) {
    final entries = _entries(PrivioScope.of(context).channels.postsIn(_channel.id));
    final index = entries.indexWhere((entry) => entry.post?.id == postId);
    if (index >= 0) _scroll.jumpTo(index: index);
  }

  void _onMenu(String action) {
    switch (action) {
      case 'profile':
        unawaited(_openProfile());
      case 'invite':
        _share();
      case 'picture':
        _editPicture();
      case 'reactions':
        _editReactions();
      case 'comments':
        _toggleComments();
      case 'scheduled':
        _openScheduled();
      case 'requests':
        _openJoinRequests();
      case 'stats':
        _openStats();
      case 'transfer':
        _transfer();
      case 'report':
        _report();
      case 'members':
        _openMembers();
      case 'leave':
        _leave();
      case 'delete':
        _confirmDelete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = PrivioScope.of(context);
    final controller = state.channels;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        // Re-read on every build: a key can arrive while this screen is open,
        // and the padlocks should clear where the reader is already looking.
        final channel = controller.channelById(_channel.id) ?? _channel;
        final posts = controller.postsIn(channel.id);
        final canPost = channel.permissions.canPost;

        return Scaffold(
          appBar: AppBar(
            leading: const PrivioBackButton(),
            titleSpacing: 0,
            // The whole header opens the channel's own page — its picture, its
            // link, who is in it, what it holds. Tapping a header is where
            // people look for that first, and until this line existed the four
            // screens behind it shipped in the binary with nothing to open them.
            title: GestureDetector(
              onTap: () => unawaited(_openProfile()),
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  ChannelAvatar(
                    channel: channel,
                    imageBytes: controller.avatarFor(channel),
                    size: 36,
                  ),
                  const SizedBox(width: PrivioSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          channel.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                '${channel.isPublic ? 'Public' : 'Private'} · '
                                '${channel.memberLabel}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            if (channel.muted)
                              const Padding(
                                padding: EdgeInsets.only(left: PrivioSpacing.xs),
                                child: Icon(
                                  Icons.notifications_off_rounded,
                                  size: 12,
                                  color: PrivioColors.textTertiary,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              if (channel.isMember)
                IconButton(
                  onPressed: _toggleSearch,
                  icon: Icon(_query == null ? Icons.search_rounded : Icons.close_rounded),
                  tooltip: _query == null ? 'Search this channel' : 'Close search',
                ),
              if (channel.isMember)
                PopupMenuButton<String>(
                  onSelected: _onMenu,
                  color: PrivioColors.surfaceRaised,
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'profile', child: Text('Channel info')),
                    if (channel.inviteCode != null)
                      const PopupMenuItem(value: 'invite', child: Text('Invite link')),
                    if (channel.permissions.canPost)
                      const PopupMenuItem(value: 'scheduled', child: Text('Scheduled')),
                    if (channel.permissions.canManageMembers && channel.invite.needsApproval)
                      const PopupMenuItem(
                        value: 'requests',
                        child: Text('Requests to join'),
                      ),
                    if (channel.permissions.canEditChannel)
                      PopupMenuItem(
                        value: 'picture',
                        child: Text(
                          channel.hasAvatar ? 'Channel picture' : 'Add a picture',
                        ),
                      ),
                    if (channel.permissions.canEditChannel)
                      const PopupMenuItem(value: 'reactions', child: Text('Reactions')),
                    if (channel.permissions.canEditChannel)
                      PopupMenuItem(
                        value: 'comments',
                        child: Text(
                          channel.commentsEnabled ? 'Turn comments off' : 'Turn comments on',
                        ),
                      ),
                    const PopupMenuItem(value: 'members', child: Text('Members')),
                    if (channel.permissions.canEditChannel)
                      const PopupMenuItem(value: 'stats', child: Text('Statistics')),
                    if (channel.role == 'owner')
                      const PopupMenuItem(
                        value: 'transfer',
                        child: Text('Hand this channel on'),
                      ),
                    if (channel.isMember && channel.role != 'owner')
                      const PopupMenuItem(value: 'report', child: Text('Report channel')),
                    if (channel.role != 'owner')
                      const PopupMenuItem(value: 'leave', child: Text('Leave channel')),
                    if (channel.permissions.canDeleteChannel)
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete channel', style: TextStyle(color: PrivioColors.danger)),
                      ),
                  ],
                ),
              const SizedBox(width: PrivioSpacing.xs),
            ],
          ),
          body: Column(
            children: [
              if (_query != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    PrivioSpacing.gutter,
                    PrivioSpacing.sm,
                    PrivioSpacing.gutter,
                    0,
                  ),
                  child: TextField(
                    controller: _search,
                    autofocus: true,
                    onChanged: (value) => setState(() => _query = value),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded, size: 18),
                      hintText: 'Search posts you can read',
                      isDense: true,
                    ),
                  ),
                ),
              if (channel.isMember && !channel.hasCurrentKey)
                _MissingKeyBanner(
                  // Two different situations behind one padlock, and the
                  // difference decides whether waiting is any use: a device
                  // that has never had a key is waiting for a first delivery,
                  // while one that holds older versions is waiting for a
                  // rotation somebody set off by leaving or being removed.
                  rotating: channel.hasKey,
                  epoch: channel.keyEpoch,
                  onRetry: () => _retryKey(channel.id),
                ),
              Expanded(
                child: Builder(
                  builder: (context) {
                    if (!channel.isMember) {
                      return _JoinPrompt(channel: channel, onJoin: _join);
                    }
                    if (posts.isEmpty) return const _EmptyFeed();

                    final entries = _entries(posts);
                    if (entries.isEmpty) return const _NoSearchResults();
                    _landOnNewest(entries.length);

                    return RefreshIndicator(
                      color: PrivioColors.accent,
                      backgroundColor: PrivioColors.surface,
                      onRefresh: () => controller.loadPosts(channel.id),
                      child: ScrollablePositionedList.builder(
                        itemScrollController: _scroll,
                        padding: const EdgeInsets.all(PrivioSpacing.gutter),
                        itemCount: entries.length,
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          final post = entry.post;
                          if (post == null) return _DayDivider(day: entry.day!);
                          return _PostCard(
                            post: post,
                            channel: channel,
                            mine: post.authorUsername != null &&
                                post.authorUsername == state.username,
                            onEdit: () => _edit(post),
                            onOpenThread: () => _openThread(post),
                            onVote: (options) =>
                                controller.vote(channel.id, post.id, options),
                            onReact: (emoji, {required bool on}) =>
                                controller.react(channel.id, post.id, emoji, on: on),
                            onPin: () => controller.pin(
                              channel.id,
                              post.id,
                              pinned: !post.pinned,
                            ),
                            onDelete: () => controller.deletePost(channel.id, post.id),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
              if (channel.isMember && canPost)
                _Composer(
                  controller: _composer,
                  sending: _sending,
                  pending: _pending,
                  onAttach: _attach,
                  onSchedule: _schedule,
                  onPoll: _poll,
                  onDropAttachment: () => setState(() => _pending = null),
                  // Never the old key. Posting under a superseded version is
                  // exactly what a rotation exists to prevent, and the server
                  // would refuse it anyway — so the composer says why instead
                  // of failing on send.
                  enabled: channel.hasCurrentKey,
                  onSend: _publish,
                ),
            ],
          ),
        );
      },
    );
  }
}

/// One row of the feed: either a post, or the date above the first post of a
/// day.
///
/// Flattened into a single list rather than grouped, because the list has to
/// be able to say what is at index N — that is what puts the first paint on
/// the newest post instead of at the top of the history.
class _FeedEntry {
  const _FeedEntry.post(ChannelPost this.post) : day = null;
  const _FeedEntry.day(DateTime this.day) : post = null;

  final ChannelPost? post;
  final DateTime? day;
}

/// "Today", "Yesterday", or the date.
class _DayDivider extends StatelessWidget {
  const _DayDivider({required this.day});

  final DateTime day;

  static const List<String> _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  String get _label {
    final today = DateUtils.dateOnly(DateTime.now());
    final difference = today.difference(day).inDays;
    if (difference == 0) return 'Today';
    if (difference == 1) return 'Yesterday';
    final month = _months[day.month - 1];
    // The year only where it is not this one: a feed of last week's posts does
    // not need telling which year it is.
    return day.year == today.year
        ? '${day.day} $month'
        : '${day.day} $month ${day.year}';
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: PrivioSpacing.md),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: PrivioSpacing.md,
              vertical: PrivioSpacing.xs,
            ),
            decoration: const BoxDecoration(
              color: PrivioColors.surfaceRaised,
              borderRadius: BorderRadius.all(PrivioRadius.pill),
            ),
            child: Text(_label, style: Theme.of(context).textTheme.bodySmall),
          ),
        ),
      );
}

/// What a search that found nothing says.
///
/// It says where it looked, because the limit is real and not obvious: the
/// server holds the posts sealed, so the only text there is to search is what
/// this device has already opened and downloaded.
class _NoSearchResults extends StatelessWidget {
  const _NoSearchResults();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off_rounded, size: 40, color: PrivioColors.textTertiary),
            const SizedBox(height: PrivioSpacing.md),
            Text('Nothing matches', style: theme.textTheme.titleMedium),
            const SizedBox(height: PrivioSpacing.xs),
            Text(
              'The search runs on this device, over the posts it has already '
              'loaded and could open. The server cannot search them: it holds '
              'them sealed.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _PostCard extends StatelessWidget {
  const _PostCard({
    required this.post,
    required this.channel,
    required this.onPin,
    required this.onDelete,
    required this.onReact,
    required this.onEdit,
    required this.onOpenThread,
    required this.onVote,
    required this.mine,
  });

  final ChannelPost post;
  final ChannelInfo channel;
  final VoidCallback onPin;
  final VoidCallback onDelete;

  /// Rewrites it. Offered only on this account's own posts, because that is
  /// the only case the server will accept.
  final VoidCallback onEdit;

  /// Opens the thread under it. Only reachable where the channel has threads.
  final VoidCallback onOpenThread;

  /// Sends this account's whole answer to the poll on it.
  final Future<bool> Function(List<int>) onVote;

  /// Whether this account wrote it.
  final bool mine;

  /// Adds or removes this account's reaction.
  final Future<bool> Function(String emoji, {required bool on}) onReact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canModerate = channel.permissions.canEditChannel ||
        channel.permissions.canDeletePosts ||
        (mine && channel.permissions.canPost);

    return Container(
      margin: const EdgeInsets.only(bottom: PrivioSpacing.md),
      padding: const EdgeInsets.all(PrivioSpacing.lg),
      decoration: BoxDecoration(
        color: PrivioColors.surfaceRaised,
        borderRadius: const BorderRadius.all(PrivioRadius.card),
        border: post.pinned
            ? Border.all(color: PrivioColors.accentDim)
            : Border.all(color: PrivioColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (post.pinned) ...[
                const Icon(Icons.push_pin_rounded, size: 14, color: PrivioColors.accent),
                const SizedBox(width: PrivioSpacing.xs),
              ],
              Expanded(
                child: Text(
                  post.authorUsername ?? 'Unknown',
                  style: theme.textTheme.labelLarge?.copyWith(color: PrivioColors.accentBright),
                ),
              ),
              Text(_formatTime(post.createdAt), style: theme.textTheme.bodySmall),
              // Said plainly rather than hidden: a reader who saw the first
              // version is entitled to know it is not the one in front of them.
              if (post.isEdited) ...[
                const SizedBox(width: PrivioSpacing.xs),
                Text('· edited', style: theme.textTheme.bodySmall),
              ],
              if (canModerate)
                PopupMenuButton<String>(
                  color: PrivioColors.surfaceHigh,
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.more_horiz_rounded, size: 18),
                  onSelected: (value) => switch (value) {
                    'pin' => onPin(),
                    'edit' => onEdit(),
                    _ => onDelete(),
                  },
                  itemBuilder: (_) => [
                    if (mine && channel.permissions.canPost)
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    if (channel.permissions.canEditChannel)
                      PopupMenuItem(value: 'pin', child: Text(post.pinned ? 'Unpin' : 'Pin')),
                    if (channel.permissions.canDeletePosts)
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete', style: TextStyle(color: PrivioColors.danger)),
                      ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: PrivioSpacing.sm),
          if (post.opened) ...[
            if (post.body.isNotEmpty)
              // Links are tappable, and nothing opens without being confirmed:
              // a channel is somebody else's text, and a tap that leaves for
              // the browser unannounced is not a thing a reader agreed to.
              LinkedText(post.body, style: theme.textTheme.bodyMedium),
            if (post.attachment != null) ...[
              if (post.body.isNotEmpty) const SizedBox(height: PrivioSpacing.sm),
              _AttachmentTile(channelId: channel.id, post: post),
            ],
            if (post.poll != null) ...[
              if (post.body.isNotEmpty) const SizedBox(height: PrivioSpacing.sm),
              _PollCard(
                poll: post.poll!,
                canVote: channel.isMember,
                onVote: (options) => onVote(options),
              ),
            ],
            // Only under a post this device could open. A padlock with a row
            // of emojis beneath it invites a reaction to something nobody can
            // read, which is not a thing to ask of a reader.
            if (channel.isMember) ...[
              const SizedBox(height: PrivioSpacing.sm),
              _ReactionBar(post: post, channel: channel, onReact: onReact),
            ],
            if (channel.isMember && channel.commentsEnabled) ...[
              const SizedBox(height: PrivioSpacing.xs),
              InkWell(
                onTap: onOpenThread,
                borderRadius: const BorderRadius.all(PrivioRadius.pill),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: PrivioSpacing.sm,
                    vertical: PrivioSpacing.xs,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.mode_comment_outlined,
                        size: 15,
                        color: PrivioColors.textSecondary,
                      ),
                      const SizedBox(width: PrivioSpacing.xs),
                      Text(
                        post.commentCount == 0
                            ? 'Comment'
                            : '${post.commentCount} '
                                'comment${post.commentCount == 1 ? '' : 's'}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ] else
            Row(
              children: [
                const Icon(Icons.lock_rounded, size: 16, color: PrivioColors.textTertiary),
                const SizedBox(width: PrivioSpacing.sm),
                Expanded(
                  child: Text(
                    'Encrypted — this device has no key for it.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  static String _formatTime(DateTime when) {
    final now = DateTime.now();
    final sameDay = when.year == now.year && when.month == now.month && when.day == now.day;
    final hh = when.hour.toString().padLeft(2, '0');
    final mm = when.minute.toString().padLeft(2, '0');
    if (sameDay) return '$hh:$mm';
    return '${when.day}/${when.month} $hh:$mm';
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.enabled,
    required this.onSend,
    this.pending,
    this.onAttach,
    this.onSchedule,
    this.onPoll,
    this.onDropAttachment,
  });

  final TextEditingController controller;
  final bool sending;
  final bool enabled;
  final VoidCallback onSend;

  /// The file that will go with the next post, before it is sealed.
  final ChannelUpload? pending;
  final VoidCallback? onAttach;

  /// Publishes later instead of now. Null hides the button.
  final VoidCallback? onSchedule;

  /// Asks a question instead of making a statement. Null hides the button.
  final VoidCallback? onPoll;
  final VoidCallback? onDropAttachment;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.all(PrivioSpacing.md),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: PrivioColors.border)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // What is about to be sent, so nobody publishes a file they picked
            // and forgot about.
            if (pending != null) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: PrivioSpacing.sm),
                child: Row(
                  children: [
                    const Icon(Icons.attach_file_rounded, size: 16, color: PrivioColors.accent),
                    const SizedBox(width: PrivioSpacing.xs),
                    Expanded(
                      child: Text(
                        '${pending!.name ?? 'File'} · ${_readableSize(pending!.bytes.length)}',
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    IconButton(
                      onPressed: sending ? null : onDropAttachment,
                      icon: const Icon(Icons.close_rounded, size: 16),
                      tooltip: 'Remove the file',
                    ),
                  ],
                ),
              ),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: enabled && !sending ? onAttach : null,
                  icon: const Icon(Icons.attach_file_rounded),
                  tooltip: 'Attach a picture or a file',
                ),
                if (onSchedule != null)
                  IconButton(
                    onPressed: enabled && !sending ? onSchedule : null,
                    icon: const Icon(Icons.schedule_rounded),
                    tooltip: 'Publish later',
                  ),
                if (onPoll != null)
                  IconButton(
                    onPressed: enabled && !sending ? onPoll : null,
                    icon: const Icon(Icons.poll_outlined),
                    tooltip: 'Ask a question',
                  ),
                Expanded(
              child: TextField(
                controller: controller,
                enabled: enabled,
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: enabled ? 'Write a post' : 'No key for this channel',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: PrivioSpacing.sm),
            IconButton.filled(
              onPressed: enabled && !sending ? onSend : null,
              style: IconButton.styleFrom(backgroundColor: PrivioColors.accent),
              icon: sending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded, color: PrivioColors.background, size: 18),
            ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Rewriting a post.
///
/// The attachment is not part of this and the dialog says so: it is already
/// sealed and uploaded, and re-uploading it to change a sentence would spend
/// the author's data allowance twice. Changing the picture means a new post.
class _EditPostDialog extends StatefulWidget {
  const _EditPostDialog({required this.post});

  final ChannelPost post;

  @override
  State<_EditPostDialog> createState() => _EditPostDialogState();
}

class _EditPostDialogState extends State<_EditPostDialog> {
  late final TextEditingController _text = TextEditingController(text: widget.post.body);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      backgroundColor: PrivioColors.surfaceRaised,
      title: const Text('Edit post'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _text,
              autofocus: true,
              minLines: 3,
              maxLines: 10,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Post'),
            ),
            const SizedBox(height: PrivioSpacing.md),
            Text(
              widget.post.isScheduled
                  ? 'Nobody has seen this yet, so it will not be marked as '
                      'edited.'
                  : 'The post will be marked as edited. Its file, if it has '
                      'one, stays as it is.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final text = _text.text.trim();
            // An empty post is a deletion wearing another name, and deletion
            // has its own entry that says what it does.
            if (text.isEmpty) return;
            Navigator.of(context).pop(text);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// What this account has queued, and when each of it goes out.
///
/// Its own screen rather than a section of the feed: the feed is what everyone
/// sees, and a waiting post is not in it for anybody, the author included.
class _ScheduledScreen extends StatelessWidget {
  const _ScheduledScreen({
    required this.channel,
    required this.onPublishNow,
    required this.onDelete,
  });

  final ChannelInfo channel;
  final Future<void> Function(ChannelPost) onPublishNow;
  final Future<void> Function(ChannelPost) onDelete;

  @override
  Widget build(BuildContext context) {
    final controller = PrivioScope.of(context).channels;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final waiting = controller.scheduledIn(channel.id);
        return Scaffold(
          appBar: AppBar(
            leading: const PrivioBackButton(),
            title: const Text('Scheduled'),
          ),
          body: waiting.isEmpty
              ? const _NothingScheduled()
              : ListView.builder(
                  padding: const EdgeInsets.all(PrivioSpacing.gutter),
                  itemCount: waiting.length,
                  itemBuilder: (context, index) {
                    final post = waiting[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: PrivioSpacing.md),
                      padding: const EdgeInsets.all(PrivioSpacing.lg),
                      decoration: BoxDecoration(
                        color: PrivioColors.surfaceRaised,
                        borderRadius: const BorderRadius.all(PrivioRadius.card),
                        border: Border.all(color: PrivioColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.schedule_rounded,
                                size: 14,
                                color: PrivioColors.accent,
                              ),
                              const SizedBox(width: PrivioSpacing.xs),
                              Expanded(
                                child: Text(
                                  post.publishAt == null
                                      ? 'Waiting'
                                      : _whenLabel(post.publishAt!),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: PrivioSpacing.sm),
                          Text(
                            post.opened ? post.body : 'Encrypted — no key on this device.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: PrivioSpacing.sm),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () => onDelete(post),
                                child: const Text(
                                  'Discard',
                                  style: TextStyle(color: PrivioColors.danger),
                                ),
                              ),
                              const SizedBox(width: PrivioSpacing.sm),
                              FilledButton(
                                onPressed: () => onPublishNow(post),
                                child: const Text('Publish now'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}

class _NothingScheduled extends StatelessWidget {
  const _NothingScheduled();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.schedule_rounded, size: 40, color: PrivioColors.textTertiary),
            const SizedBox(height: PrivioSpacing.md),
            Text('Nothing waiting', style: theme.textTheme.titleMedium),
            const SizedBox(height: PrivioSpacing.xs),
            Text(
              'Posts you schedule wait here until their time comes. Nobody '
              'else can see them, or that they exist.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// "Today at 18:30", "Tomorrow at 09:00", or the date.
String _whenLabel(DateTime when) {
  final today = DateUtils.dateOnly(DateTime.now());
  final day = DateUtils.dateOnly(when);
  final hh = when.hour.toString().padLeft(2, '0');
  final mm = when.minute.toString().padLeft(2, '0');
  final difference = day.difference(today).inDays;
  if (difference == 0) return 'today at $hh:$mm';
  if (difference == 1) return 'tomorrow at $hh:$mm';
  return '${when.day}.${when.month}. at $hh:$mm';
}

/// Which emojis a channel offers under its posts.
///
/// A fixed palette rather than a free text field, and that is the security
/// decision rather than a design one: the column behind this is readable by the
/// server, and an unconstrained one would turn the bar under every post into a
/// row of captions an admin writes. The server enforces the same rule, so
/// hiding the field is not what stops it.
///
/// What is already on a post is not touched by a change here.
class _ReactionSetDialog extends StatefulWidget {
  const _ReactionSetDialog({required this.current});

  final List<String> current;

  /// What an admin may choose from. Wide enough to cover what a channel
  /// usually wants, and nothing in it is text.
  static const List<String> palette = [
    '👍', '👎', '❤️', '🔥', '👏', '😂', '😮', '😢',
    '🎉', '🙏', '💯', '🤔', '👀', '✅', '❌', '⭐',
  ];

  /// Twelve already does not fit across a phone.
  static const int limit = 12;

  @override
  State<_ReactionSetDialog> createState() => _ReactionSetDialogState();
}

class _ReactionSetDialogState extends State<_ReactionSetDialog> {
  late final Set<String> _chosen = widget.current.toSet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      backgroundColor: PrivioColors.surfaceRaised,
      title: const Text('Reactions'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'What readers can put under a post. Reactions already on a post '
              'stay, even if you take the emoji off this list.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: PrivioSpacing.md),
            Wrap(
              spacing: PrivioSpacing.xs,
              runSpacing: PrivioSpacing.xs,
              children: [
                for (final emoji in _ReactionSetDialog.palette)
                  _PaletteTile(
                    emoji: emoji,
                    selected: _chosen.contains(emoji),
                    onTap: () => setState(() {
                      if (_chosen.contains(emoji)) {
                        _chosen.remove(emoji);
                      } else if (_chosen.length < _ReactionSetDialog.limit) {
                        _chosen.add(emoji);
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: PrivioSpacing.sm),
            Text(
              '${_chosen.length} of ${_ReactionSetDialog.limit}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          // An empty bar is not a state the server accepts, and it is not one
          // anybody meant to ask for.
          onPressed: _chosen.isEmpty
              ? null
              : () => Navigator.of(context).pop(_chosen.toList()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _PaletteTile extends StatelessWidget {
  const _PaletteTile({
    required this.emoji,
    required this.selected,
    required this.onTap,
  });

  final String emoji;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(PrivioRadius.card),
        child: Container(
          padding: const EdgeInsets.all(PrivioSpacing.sm),
          decoration: BoxDecoration(
            color: selected ? PrivioColors.accentSurface : PrivioColors.surfaceHigh,
            borderRadius: const BorderRadius.all(PrivioRadius.card),
            border: selected ? Border.all(color: PrivioColors.accentDim) : null,
          ),
          child: Text(emoji, style: const TextStyle(fontSize: 22)),
        ),
      );
}

/// A poll under a post: the question, the answers, and the bars.
///
/// The question comes out of the post's sealed payload; the numbers come from
/// the server, which counted them without ever learning what any option says.
/// Nobody is ever shown who voted for what — the server holds that and does not
/// serve it, so there is no list here to open.
class _PollCard extends StatefulWidget {
  const _PollCard({required this.poll, required this.canVote, required this.onVote});

  final ChannelPoll poll;
  final bool canVote;
  final Future<bool> Function(List<int>) onVote;

  @override
  State<_PollCard> createState() => _PollCardState();
}

class _PollCardState extends State<_PollCard> {
  bool _busy = false;

  /// What is selected but not yet sent, in a poll that takes several answers.
  /// Null while nothing has been touched, so the server's own answer shows.
  Set<int>? _draft;

  Set<int> get _selected => _draft ?? widget.poll.myVotes;

  Future<void> _send(List<int> options) async {
    if (_busy) return;
    setState(() => _busy = true);
    await widget.onVote(options);
    // Cleared either way: on success the controller has the server's answer,
    // and on failure a draft left behind would show a vote nobody cast.
    if (mounted) {
      setState(() {
        _busy = false;
        _draft = null;
      });
    }
  }

  void _tap(int index) {
    final poll = widget.poll;
    if (!widget.canVote || poll.isClosed || _busy) return;

    if (!poll.takesSeveral) {
      // One answer: a tap is the whole answer, and tapping the one already
      // chosen takes it back.
      _send(poll.myVotes.contains(index) ? const [] : [index]);
      return;
    }
    final next = {..._selected};
    if (next.contains(index)) {
      next.remove(index);
    } else if (next.length < poll.maxChoices) {
      next.add(index);
    } else {
      return;
    }
    setState(() => _draft = next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final poll = widget.poll;
    final content = poll.content;

    // The shape is known and the question is not: this device has no key for
    // the post. Offering answers nobody can read would be worse than saying so.
    if (content == null) {
      return Container(
        padding: const EdgeInsets.all(PrivioSpacing.md),
        decoration: const BoxDecoration(
          color: PrivioColors.surfaceHigh,
          borderRadius: BorderRadius.all(PrivioRadius.card),
        ),
        child: Row(
          children: [
            const Icon(Icons.lock_rounded, size: 16, color: PrivioColors.textTertiary),
            const SizedBox(width: PrivioSpacing.sm),
            Expanded(
              child: Text(
                'A poll this device has no key for.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      );
    }

    // Results show once this account has answered, or once it can no longer
    // answer. Before that the bars would be an argument rather than a question.
    final showResults = poll.hasVoted || poll.isClosed || !widget.canVote;

    return Container(
      padding: const EdgeInsets.all(PrivioSpacing.md),
      decoration: const BoxDecoration(
        color: PrivioColors.surfaceHigh,
        borderRadius: BorderRadius.all(PrivioRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(content.question, style: theme.textTheme.titleSmall),
          const SizedBox(height: PrivioSpacing.xs),
          Text(
            [
              if (poll.takesSeveral)
                'Pick up to ${poll.maxChoices}'
              else
                'Pick one',
              if (poll.isClosed)
                'closed'
              else if (poll.closesAt != null)
                'closes ${_whenLabel(poll.closesAt!)}',
              '${poll.voters} ${poll.voters == 1 ? 'vote' : 'votes'}',
            ].join(' · '),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: PrivioSpacing.sm),
          for (var index = 0; index < content.options.length; index++)
            _PollOption(
              label: content.options[index],
              count: poll.countFor(index),
              share: poll.shareOf(index),
              chosen: _selected.contains(index),
              showResults: showResults,
              enabled: widget.canVote && !poll.isClosed && !_busy,
              onTap: () => _tap(index),
            ),
          // A poll that takes several answers needs a moment to gather them,
          // so it has a button; a one-answer poll is sent by the tap itself.
          if (poll.takesSeveral && widget.canVote && !poll.isClosed) ...[
            const SizedBox(height: PrivioSpacing.xs),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _busy ? null : () => _send(_selected.toList()),
                child: Text(_selected.isEmpty ? 'Clear my answer' : 'Answer'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PollOption extends StatelessWidget {
  const _PollOption({
    required this.label,
    required this.count,
    required this.share,
    required this.chosen,
    required this.showResults,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final int count;

  /// Against the busiest option, not the total: in a poll that takes several
  /// answers the totals add up to more than the people.
  final double share;
  final bool chosen;
  final bool showResults;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: PrivioSpacing.xs),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: const BorderRadius.all(PrivioRadius.card),
        child: Stack(
          children: [
            if (showResults)
              Positioned.fill(
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: share.clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: chosen ? PrivioColors.accentSurface : PrivioColors.surfaceRaised,
                      borderRadius: const BorderRadius.all(PrivioRadius.card),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: PrivioSpacing.md,
                vertical: PrivioSpacing.sm,
              ),
              child: Row(
                children: [
                  Icon(
                    chosen
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 16,
                    color: chosen ? PrivioColors.accentBright : PrivioColors.textTertiary,
                  ),
                  const SizedBox(width: PrivioSpacing.sm),
                  Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
                  if (showResults) ...[
                    const SizedBox(width: PrivioSpacing.sm),
                    Text('$count', style: theme.textTheme.bodySmall),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Writing a poll.
class _NewPollDialog extends StatefulWidget {
  const _NewPollDialog();

  @override
  State<_NewPollDialog> createState() => _NewPollDialogState();
}

class _NewPollDialogState extends State<_NewPollDialog> {
  /// Two is the fewest that is a question; twelve is what the server allows and
  /// more than fits on a phone.
  static const int _maxOptions = 12;

  final TextEditingController _question = TextEditingController();
  final List<TextEditingController> _options = [
    TextEditingController(),
    TextEditingController(),
  ];
  bool _several = false;

  @override
  void dispose() {
    _question.dispose();
    for (final option in _options) {
      option.dispose();
    }
    super.dispose();
  }

  List<String> get _filled =>
      [for (final option in _options) option.text.trim()]..removeWhere((o) => o.isEmpty);

  bool get _ready => _question.text.trim().isNotEmpty && _filled.length >= 2;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      backgroundColor: PrivioColors.surfaceRaised,
      title: const Text('Ask a question'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _question,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Question'),
            ),
            const SizedBox(height: PrivioSpacing.md),
            for (var index = 0; index < _options.length; index++)
              Padding(
                padding: const EdgeInsets.only(bottom: PrivioSpacing.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _options[index],
                        onChanged: (_) => setState(() {}),
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(hintText: 'Answer ${index + 1}'),
                      ),
                    ),
                    if (_options.length > 2)
                      IconButton(
                        onPressed: () => setState(() => _options.removeAt(index).dispose()),
                        icon: const Icon(Icons.close_rounded, size: 18),
                        tooltip: 'Remove',
                      ),
                  ],
                ),
              ),
            if (_options.length < _maxOptions)
              TextButton.icon(
                onPressed: () =>
                    setState(() => _options.add(TextEditingController())),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add an answer'),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _several,
              onChanged: (value) => setState(() => _several = value),
              activeThumbColor: PrivioColors.accent,
              title: Text('Several answers', style: theme.textTheme.bodyMedium),
            ),
            Text(
              'The question and the answers are encrypted with the channel key, '
              'like a post. The server counts the votes without ever learning '
              'what any of them say.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: !_ready
              ? null
              : () {
                  final options = _filled;
                  Navigator.of(context).pop(
                    ChannelPollDraft(
                      question: _question.text.trim(),
                      options: options,
                      // "Several" means up to all but one: letting somebody
                      // tick every box is not a poll, it is a list.
                      maxChoices: _several ? options.length - 1 : 1,
                    ),
                  );
                },
          child: const Text('Ask'),
        ),
      ],
    );
  }
}

/// The reactions on a post, and a way to add one.
///
/// What is shown is what is there: an emoji with nobody behind it is not drawn,
/// so a quiet post stays quiet and does not carry a row of zeroes. The plus
/// opens the channel's own set — an admin decides what it holds, and the server
/// refuses anything outside it.
///
/// A tap on one already marked takes it back. There is no long-press list of
/// who reacted, because there is no such list to serve: the server answers with
/// totals and with this account's own, and nothing else.
class _ReactionBar extends StatefulWidget {
  const _ReactionBar({
    required this.post,
    required this.channel,
    required this.onReact,
  });

  final ChannelPost post;
  final ChannelInfo channel;
  final Future<bool> Function(String emoji, {required bool on}) onReact;

  @override
  State<_ReactionBar> createState() => _ReactionBarState();
}

class _ReactionBarState extends State<_ReactionBar> {
  /// Which emoji is mid-flight, so a second tap does not race the first.
  String? _busy;

  Future<void> _toggle(String emoji) async {
    if (_busy != null) return;
    setState(() => _busy = emoji);
    // No optimistic count. The number that appears is the one the server
    // agreed to, because a reaction that quietly failed would otherwise leave a
    // total on this screen that nobody else can see.
    await widget.onReact(emoji, on: !widget.post.myReactions.contains(emoji));
    if (mounted) setState(() => _busy = null);
  }

  Future<void> _pick() async {
    final emoji = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: PrivioColors.surfaceRaised,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(PrivioSpacing.lg),
          child: Wrap(
            spacing: PrivioSpacing.sm,
            runSpacing: PrivioSpacing.sm,
            children: [
              for (final emoji in widget.channel.reactionEmojis)
                InkWell(
                  onTap: () => Navigator.of(sheetContext).pop(emoji),
                  borderRadius: const BorderRadius.all(PrivioRadius.card),
                  child: Padding(
                    padding: const EdgeInsets.all(PrivioSpacing.sm),
                    child: Text(emoji, style: const TextStyle(fontSize: 28)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (emoji != null) await _toggle(emoji);
  }

  @override
  Widget build(BuildContext context) {
    final counts = widget.post.reactions.entries.toList()
      // Busiest first, and alphabetical within a tie so the row does not
      // reshuffle itself every time two counts pass each other.
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });

    return Wrap(
      spacing: PrivioSpacing.xs,
      runSpacing: PrivioSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final entry in counts)
          _ReactionChip(
            emoji: entry.key,
            count: entry.value,
            mine: widget.post.myReactions.contains(entry.key),
            busy: _busy == entry.key,
            onTap: () => _toggle(entry.key),
          ),
        InkWell(
          onTap: _busy == null ? _pick : null,
          borderRadius: const BorderRadius.all(PrivioRadius.pill),
          child: const Padding(
            padding: EdgeInsets.symmetric(
              horizontal: PrivioSpacing.sm,
              vertical: PrivioSpacing.xs,
            ),
            child: Icon(
              Icons.add_reaction_outlined,
              size: 18,
              color: PrivioColors.textTertiary,
            ),
          ),
        ),
      ],
    );
  }
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({
    required this.emoji,
    required this.count,
    required this.mine,
    required this.busy,
    required this.onTap,
  });

  final String emoji;
  final int count;

  /// Whether this account is one of the [count]. Drawn differently, because
  /// "three people" and "three people including you" are different facts.
  final bool mine;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: busy ? null : onTap,
      borderRadius: const BorderRadius.all(PrivioRadius.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: PrivioSpacing.sm,
          vertical: PrivioSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: mine ? PrivioColors.accentSurface : PrivioColors.surfaceHigh,
          borderRadius: const BorderRadius.all(PrivioRadius.pill),
          border: mine ? Border.all(color: PrivioColors.accentDim) : null,
        ),
        child: Opacity(
          opacity: busy ? 0.5 : 1,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: PrivioSpacing.xs),
              Text(
                '$count',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: mine ? PrivioColors.accentBright : PrivioColors.textSecondary,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A post's file: what it is, and a way to open it.
///
/// Nothing is downloaded until it is asked for. A channel feed that fetched
/// every picture on the way past would spend a stranger's data allowance on a
/// channel they are only glancing at — and on a metered connection that is a
/// cost, not a convenience.
class _AttachmentTile extends StatefulWidget {
  const _AttachmentTile({required this.channelId, required this.post});

  final String channelId;
  final ChannelPost post;

  @override
  State<_AttachmentTile> createState() => _AttachmentTileState();
}

class _AttachmentTileState extends State<_AttachmentTile> {
  bool _busy = false;
  Uint8List? _opened;

  Future<void> _open() async {
    final attachment = widget.post.attachment;
    if (attachment == null || _busy) return;
    setState(() => _busy = true);
    final controller = PrivioScope.of(context).channels;
    final bytes = await controller.openAttachment(widget.channelId, widget.post);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _opened = bytes;
    });
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(controller.error ?? 'Could not open that file.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final attachment = widget.post.attachment!;
    final opened = _opened;

    // Once an image is open it is the point, so it replaces its own row.
    if (opened != null && attachment.isImage) {
      return GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => _ImageViewer(bytes: opened, name: attachment.name),
          ),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.all(PrivioRadius.card),
          child: Image.memory(opened, fit: BoxFit.cover),
        ),
      );
    }

    return InkWell(
      onTap: _busy ? null : _open,
      borderRadius: const BorderRadius.all(PrivioRadius.card),
      child: Container(
        padding: const EdgeInsets.all(PrivioSpacing.md),
        decoration: const BoxDecoration(
          color: PrivioColors.surfaceRaised,
          borderRadius: BorderRadius.all(PrivioRadius.card),
        ),
        child: Row(
          children: [
            if (_busy)
              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            else
              Icon(
                attachment.isImage ? Icons.image_outlined : Icons.insert_drive_file_outlined,
                size: 18,
                color: PrivioColors.accent,
              ),
            const SizedBox(width: PrivioSpacing.md),
            Expanded(
              child: Text(
                attachment.name ?? (attachment.isImage ? 'Picture' : 'File'),
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const SizedBox(width: PrivioSpacing.sm),
            Text(
              opened != null ? 'Opened' : _readableSize(attachment.bytes),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Bytes as something a person reads without counting zeros.
String _readableSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} kB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// A picture at full size, with pinch and pan.
///
/// The bytes are the ones already decrypted in memory for the feed — opening
/// this writes nothing to disk and asks the server for nothing a second time.
class _ImageViewer extends StatelessWidget {
  const _ImageViewer({required this.bytes, this.name});

  final Uint8List bytes;
  final String? name;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PrivioColors.background,
      appBar: AppBar(
        backgroundColor: PrivioColors.background,
        leading: const PrivioBackButton(),
        title: Text(
          name ?? 'Picture',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 6,
          child: Image.memory(bytes),
        ),
      ),
    );
  }
}

/// What a channel adds up to.
///
/// No view count, and the sheet says why rather than leaving a gap somebody
/// reads as an oversight.
class _StatsSheet extends StatelessWidget {
  const _StatsSheet({required this.stats});

  final ChannelStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(PrivioSpacing.gutter),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Statistics', style: theme.textTheme.titleMedium),
              const SizedBox(height: PrivioSpacing.md),
              _StatRow(label: 'Subscribers', value: stats.members),
              _StatRow(label: 'Posts', value: stats.posts),
              if (stats.scheduled > 0) _StatRow(label: 'Waiting to publish', value: stats.scheduled),
              _StatRow(label: 'Reactions', value: stats.reactions),
              _StatRow(label: 'Comments', value: stats.comments),
              if (stats.pollVoters > 0) _StatRow(label: 'People who voted', value: stats.pollVoters),
              if (stats.silenced > 0) _StatRow(label: 'Stopped from posting', value: stats.silenced),
              if (stats.waiting > 0) _StatRow(label: 'Waiting to join', value: stats.waiting),
              const SizedBox(height: PrivioSpacing.lg),
              Text(
                'There is no view count, and that is a decision rather than a '
                'gap. Counting who has read a post — without counting anybody '
                'twice — means keeping a row for every reader of every post, '
                'which is a record of what each person read. Everything above '
                'is counted from something somebody chose to do.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: PrivioSpacing.xs),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          Text('$value', style: theme.textTheme.titleSmall),
        ],
      ),
    );
  }
}

/// Choosing who gets the channel.
class _PickNewOwnerSheet extends StatelessWidget {
  const _PickNewOwnerSheet({required this.members});

  final List<ChannelMember> members;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(PrivioSpacing.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Hand this channel on', style: theme.textTheme.titleMedium),
            const SizedBox(height: PrivioSpacing.xs),
            Text(
              'Only somebody already in the channel. Handing it to a stranger '
              'would put them in charge of a key they do not hold.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: PrivioSpacing.md),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: members.length,
                itemBuilder: (context, index) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(members[index].label),
                  subtitle: Text(
                    members[index].isAdmin ? 'Admin' : 'Subscriber',
                    style: theme.textTheme.bodySmall,
                  ),
                  onTap: () => Navigator.of(context).pop(members[index]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The password step, and the sentence that explains why there is one.
class _ConfirmTransferDialog extends StatefulWidget {
  const _ConfirmTransferDialog({required this.member});

  final ChannelMember member;

  @override
  State<_ConfirmTransferDialog> createState() => _ConfirmTransferDialogState();
}

class _ConfirmTransferDialogState extends State<_ConfirmTransferDialog> {
  final TextEditingController _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      backgroundColor: PrivioColors.surfaceRaised,
      title: Text('Give the channel to ${widget.member.label}?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'They will own it. You stay on as an admin with everything you '
              'have now except the right to delete the channel — and they can '
              'remove you afterwards.\n\n'
              'You cannot undo this yourself. That is why it asks for your '
              'password rather than trusting an unlocked phone.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: PrivioSpacing.md),
            TextField(
              controller: _password,
              autofocus: true,
              obscureText: true,
              onSubmitted: (value) => Navigator.of(context).pop(value),
              decoration: const InputDecoration(hintText: 'Your Privio password'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: PrivioColors.danger),
          onPressed: () => Navigator.of(context).pop(_password.text),
          child: const Text('Hand it on'),
        ),
      ],
    );
  }
}

/// Reporting a channel, and being straight about what a report can reach.
class _ReportSheet extends StatelessWidget {
  const _ReportSheet({required this.channel});

  final ChannelInfo channel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(PrivioSpacing.gutter),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Report this channel', style: theme.textTheme.titleMedium),
              const SizedBox(height: PrivioSpacing.xs),
              Text(
                channel.isPublic
                    ? 'The report carries this channel and the reason you pick. '
                        'Whoever runs the server can see a public channel\'s name '
                        'and description, because those are how it is searched '
                        'for — but not its posts, which are encrypted.'
                    : 'The report carries this channel and the reason you pick, '
                        'and nothing else. Its name and its posts are encrypted, '
                        'so whoever runs the server cannot read them. That is the '
                        'honest limit of what reporting a private channel does.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: PrivioSpacing.md),
              for (final reason in ChannelReportReason.values)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(reason.label),
                  onTap: () => Navigator.of(context).pop(reason),
                ),
              const SizedBox(height: PrivioSpacing.sm),
              Text(
                'There is no message box on purpose: it would be the one place '
                'in Privio where somebody pastes the encrypted thing they are '
                'reporting into a field the server can read.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the settings sheet decided.
class _InviteAction {
  const _InviteAction.settings({
    this.expiresAt,
    this.clearExpiry = false,
    this.maxUses,
    this.clearMaxUses = false,
    this.needsApproval,
  }) : rotate = false;

  const _InviteAction.rotate()
      : rotate = true,
        expiresAt = null,
        clearExpiry = false,
        maxUses = null,
        clearMaxUses = false,
        needsApproval = null;

  final bool rotate;
  final DateTime? expiresAt;
  final bool clearExpiry;
  final int? maxUses;
  final bool clearMaxUses;
  final bool? needsApproval;
}

/// What the invite link is allowed to do.
///
/// Revoking is rotating, and the sheet says so plainly rather than calling it
/// "revoke" and leaving people to wonder whether the old link half-works. It
/// does not: a new code takes effect at once and every copy of the old one
/// stops resolving, in messages, on posters, in somebody's clipboard.
class _InviteSettingsSheet extends StatefulWidget {
  const _InviteSettingsSheet({required this.channel});

  final ChannelInfo channel;

  @override
  State<_InviteSettingsSheet> createState() => _InviteSettingsSheetState();
}

class _InviteSettingsSheetState extends State<_InviteSettingsSheet> {
  late DateTime? _expiresAt = widget.channel.invite.expiresAt;
  late int? _maxUses = widget.channel.invite.maxUses;
  late bool _needsApproval = widget.channel.invite.needsApproval;

  /// The limits people actually pick. A free number field invites a typo that
  /// closes a channel to everybody but one person.
  static const List<int> _useChoices = [1, 5, 10, 25, 100];

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: DateTime(now.year + 1, now.month, now.day),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
    );
    if (time == null || !mounted) return;
    final when = DateTime(day.year, day.month, day.day, time.hour, time.minute);
    if (!when.isAfter(now)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a time that has not gone yet.')),
      );
      return;
    }
    setState(() => _expiresAt = when);
  }

  Future<void> _confirmRotate() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PrivioColors.surfaceRaised,
        title: const Text('Replace the link?'),
        content: const Text(
          'The link you have shared stops working immediately — in messages, '
          'on posters, wherever it was pasted. Nobody holding it can join.\n\n'
          'People already in the channel stay in. There is no way to bring the '
          'old link back.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: PrivioColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Replace it'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      Navigator.of(context).pop(const _InviteAction.rotate());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(PrivioSpacing.gutter),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Invite link', style: theme.textTheme.titleMedium),
              const SizedBox(height: PrivioSpacing.md),

              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _needsApproval,
                onChanged: (value) => setState(() => _needsApproval = value),
                activeThumbColor: PrivioColors.accent,
                title: Text('Ask me first', style: theme.textTheme.bodyMedium),
                subtitle: Text(
                  'People who follow the link wait for your approval instead of '
                  'walking in. They hold no key until you let them in.',
                  style: theme.textTheme.bodySmall,
                ),
              ),

              const SizedBox(height: PrivioSpacing.md),
              Text('Expires', style: theme.textTheme.labelLarge),
              const SizedBox(height: PrivioSpacing.xs),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _expiresAt == null ? 'Never' : _whenLabel(_expiresAt!),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  if (_expiresAt != null)
                    TextButton(
                      onPressed: () => setState(() => _expiresAt = null),
                      child: const Text('Never'),
                    ),
                  TextButton(onPressed: _pickExpiry, child: const Text('Pick a time')),
                ],
              ),

              const SizedBox(height: PrivioSpacing.md),
              Text('How many can join on it', style: theme.textTheme.labelLarge),
              const SizedBox(height: PrivioSpacing.xs),
              Wrap(
                spacing: PrivioSpacing.sm,
                children: [
                  ChoiceChip(
                    label: const Text('No limit'),
                    selected: _maxUses == null,
                    onSelected: (_) => setState(() => _maxUses = null),
                  ),
                  for (final choice in _useChoices)
                    ChoiceChip(
                      label: Text('$choice'),
                      selected: _maxUses == choice,
                      onSelected: (_) => setState(() => _maxUses = choice),
                    ),
                ],
              ),
              if (widget.channel.invite.maxUses != null) ...[
                const SizedBox(height: PrivioSpacing.xs),
                Text(
                  '${widget.channel.invite.uses} have joined on this link so far. '
                  'Opening it and walking away does not count.',
                  style: theme.textTheme.bodySmall,
                ),
              ],

              const SizedBox(height: PrivioSpacing.lg),
              OutlinedButton.icon(
                onPressed: _confirmRotate,
                icon: const Icon(Icons.link_off_rounded, size: 18),
                label: const Text('Replace the link'),
                style: OutlinedButton.styleFrom(foregroundColor: PrivioColors.danger),
              ),
              const SizedBox(height: PrivioSpacing.xs),
              Text(
                'Replacing is how a link is revoked: the old one stops working '
                'at once, everywhere. There is no half-working link left behind.',
                style: theme.textTheme.bodySmall,
              ),

              const SizedBox(height: PrivioSpacing.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: PrivioSpacing.sm),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(
                      _InviteAction.settings(
                        expiresAt: _expiresAt,
                        clearExpiry: _expiresAt == null,
                        maxUses: _maxUses,
                        clearMaxUses: _maxUses == null,
                        needsApproval: _needsApproval,
                      ),
                    ),
                    child: const Text('Save'),
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

/// Who is waiting at the door.
///
/// They are not members: they hold no key, are sent nothing, and the channel
/// does not count them. The row exists so an admin sees the knock — the
/// alternative is a link that silently does nothing and a person who assumes
/// it is broken.
class _JoinRequestsScreen extends StatelessWidget {
  const _JoinRequestsScreen({required this.channel});

  final ChannelInfo channel;

  @override
  Widget build(BuildContext context) {
    final controller = PrivioScope.of(context).channels;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final waiting = controller.knockingAt(channel.id);
        return Scaffold(
          appBar: AppBar(
            leading: const PrivioBackButton(),
            title: const Text('Requests to join'),
          ),
          body: waiting.isEmpty
              ? const _NobodyWaiting()
              : ListView.builder(
                  itemCount: waiting.length,
                  itemBuilder: (context, index) {
                    final request = waiting[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: PrivioSpacing.gutter,
                        vertical: PrivioSpacing.xs,
                      ),
                      title: Text(request.label),
                      subtitle: Text(
                        'Asked ${_whenLabel(request.requestedAt)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: () => controller.answerJoinRequest(
                              channel.id,
                              request.accountId,
                              admit: false,
                            ),
                            child: const Text(
                              'No',
                              style: TextStyle(color: PrivioColors.danger),
                            ),
                          ),
                          const SizedBox(width: PrivioSpacing.xs),
                          FilledButton(
                            onPressed: () => controller.answerJoinRequest(
                              channel.id,
                              request.accountId,
                              admit: true,
                            ),
                            child: const Text('Let in'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}

class _NobodyWaiting extends StatelessWidget {
  const _NobodyWaiting();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.door_front_door_outlined, size: 40, color: PrivioColors.textTertiary),
            const SizedBox(height: PrivioSpacing.md),
            Text('Nobody waiting', style: theme.textTheme.titleMedium),
            const SizedBox(height: PrivioSpacing.xs),
            Text(
              'People who follow the invite link appear here while the link is '
              'set to ask you first.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _InviteDialog extends StatelessWidget {
  const _InviteDialog({required this.link, required this.channel, this.onManage});

  final String link;
  final ChannelInfo channel;

  /// Opens the settings. Null for a member who cannot change them.
  final VoidCallback? onManage;

  /// What the link is currently good for, in one line.
  String get _state {
    final invite = channel.invite;
    if (invite.hasExpired) return 'This link has expired — nobody can join on it.';
    if (invite.isUsedUp) return 'This link has been used up.';
    return [
      if (invite.needsApproval)
        'Joining needs your approval'
      else
        'Anyone with it joins straight away',
      if (invite.maxUses != null) '${invite.uses} of ${invite.maxUses} used',
      if (invite.expiresAt != null) 'expires ${_whenLabel(invite.expiresAt!)}',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      backgroundColor: PrivioColors.surfaceRaised,
      title: const Text('Invite link'),
      // Scrollable: the QR code plus the link plus the explanation is taller
      // than a dialog on a small phone in landscape.
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          // Rendered on this device. The link is never sent anywhere to be
          // turned into a picture of itself.
          Center(
            child: Container(
              padding: const EdgeInsets.all(PrivioSpacing.md),
              decoration: const BoxDecoration(
                color: PrivioColors.textPrimary,
                borderRadius: BorderRadius.all(PrivioRadius.card),
              ),
              child: QrImageView(
                data: link,
                version: QrVersions.auto,
                size: 176,
                backgroundColor: PrivioColors.textPrimary,
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
          const SizedBox(height: PrivioSpacing.md),
          SelectableText(link, style: theme.textTheme.bodySmall),
          const SizedBox(height: PrivioSpacing.md),
          Text(
            'Share this anywhere — it carries no key. Whoever opens it joins the '
            'channel, and the key to read it is sent to their device afterwards, '
            'encrypted, by someone who already has it.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: PrivioSpacing.sm),
          Text(
            _state,
            style: theme.textTheme.bodySmall?.copyWith(
              color: channel.invite.isSpent ? PrivioColors.warning : PrivioColors.textSecondary,
            ),
          ),
          ],
        ),
      ),
      actions: [
        if (onManage != null)
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              onManage!();
            },
            child: const Text('Settings'),
          ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
        FilledButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: link));
            if (context.mounted) Navigator.of(context).pop();
          },
          child: const Text('Copy'),
        ),
      ],
    );
  }
}

class _MissingKeyBanner extends StatelessWidget {
  const _MissingKeyBanner({this.rotating = false, this.epoch = 1, this.onRetry});

  /// Tries the key delivery again. Null leaves the banner as an explanation.
  final VoidCallback? onRetry;

  /// True when this device already reads some of the channel and is waiting for
  /// a new version, rather than waiting for its first key ever.
  final bool rotating;

  final int epoch;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(PrivioSpacing.gutter),
      padding: const EdgeInsets.all(PrivioSpacing.md),
      decoration: BoxDecoration(
        color: PrivioColors.warning.withValues(alpha: 0.12),
        borderRadius: const BorderRadius.all(PrivioRadius.card),
      ),
      child: Row(
        children: [
          Icon(
            rotating ? Icons.autorenew_rounded : Icons.key_off_rounded,
            size: 18,
            color: PrivioColors.warning,
          ),
          const SizedBox(width: PrivioSpacing.md),
          Expanded(
            child: Text(
              rotating
                  ? 'Someone left this channel, so it is changing its key '
                      '(version $epoch). Posts from before are still readable. '
                      'New ones open once the new key reaches this device.'
                  : 'Waiting for the key. It is sent to this device, encrypted, '
                      'by someone already in the channel — the server never '
                      'holds it.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(width: PrivioSpacing.sm),
            TextButton(
              onPressed: onRetry,
              child: const Text('Try again'),
            ),
          ],
        ],
      ),
    );
  }
}

class _JoinPrompt extends StatelessWidget {
  const _JoinPrompt({required this.channel, required this.onJoin});

  final ChannelInfo channel;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.campaign_outlined, size: 40, color: PrivioColors.textTertiary),
            const SizedBox(height: PrivioSpacing.md),
            Text(channel.title, style: theme.textTheme.titleMedium),
            if (channel.description != null) ...[
              const SizedBox(height: PrivioSpacing.xs),
              Text(
                channel.description!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: PrivioSpacing.md),
            Text(
              'Joining gets you the posts. The key that opens them is sent to '
              'your device afterwards by a member, never by the server.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: PrivioSpacing.xl),
            FilledButton(onPressed: onJoin, child: const Text('Join channel')),
          ],
        ),
      ),
    );
  }
}

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.article_outlined, size: 40, color: PrivioColors.textTertiary),
            const SizedBox(height: PrivioSpacing.md),
            Text('No posts yet', style: theme.textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}
