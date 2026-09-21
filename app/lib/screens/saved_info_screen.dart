import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../l10n/app_localizations.dart';
import '../models/models.dart';
import '../theme/accent.dart';
import '../theme/privio_colors.dart';
import '../widgets/photo_viewer.dart';
import '../widgets/privio_back_button.dart';
import '../widgets/settings_row.dart';

/// What is in Saved, gathered rather than scrolled for.
///
/// A notebook's pictures and files are the thing people come back for, and
/// finding them by scrolling a year of notes is not finding them. This is the
/// same list the area already holds — `ConversationController.savedMedia()`
/// reads the conversation's own messages — presented by what they are rather
/// than by when they were written.
///
/// It is also where the two honest sentences about Saved live: that nobody
/// else can see it, and that the disappearing-message timer of ordinary chats
/// is not applied here.
class SavedInfoScreen extends StatelessWidget {
  const SavedInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = PrivioScope.of(context);
    final text = AppText.of(context);

    return ListenableBuilder(
      listenable: state.conversations,
      builder: (context, _) {
        final media = state.conversations.savedMedia();
        final pictures = [
          for (final entry in media)
            if (entry.attachment!.isImage) entry,
        ];
        final files = [
          for (final entry in media)
            if (!entry.attachment!.isImage) entry,
        ];

        return Scaffold(
          backgroundColor: PrivioColors.background,
          appBar: AppBar(
            backgroundColor: PrivioColors.background,
            leading: const PrivioBackButton(),
            title: Text(text.savedInfoTitle),
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: PrivioSpacing.xxxl),
            children: [
              const SizedBox(height: PrivioSpacing.lg),
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: context.accents.surface,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.bookmark_rounded,
                    size: 34,
                    color: context.accents.accent,
                  ),
                ),
              ),
              const SizedBox(height: PrivioSpacing.md),
              Center(
                child: Text(
                  text.savedTitle,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              const SizedBox(height: PrivioSpacing.xs),
              Center(
                child: Text(
                  text.savedChatSubtitle,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: PrivioColors.textSecondary),
                ),
              ),
              const SizedBox(height: PrivioSpacing.xl),

              SettingsSection(
                children: [
                  SettingsRow(
                    icon: Icons.timer_off_outlined,
                    label: text.savedKeptForever,
                    subtitle: text.savedNoTimerNote,
                  ),
                ],
              ),

              if (media.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    PrivioSpacing.xxl,
                    PrivioSpacing.xxl,
                    PrivioSpacing.xxl,
                    0,
                  ),
                  child: Text(
                    text.savedMediaEmpty,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: PrivioColors.textTertiary),
                  ),
                ),

              if (pictures.isNotEmpty) ...[
                const SizedBox(height: PrivioSpacing.lg),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: PrivioSpacing.gutter,
                  ),
                  child: Text(
                    text.savedMediaRow.toUpperCase(),
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(letterSpacing: 0.8),
                  ),
                ),
                const SizedBox(height: PrivioSpacing.sm),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: PrivioSpacing.gutter,
                  ),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 4,
                    crossAxisSpacing: 4,
                  ),
                  itemCount: pictures.length,
                  itemBuilder: (context, index) => _Thumb(message: pictures[index]),
                ),
              ],

              if (files.isNotEmpty) ...[
                const SizedBox(height: PrivioSpacing.lg),
                SettingsSection(
                  children: [
                    for (final entry in files)
                      SettingsRow(
                        icon: Icons.insert_drive_file_outlined,
                        label: entry.attachment!.fileName ?? entry.body,
                        value: entry.attachment!.readableSize,
                      ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// One saved picture.
///
/// The bytes are fetched the same way a bubble fetches them, through
/// `attachmentBytes` — decrypted on this device, from the key that travelled
/// inside the entry. A picture whose blob is gone draws as a plain tile rather
/// than as an error: it is still a saved entry, and the grid is not the place
/// to explain storage retention.
class _Thumb extends StatefulWidget {
  const _Thumb({required this.message});

  final Message message;

  @override
  State<_Thumb> createState() => _ThumbState();
}

class _ThumbState extends State<_Thumb> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_load()));
  }

  Future<void> _load() async {
    final bytes = await PrivioScope.of(context)
        .conversations
        .attachmentBytes(widget.message.attachment!);
    if (mounted) setState(() => _bytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    return GestureDetector(
      onTap: bytes == null
          ? null
          : () => unawaited(
                PhotoViewer.open(
                  context,
                  bytes: bytes,
                  name: widget.message.attachment!.fileName,
                ),
              ),
      child: Container(
        decoration: BoxDecoration(
          color: PrivioColors.surfaceRaised,
          borderRadius: BorderRadius.circular(PrivioSpacing.sm),
        ),
        clipBehavior: Clip.antiAlias,
        child: bytes == null
            ? null
            : Image.memory(bytes, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()),
      ),
    );
  }
}
