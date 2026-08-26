import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
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
  });

  final String accountId;
  final String title;
  final bool isGroup;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _composer = TextEditingController();
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    _composer.clear();
    await PrivioScope.of(context).conversations.send(widget.accountId, text);
    _scrollToEnd();
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
      picked = await FilePicker.pickFiles(withData: true)
          .timeout(const Duration(minutes: 2));
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

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = PrivioScope.of(context);

    return ListenableBuilder(
      listenable: state.conversations,
      builder: (context, _) {
        final messages = state.conversations.messagesWith(widget.accountId);

        return Scaffold(
          appBar: AppBar(
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
                        widget.isGroup
                            ? _groupSubtitle(state)
                            : 'End-to-end encrypted',
                        style: theme.textTheme.labelSmall?.copyWith(color: PrivioColors.accent),
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
              IconButton(onPressed: () {}, icon: const Icon(Icons.call_outlined), tooltip: 'Voice call'),
              IconButton(onPressed: () {}, icon: const Icon(Icons.more_vert_rounded), tooltip: 'Chat options'),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.only(bottom: PrivioSpacing.md),
                  itemCount: messages.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) return const EncryptionNotice();
                    return MessageBubble(message: messages[index - 1]);
                  },
                ),
              ),
              if (state.conversations.error != null)
                _ErrorBanner(message: state.conversations.error!),
              _Composer(
                controller: _composer,
                onSend: _send,
                // Group attachments need the same per-device fan-out as group
                // text, which is not wired yet; a button that silently does
                // nothing is worse than no button.
                onAttach: widget.isGroup ? null : _attach,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: PrivioColors.danger.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(
        horizontal: PrivioSpacing.gutter,
        vertical: PrivioSpacing.sm,
      ),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: PrivioColors.danger),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.onSend,
    required this.onAttach,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback? onAttach;

  @override
  Widget build(BuildContext context) {
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
            IconButton(
              onPressed: onAttach,
              icon: Icon(
                Icons.add_rounded,
                color: onAttach == null
                    ? PrivioColors.surfaceHigh
                    : PrivioColors.textSecondary,
              ),
              tooltip: onAttach == null ? 'Files in groups are not ready yet' : 'Attach a file',
            ),
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => onSend(),
                decoration: const InputDecoration(
                  hintText: 'Type a message...',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: PrivioSpacing.sm),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                final hasText = value.text.trim().isNotEmpty;
                return IconButton.filled(
                  onPressed: hasText ? onSend : () {},
                  style: IconButton.styleFrom(
                    backgroundColor: hasText ? PrivioColors.accent : PrivioColors.surfaceRaised,
                    foregroundColor: hasText ? PrivioColors.background : PrivioColors.textSecondary,
                  ),
                  icon: Icon(hasText ? Icons.send_rounded : Icons.mic_rounded, size: 20),
                  tooltip: hasText ? 'Send' : 'Hold to record',
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
