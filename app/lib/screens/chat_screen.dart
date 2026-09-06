import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../calls/call.dart';
import '../calls/call_signal.dart';
import '../core/app_state.dart';
import '../core/conversation_controller.dart';
import '../crypto/safety_number.dart';
import '../models/models.dart';
import '../media/voice.dart';
import 'group_info_screen.dart';
import 'license_screen.dart';
import 'safety_number_screen.dart';
import '../widgets/disappearing_timer_sheet.dart';
import '../widgets/privio_back_button.dart';
import '../widgets/voice_composer.dart';
import '../theme/privio_colors.dart';
import '../widgets/avatar.dart';
import '../widgets/message_bubble.dart';
import '../widgets/scrub_notice.dart';

/// One conversation. Everything shown here was decrypted on this device, and
/// everything typed here is sealed before it leaves it.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    required this.accountId,
    required this.title,
    super.key,
    this.isGroup = false,
    this.jumpTo,
  });

  final String accountId;
  final String title;
  final bool isGroup;

  /// The client id of a message to open at, from a search result. Null opens
  /// where a chat always opens: at the end.
  final String? jumpTo;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final GlobalKey<VoiceComposerState> _voiceKey = GlobalKey<VoiceComposerState>();

  /// The message the next send replies to, or null.
  Message? _replyingTo;

  final TextEditingController _composer = TextEditingController();

  /// A positioned list rather than a plain one, because a search result has to
  /// land on a message that may be hundreds of lines up. A ScrollController can
  /// only be given an offset, and the offset of a message that has never been
  /// laid out is not knowable.
  final ItemScrollController _scroll = ItemScrollController();

  /// Which message a search sent us to, drawn lit until it is read. Cleared on
  /// the first touch, so it marks the message rather than staining it.
  String? _highlighted;
  bool _jumped = false;

  /// What the safety-number screen would say, kept here so the header can say
  /// it too. Read once on open rather than on every rebuild: it changes only
  /// when a key does, and asking the keystore per frame would be absurd.
  VerificationState? _verification;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _highlighted = widget.jumpTo;
    if (!widget.isGroup) {
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_readVerification()));
    }
  }

  Future<void> _readVerification() async {
    final state = PrivioScope.of(context);
    final me = state.accountId;
    if (me == null) return;
    final numbers = await state.services.crypto.safetyNumbers(
      localAccountId: me,
      remoteAccountId: widget.accountId,
    );
    if (!mounted) return;
    setState(() => _verification = numbers.isEmpty ? null : numbers.state);
  }

  Future<void> _openGroupInfo() => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => GroupInfoScreen(groupId: widget.accountId),
        ),
      );

  Future<void> _openSafetyNumber() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SafetyNumberScreen(
          accountId: widget.accountId,
          title: widget.title,
        ),
      ),
    );
    if (mounted) await _readVerification();
  }

  /// The header line. It used to say "End-to-end encrypted" unconditionally,
  /// which is true and answers the wrong question: encrypted *to whom* is the
  /// part a user cannot check for themselves.
  String _encryptionSubtitle(AppState state) {
    if (state.conversations.hasIdentityChange(widget.accountId) ||
        state.conversations.hasKeyChangeAlert(widget.accountId)) {
      return 'Safety number changed';
    }
    return switch (_verification) {
      VerificationState.verified => 'End-to-end encrypted · verified',
      VerificationState.changed => 'End-to-end encrypted · number changed',
      _ => 'End-to-end encrypted',
    };
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _voiceRebuild.dispose();
    _composer.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    final replyTo = _replyingTo;
    _composer.clear();
    setState(() => _replyingTo = null);
    await PrivioScope.of(context).conversations.send(widget.accountId, text, replyTo: replyTo);
    _scrollToEnd();
  }

  /// Long press on a bubble: react, or reply.
  ///
  /// One sheet for both, because they are the two things anyone wants to do to
  /// a message that is already there — and a long press that opened a menu of
  /// twelve would be a long press people stop using.
  Future<void> _openMessageActions(AppState state, Message message) async {
    final clientId = message.clientId;
    final queued = clientId != null && state.conversations.isQueued(clientId);
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: PrivioColors.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: PrivioSpacing.gutter,
                vertical: PrivioSpacing.md,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final emoji in queued ? const <String>[] : ConversationController.quickReactions)
                    GestureDetector(
                      onTap: () => Navigator.of(sheetContext).pop('react:$emoji'),
                      child: Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: state.conversations.accountId != null &&
                                  message.reactions[state.conversations.accountId] == emoji
                              ? PrivioColors.accentSurface
                              : PrivioColors.surfaceRaised,
                          shape: BoxShape.circle,
                        ),
                        child: Text(emoji, style: const TextStyle(fontSize: 22)),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1, color: PrivioColors.border),
            // A recording that never went out. The controller has had a retry
            // and a discard since the offline queue was written, and nothing
            // offered either of them: a failed voice message showed a red mark
            // and left the person looking at it with nothing to do.
            if (queued) ...[
              ListTile(
                leading: const Icon(Icons.refresh_rounded),
                title: const Text('Try again'),
                subtitle: Text(
                  message.state == DeliveryState.failed
                      ? 'It did not go out. Send it now.'
                      : 'Waiting for a network. Try now anyway.',
                ),
                onTap: () => Navigator.of(sheetContext).pop('retry'),
              ),
              const Divider(height: 1, color: PrivioColors.border),
            ],
            if (!queued)
              ListTile(
                leading: const Icon(Icons.reply_rounded),
                title: const Text('Reply'),
                onTap: () => Navigator.of(sheetContext).pop('reply'),
              ),
            if (message.body.isNotEmpty && message.kind != MessageKind.deleted)
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('Copy text'),
                onTap: () => Navigator.of(sheetContext).pop('copy'),
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              iconColor: PrivioColors.danger,
              textColor: PrivioColors.danger,
              title: const Text('Delete'),
              onTap: () => Navigator.of(sheetContext).pop('delete'),
            ),
            const SizedBox(height: PrivioSpacing.sm),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    if (action == 'retry') {
      await state.conversations.retry(clientId!);
      return;
    }
    if (action == 'reply') {
      setState(() => _replyingTo = message);
      return;
    }
    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: message.body));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Copied.')));
      return;
    }
    if (action == 'delete') {
      // Dropping the queue entry too. Removing only the bubble would leave the
      // message to arrive later out of a queue the person thought was empty.
      if (queued) {
        state.conversations.discard(clientId);
        return;
      }
      await _confirmDelete(state, message);
      return;
    }
    await state.conversations.react(
      widget.accountId,
      message,
      action.substring('react:'.length),
    );
  }

  /// Asks which kind of delete this is, and says plainly what each one can and
  /// cannot do.
  Future<void> _confirmDelete(AppState state, Message message) async {
    // Taking it back everywhere is only offered for what this account wrote,
    // and only while there is still somebody to ask.
    final canRecall = message.isMine && message.kind != MessageKind.deleted;

    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: PrivioColors.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: PrivioSpacing.sm),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('Delete for me'),
              subtitle: const Text('Gone from this device. Other devices keep it.'),
              onTap: () => Navigator.of(sheetContext).pop('me'),
            ),
            if (canRecall)
              ListTile(
                leading: const Icon(Icons.delete_forever_outlined),
                iconColor: PrivioColors.danger,
                textColor: PrivioColors.danger,
                title: const Text('Delete for everyone'),
                subtitle: const Text(
                  'Asks their app to forget it. It cannot take back what was '
                  'already read, screenshotted, or restored from a backup.',
                ),
                onTap: () => Navigator.of(sheetContext).pop('everyone'),
              ),
            const SizedBox(height: PrivioSpacing.sm),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    if (choice == 'everyone') {
      await state.conversations.deleteForEveryone(widget.accountId, message);
    } else {
      await state.conversations.deleteForMe(widget.accountId, message);
    }
  }

  /// Picks a file and sends it. The bytes are read into memory rather than
  /// handed over as a path, because they have to be scrubbed and sealed before
  /// anything leaves the device.
  Future<void> _attach() async {
    FilePickerResult? picked;
    try {
      // A platform whose picker is missing answers with a future that never
      // completes, which looks to the user like a button that does nothing. The
      // timeout turns that into a message they can act on.
      picked = await FilePicker.pickFiles(withData: true).timeout(const Duration(minutes: 2));
    } on TimeoutException {
      if (mounted) _showError('The file picker did not respond.');
      return;
    } on Object catch (failure) {
      if (mounted) _showError('Could not open the file picker: $failure');
      return;
    }

    final file = picked?.files.singleOrNull;
    if (file == null || !mounted) return;
    if (file.bytes == null) {
      _showError('Could not read ${file.name}.');
      return;
    }

    final report = await PrivioScope.of(context).conversations.sendAttachment(
          widget.accountId,
          file: file.bytes!,
          fileName: file.name,
        );
    _scrollToEnd();
    if (report != null && mounted) ScrubNotice.show(context, report);
  }

  /// Members, and whether this device can read the group's name yet.
  String _groupSubtitle(AppState state) {
    final group = state.conversations.groupInfo(widget.accountId);
    if (group == null) return 'End-to-end encrypted';
    if (group.groupKey == null) return 'Waiting for the group key';
    final count = group.memberIds.length;
    return count > 0 ? '$count members · encrypted' : 'End-to-end encrypted';
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// The index of [clientId] in the list as it is drawn, or null.
  ///
  /// One past the message's own position: the encryption notice is item zero.
  int? _indexOf(List<Message> messages, String clientId) {
    final at = messages.indexWhere((m) => m.clientId == clientId);
    return at == -1 ? null : at + 1;
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.isAttached) return;
      _scroll.scrollTo(
        index: _messageCount,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  /// How many rows the list has, kept so a scroll-to-end has something to aim
  /// at from outside the build.
  int _messageCount = 0;

  /// Where the list should be on its very first layout.
  int _initialIndex(List<Message> messages) {
    final target = widget.jumpTo;
    if (target != null) return _indexOf(messages, target) ?? messages.length;
    return messages.length;
  }

  /// Opens the chat on the message a search found, rather than at the end.
  void _scrollToHit(List<Message> messages, String clientId) {
    final index = _indexOf(messages, clientId);
    if (index == null) {
      // Deleted, expired, or never on this device. Nothing to jump to, and the
      // chat still opens.
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.isAttached) return;
      _scroll.jumpTo(index: index, alignment: 0.3);
    });
  }

  // --- Disappearing messages ------------------------------------------------

  /// Sets how long messages in this chat live.
  ///
  /// The timer is agreed end to end: it rides inside each sealed payload, so
  /// the other side adopts it without the server being told. Both devices then
  /// delete on their own clocks — which is the only way this can work, because
  /// a server asked to forget something is a server being trusted.
  Future<void> _chooseTimer(AppState state) async {
    final chosen = await DisappearingTimerSheet.choose(
      context,
      current: state.conversations.disappearAfter(widget.accountId),
      isGroup: false,
    );
    if (chosen == null || !mounted) return;
    state.conversations.setDisappearAfter(widget.accountId, chosen.value);
  }

  /// Blocks the other side of a 1:1 chat.
  ///
  /// The server drops what they send afterwards and tells them nothing, so the
  /// confirmation says that rather than promising them a notice.
  Future<void> _confirmBlock(AppState state) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PrivioColors.surface,
        title: Text('Block ${widget.title}?'),
        content: const Text(
          'Their messages stop arriving. They are not told, and it looks to them '
          'as though nothing changed. You can lift it in Privacy & Security.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: PrivioColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Block'),
          ),
        ],
      ),
    );
    if (!(yes ?? false) || !mounted) return;

    final blocked = await state.conversations.block(widget.accountId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(blocked ? '${widget.title} is blocked.' : 'Could not block them.'),
      ),
    );
    if (blocked) Navigator.of(context).pop();
  }

  // --- Voice messages -------------------------------------------------------

  void _onVoiceFailure(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// The microphone was refused.
  ///
  /// Said once, plainly, with the way to change it — not repeated on every
  /// press, and never as a dialog that blocks the chat.
  void _onMicrophoneDenied() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Privio cannot record without microphone access. '
          'You can grant it in your device settings.',
        ),
        duration: Duration(seconds: 5),
      ),
    );
  }

  Future<void> _sendVoice(AppState state, VoiceRecording recording) async {
    await state.conversations.sendVoice(widget.accountId, recording);
    _scrollToEnd();
  }

  /// Bumped whenever the recorder changes stage, so the row showing either the
  /// composer or the recording strip rebuilds.
  final ValueNotifier<int> _voiceRebuild = ValueNotifier<int>(0);

  void _voiceChanged() => _voiceRebuild.value++;

  Future<void> _startRecording() async {
    await _voiceKey.currentState?.start();
    _voiceChanged();
  }

  Future<void> _endRecording() async {
    await _voiceKey.currentState?.onHoldReleased();
    _voiceChanged();
  }

  /// Plays a recording back before it is sent, from memory.
  Future<void> _previewVoice(AppState state, VoiceRecording recording) =>
      state.services.player.play(
        'preview',
        recording.bytes,
        mediaType: recording.mediaType,
      );

  /// Stops anything being recorded when the app goes away.
  ///
  /// A call arriving, or the app being backgrounded, takes the microphone with
  /// it. Keeping a half-recording running through that produces silence at
  /// best; stopping into the preview keeps what was said and lets the user
  /// decide.
  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    if (lifecycleState == AppLifecycleState.inactive ||
        lifecycleState == AppLifecycleState.paused ||
        lifecycleState == AppLifecycleState.hidden) {
      final composer = _voiceKey.currentState;
      if (composer?.stage == VoiceComposerStage.recording) {
        unawaited(composer!.pause());
      }
    }
  }

  /// Shows the group's join link. It carries no key: whoever opens it joins,
  /// and a member's device sends them the key to the group's name afterwards.
  Future<void> _shareGroupLink(AppState state) async {
    final link = state.conversations.groupInviteLink(widget.accountId);
    if (link == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No link for this group yet — pull to refresh.')),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PrivioColors.surfaceRaised,
        title: const Text('Invite link'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(link, style: Theme.of(dialogContext).textTheme.bodySmall),
            const SizedBox(height: PrivioSpacing.md),
            Text(
              'Share it anywhere — it carries no key. Whoever opens it joins the '
              'group, and the key to its name reaches their device encrypted.',
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: link));
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            child: const Text('Copy'),
          ),
        ],
      ),
    );
  }

  Future<void> _call(AppState state, CallMedia media) => state.services.calls.place(
        CallParty(accountId: widget.accountId, username: widget.title),
        media: media,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = PrivioScope.of(context);

    return ListenableBuilder(
      listenable: state.conversations,
      builder: (context, _) {
        final messages = state.conversations.messagesWith(widget.accountId);
        _messageCount = messages.length;
        // Once, on the way in: a search sent us to a particular line.
        if (widget.jumpTo != null && !_jumped) {
          _jumped = true;
          _scrollToHit(messages, widget.jumpTo!);
        }

        return Scaffold(
          appBar: AppBar(
            leading: const PrivioBackButton(),
            titleSpacing: 0,
            title: Row(
              children: [
                PrivioAvatar(
                  label: widget.title,
                  size: 34,
                  seed: widget.accountId.hashCode.abs(),
                  isGroup: widget.isGroup,
                  imageBytes: state.conversations.avatarFor(widget.accountId),
                ),
                const SizedBox(width: PrivioSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      Text(
                        state.conversations.isTyping(widget.accountId)
                            ? 'typing…'
                            : widget.isGroup
                                ? _groupSubtitle(state)
                                : _encryptionSubtitle(state),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: state.conversations.hasIdentityChange(widget.accountId) ||
                                  state.conversations.hasKeyChangeAlert(widget.accountId) ||
                                  _verification == VerificationState.changed
                              ? PrivioColors.warning
                              : PrivioColors.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              if (widget.isGroup)
                IconButton(
                  onPressed: () => _shareGroupLink(state),
                  icon: const Icon(Icons.link_rounded),
                  tooltip: 'Invite link',
                ),
              // Groups have no call yet: a group call is a different piece of
              // machinery, not the same one with more people in it.
              if (!widget.isGroup) ...[
                IconButton(
                  onPressed: () => unawaited(_call(state, CallMedia.video)),
                  icon: const Icon(Icons.videocam_outlined),
                  tooltip: 'Video call',
                ),
                IconButton(
                  onPressed: () => unawaited(_call(state, CallMedia.audio)),
                  icon: const Icon(Icons.call_outlined),
                  tooltip: 'Voice call',
                ),
              ],
              // The overflow used to open the timer sheet directly, which made
              // it an icon that meant one specific thing. It is a menu now, so
              // blocking has somewhere to live.
              PopupMenuButton<String>(
                icon: Icon(
                  state.conversations.disappearAfter(widget.accountId) == null
                      ? Icons.more_vert_rounded
                      : Icons.timer_outlined,
                  color: state.conversations.disappearAfter(widget.accountId) == null
                      ? null
                      : PrivioColors.accent,
                ),
                color: PrivioColors.surface,
                tooltip: 'More',
                onSelected: (action) => switch (action) {
                  'timer' => _chooseTimer(state),
                  'block' => _confirmBlock(state),
                  'safety' => _openSafetyNumber(),
                  'group' => _openGroupInfo(),
                  _ => null,
                },
                itemBuilder: (context) => [
                  if (widget.isGroup)
                    const PopupMenuItem(
                      value: 'group',
                      child: Text('Group info'),
                    ),
                  const PopupMenuItem(
                    value: 'timer',
                    child: Text('Disappearing messages'),
                  ),
                  if (!widget.isGroup)
                    const PopupMenuItem(
                      value: 'safety',
                      child: Text('Safety number'),
                    ),
                  if (!widget.isGroup)
                    const PopupMenuItem(
                      value: 'block',
                      child: Text('Block'),
                    ),
                ],
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                // The highlight is a pointer, not a state: the first touch in
                // the transcript means it has been seen.
                child: Listener(
                  onPointerDown: (_) {
                    if (_highlighted != null) setState(() => _highlighted = null);
                  },
                  child: ScrollablePositionedList.builder(
                    itemScrollController: _scroll,
                    // The first paint lands where it belongs, rather than at
                    // the top for one frame and then jumping.
                    initialScrollIndex: _initialIndex(messages),
                    padding: const EdgeInsets.only(bottom: PrivioSpacing.md),
                    itemCount: messages.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) return const EncryptionNotice();
                      final message = messages[index - 1];
                      return MessageBubble(
                        message: message,
                        highlighted: message.clientId != null &&
                            message.clientId == _highlighted,
                        onLongPress: () => _openMessageActions(state, message),
                      );
                    },
                  ),
                ),
              ),
              if (_replyingTo != null)
                _ReplyBar(
                  message: _replyingTo!,
                  onCancel: () => setState(() => _replyingTo = null),
                ),
              if (state.conversations.error != null)
                _ErrorBanner(
                  message: state.conversations.error!,
                  // The server refuses to relay for an unlicensed account, so
                  // a send that failed while one is unactivated has somewhere
                  // to go rather than just a red line.
                  onActivate: state.license.needsActivation
                      ? () => Navigator.of(context).push(
                            MaterialPageRoute<void>(builder: (_) => const LicenseScreen()),
                          )
                      : null,
                ),
              // The recording strip lives inside the composer row rather than
              // replacing it. The microphone that started the hold has to stay
              // mounted, or the release never arrives.
              ListenableBuilder(
                listenable: _voiceRebuild,
                builder: (context, _) => _Composer(
                  controller: _composer,
                  onSend: _send,
                  onAttach: _attach,
                  onHoldStart: _startRecording,
                  onHoldUpdate: (dx) {
                    _voiceKey.currentState?.onDragUpdate(dx);
                    _voiceChanged();
                  },
                  onHoldEnd: _endRecording,
                  onSendVoice: () {
                    _voiceKey.currentState?.send();
                    _voiceChanged();
                  },
                  onTyping: (_) => state.conversations.typing(widget.accountId),
                  voiceStage: _voiceKey.currentState?.stage ?? VoiceComposerStage.idle,
                  voice: VoiceComposer(
                    key: _voiceKey,
                    recorder: state.services.recorder,
                    onSend: (recording) {
                      unawaited(_sendVoice(state, recording));
                      _voiceChanged();
                    },
                    onPermissionDenied: () {
                      _onMicrophoneDenied();
                      _voiceChanged();
                    },
                    onFailure: (message) {
                      _onVoiceFailure(message);
                      _voiceChanged();
                    },
                    preview: (recording) => _previewVoice(state, recording),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, this.onActivate});

  final String message;

  /// Set only when the failure is one activating a license would fix.
  final VoidCallback? onActivate;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: PrivioColors.danger.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(
        horizontal: PrivioSpacing.gutter,
        vertical: PrivioSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: PrivioColors.danger),
            ),
          ),
          if (onActivate != null) TextButton(onPressed: onActivate, child: const Text('Activate')),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.onSend,
    required this.onAttach,
    required this.onHoldStart,
    required this.onHoldUpdate,
    required this.onHoldEnd,
    required this.onSendVoice,
    required this.onTyping,
    required this.voiceStage,
    required this.voice,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback? onAttach;

  /// Hold the microphone to record, slide left to throw it away, let go to
  /// stop. [onHoldUpdate] receives the horizontal movement of the finger.
  final Future<void> Function() onHoldStart;
  final void Function(double dx) onHoldUpdate;
  final Future<void> Function() onHoldEnd;

  /// Sends the recording currently in preview.
  final VoidCallback onSendVoice;

  /// Called on every keystroke; the controller decides how often that turns
  /// into anything on the wire.
  final void Function(String text) onTyping;

  final VoiceComposerStage voiceStage;

  /// The recording or preview strip. Rendered where the text field would be.
  final Widget voice;

  @override
  Widget build(BuildContext context) {
    final recording = voiceStage != VoiceComposerStage.idle;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          PrivioSpacing.md,
          PrivioSpacing.sm,
          PrivioSpacing.md,
          PrivioSpacing.sm,
        ),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: PrivioColors.border)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (recording)
              Expanded(child: voice)
            else ...[
              IconButton(
                onPressed: onAttach,
                icon: const Icon(Icons.add_rounded, color: PrivioColors.textSecondary),
                tooltip: 'Attach a file',
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: onTyping,
                  onSubmitted: (_) => onSend(),
                  decoration: const InputDecoration(
                    hintText: 'Type a message...',
                    isDense: true,
                  ),
                ),
              ),
              // Mounted but not shown, so the recorder's state survives the
              // switch back and forth.
              Offstage(child: voice),
            ],
            const SizedBox(width: PrivioSpacing.sm),
            _TrailingAction(
              controller: controller,
              stage: voiceStage,
              onSend: onSend,
              onSendVoice: onSendVoice,
              onHoldStart: onHoldStart,
              onHoldUpdate: onHoldUpdate,
              onHoldEnd: onHoldEnd,
            ),
          ],
        ),
      ),
    );
  }
}

/// Send, or the microphone — whichever the moment calls for.
///
/// One widget so the microphone is never unmounted mid-hold: the release of a
/// long press goes to the recognizer that won the arena, and a recognizer whose
/// widget has gone reports nothing at all.
class _TrailingAction extends StatelessWidget {
  const _TrailingAction({
    required this.controller,
    required this.stage,
    required this.onSend,
    required this.onSendVoice,
    required this.onHoldStart,
    required this.onHoldUpdate,
    required this.onHoldEnd,
  });

  final TextEditingController controller;
  final VoiceComposerStage stage;
  final VoidCallback onSend;
  final VoidCallback onSendVoice;
  final Future<void> Function() onHoldStart;
  final void Function(double dx) onHoldUpdate;
  final Future<void> Function() onHoldEnd;

  @override
  Widget build(BuildContext context) {
    if (stage == VoiceComposerStage.preview) {
      return IconButton.filled(
        key: const Key('voice-send'),
        onPressed: onSendVoice,
        style: IconButton.styleFrom(
          backgroundColor: PrivioColors.accent,
          foregroundColor: PrivioColors.background,
        ),
        icon: const Icon(Icons.send_rounded, size: 20),
        tooltip: 'Send',
      );
    }

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final hasText = value.text.trim().isNotEmpty;
        if (hasText && stage == VoiceComposerStage.idle) {
          return IconButton.filled(
            onPressed: onSend,
            style: IconButton.styleFrom(
              backgroundColor: PrivioColors.accent,
              foregroundColor: PrivioColors.background,
            ),
            icon: const Icon(Icons.send_rounded, size: 20),
            tooltip: 'Send',
          );
        }

        final recording = stage != VoiceComposerStage.idle;
        return GestureDetector(
          key: const Key('voice-hold'),
          onLongPressStart: (_) => unawaited(onHoldStart()),
          onLongPressMoveUpdate: (details) => onHoldUpdate(details.offsetFromOrigin.dx),
          onLongPressEnd: (_) => unawaited(onHoldEnd()),
          // A tap is a common mis-hold, and starting a recording nobody meant
          // to start is worse than saying what the gesture is.
          onTap: recording
              ? null
              : () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Hold the microphone to record a voice message.'),
                      duration: Duration(seconds: 2),
                    ),
                  ),
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: recording ? PrivioColors.accent : PrivioColors.surfaceRaised,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.mic_rounded,
              size: 20,
              color: recording ? PrivioColors.background : PrivioColors.textSecondary,
            ),
          ),
        );
      },
    );
  }
}

/// The strip above the composer while a reply is being written.
class _ReplyBar extends StatelessWidget {
  const _ReplyBar({required this.message, required this.onCancel});

  final Message message;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(
        PrivioSpacing.gutter,
        PrivioSpacing.sm,
        PrivioSpacing.sm,
        PrivioSpacing.sm,
      ),
      decoration: const BoxDecoration(
        color: PrivioColors.surface,
        border: Border(
          top: BorderSide(color: PrivioColors.border),
          left: BorderSide(color: PrivioColors.accent, width: 3),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  switch ((message.isMine, message.senderName)) {
                    (true, _) => 'Replying to yourself',
                    // In a group the quote is meaningless without the name;
                    // in a 1:1 chat the header already says who.
                    (false, final String name) => 'Replying to $name',
                    (false, null) => 'Replying',
                  },
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: PrivioColors.accentBright,
                  ),
                ),
                Text(
                  ConversationController.previewOfMessage(message),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onCancel,
            icon: const Icon(Icons.close_rounded, size: 20),
            tooltip: 'Cancel reply',
          ),
        ],
      ),
    );
  }
}
