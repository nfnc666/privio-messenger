import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../l10n/app_localizations.dart';
import '../l10n/failure_text.dart';
import '../models/channel.dart';
import '../theme/privio_colors.dart';
import '../widgets/channel_appearance_sheet.dart';
import '../widgets/channel_header.dart';
import '../widgets/privio_back_button.dart';
import '../widgets/settings_row.dart';

/// What happens around a post: comments, who is named on it, what readers may
/// send back, and the welcome that greets them.
///
/// The old settings list had these interleaved with the channel's identity and
/// its member management, each behind a differently coloured icon tile. They
/// are one subject, so they are one page — and the welcome message, which used
/// to be a text field inside an alert dialog, is an ordinary field on it.
class ChannelPostsScreen extends StatefulWidget {
  const ChannelPostsScreen({required this.channel, super.key});

  final ChannelInfo channel;

  @override
  State<ChannelPostsScreen> createState() => _ChannelPostsScreenState();
}

class _ChannelPostsScreenState extends State<ChannelPostsScreen> {
  late final TextEditingController _welcome =
      TextEditingController(text: widget.channel.welcome.message ?? '');

  late bool _welcomeEnabled = widget.channel.welcome.enabled;
  late bool _showSenderName = widget.channel.showSenderName;
  late bool _directMessages = widget.channel.directMessagesEnabled;
  late String? _accent = widget.channel.appearance.accent;
  late String? _background = widget.channel.appearance.background;
  bool _saving = false;

  @override
  void dispose() {
    _welcome.dispose();
    super.dispose();
  }

  ChannelInfo get _channel =>
      PrivioScope.of(context).channels.channelById(widget.channel.id) ?? widget.channel;

  bool get _dirty =>
      _welcome.text.trim() != (_channel.welcome.message ?? '') ||
      _welcomeEnabled != _channel.welcome.enabled ||
      _showSenderName != _channel.showSenderName ||
      _directMessages != _channel.directMessagesEnabled ||
      _accent != _channel.appearance.accent ||
      _background != _channel.appearance.background;

  Future<bool> _confirmLeave() async {
    if (!_dirty) return true;
    final text = AppText.of(context);
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PrivioColors.surface,
        title: Text(text.chUnsavedTitle),
        content: Text(text.chUnsavedBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(text.chUnsavedKeep),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              text.chUnsavedDiscard,
              style: const TextStyle(color: PrivioColors.danger),
            ),
          ),
        ],
      ),
    );
    return discard == true;
  }

  Future<void> _save() async {
    final text = AppText.of(context);
    final controller = PrivioScope.of(context).channels;
    setState(() => _saving = true);
    try {
      final saved = await controller.saveSettings(
        _channel,
        showSenderName: _showSenderName,
        welcomeEnabled: _welcomeEnabled,
        welcomeMessage: _welcome.text.trim(),
        clearAccent: _accent == null,
        accent: _accent,
        clearBackground: _background == null,
        background: _background,
        directMessagesEnabled: _directMessages,
      );
      if (!mounted) return;
      if (!saved) {
        _say(controller.failure?.words(text) ?? text.editChannelCouldNotSave);
        return;
      }
      _say(text.chSaved);
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Comments are their own call, not part of the form.
  ///
  /// Turning discussion on creates the comment surface server-side; batching
  /// that with a text field's Save would mean a half-applied page when one of
  /// the two fails.
  Future<void> _toggleComments(bool on) async {
    final text = AppText.of(context);
    final controller = PrivioScope.of(context).channels;
    setState(() => _saving = true);
    final ok = await controller.setCommentsEnabled(_channel.id, enabled: on);
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) _say(controller.failure?.words(text) ?? text.editChannelCouldNotSave);
  }

  /// The colours, in the sheet that draws the result rather than describing it.
  ///
  /// The same sheet the old settings screen used, lifted into
  /// `widgets/channel_appearance_sheet.dart` when that screen was replaced —
  /// moved, not rewritten, so the one thing on this page that was already right
  /// stayed right.
  Future<void> _openAppearance() async {
    final chosen = await showModalBottomSheet<({String? accent, String? background})>(
      context: context,
      backgroundColor: PrivioColors.surface,
      builder: (_) => ChannelAppearanceSheet(accent: _accent, background: _background),
    );
    if (chosen == null || !mounted) return;
    setState(() {
      _accent = chosen.accent;
      _background = chosen.background;
    });
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final controller = PrivioScope.of(context).channels;
    final channel = _channel;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await _confirmLeave();
        if (!leave || !mounted) return;
        Navigator.of(this.context).pop();
      },
      child: Scaffold(
        backgroundColor: PrivioColors.background,
        appBar: AppBar(
          backgroundColor: PrivioColors.background,
          leading: const PrivioBackButton(),
          title: Text(text.chPostsTitle),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: PrivioSpacing.md),
              child: TextButton(
                onPressed: _saving || !_dirty ? null : () => unawaited(_save()),
                child: Text(
                  _saving ? text.chSaving : text.commonSave,
                  style: TextStyle(
                    color: _saving || !_dirty
                        ? PrivioColors.textTertiary
                        : Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.only(bottom: PrivioSpacing.xxxl),
          children: [
            ChannelHeader(
              channel: channel,
              imageBytes: controller.avatarFor(channel),
            ),

            SettingsSection(
              caption: text.chSectionPosts,
              children: [
                SettingsRow(
                  label: text.chRowReactions,
                  value: text.chSummaryReactions(channel.reactionEmojis.length),
                  enabled: !_saving,
                  // The picker lives on the feed, which is where the emoji are
                  // drawn at the size they will be used. Two pops: this page
                  // and the settings screen above it.
                  onTap: () => Navigator.of(context).pop('reactions'),
                ),
                SettingsRow(
                  label: text.chRowDiscussion,
                  subtitle: text.discussionBody,
                  enabled: !_saving,
                  trailing: Switch(
                    value: channel.commentsEnabled,
                    onChanged: _saving
                        ? null
                        : (on) => unawaited(_toggleComments(on)),
                  ),
                ),
                SettingsRow(
                  label: text.chRowSignature,
                  subtitle: text.adminsShowSenderNameNote,
                  enabled: !_saving,
                  trailing: Switch(
                    value: _showSenderName,
                    onChanged:
                        _saving ? null : (on) => setState(() => _showSenderName = on),
                  ),
                ),
                SettingsRow(
                  label: text.chRowDirect,
                  enabled: !_saving,
                  trailing: Switch(
                    value: _directMessages,
                    onChanged:
                        _saving ? null : (on) => setState(() => _directMessages = on),
                  ),
                ),
              ],
            ),

            SettingsSection(
              caption: text.chRowWelcome,
              children: [
                SettingsRow(
                  label: text.welcomeShowToNew,
                  enabled: !_saving,
                  trailing: Switch(
                    value: _welcomeEnabled,
                    onChanged:
                        _saving ? null : (on) => setState(() => _welcomeEnabled = on),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: PrivioSpacing.lg,
                    vertical: PrivioSpacing.xs,
                  ),
                  child: TextField(
                    controller: _welcome,
                    enabled: !_saving && _welcomeEnabled,
                    maxLines: 4,
                    minLines: 2,
                    maxLength: 1024,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: text.welcomeHint,
                      border: InputBorder.none,
                      counterText: '',
                    ),
                  ),
                ),
                if (!channel.isPublic)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      PrivioSpacing.lg,
                      0,
                      PrivioSpacing.lg,
                      PrivioSpacing.md,
                    ),
                    child: Text(
                      text.welcomePrivateNote,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: PrivioColors.textTertiary),
                    ),
                  ),
              ],
            ),

            SettingsSection(
              caption: text.chRowAppearance,
              children: [
                SettingsRow(
                  label: text.chRowAppearance,
                  value: _accent == null && _background == null
                      ? text.commonDefault
                      : text.commonCustom,
                  enabled: !_saving,
                  onTap: _saving ? null : () => unawaited(_openAppearance()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
