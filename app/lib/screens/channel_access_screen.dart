import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../l10n/app_localizations.dart';
import '../l10n/failure_text.dart';
import '../models/channel.dart';
import '../services/channel_service.dart';
import '../theme/accent.dart';
import '../theme/privio_colors.dart';
import '../widgets/channel_header.dart';
import '../widgets/privio_back_button.dart';
import '../widgets/channel_settings_tiles.dart';

/// Who can find this channel, how they get in, and who is waiting at the door.
///
/// The three were in three different places — public/private was an explanation
/// dialog on the settings list, the link settings were a bottom sheet behind
/// the feed's overflow menu, and the join queue was another entry in the same
/// menu. They answer one question, so they are one page.
///
/// Each switch here writes immediately, and that is deliberate rather than an
/// oversight: they are single independent facts, not a form. The page that has
/// a Save button is the one with text fields in it.
class ChannelAccessScreen extends StatefulWidget {
  const ChannelAccessScreen({required this.channel, super.key});

  final ChannelInfo channel;

  @override
  State<ChannelAccessScreen> createState() => _ChannelAccessScreenState();
}

class _ChannelAccessScreenState extends State<ChannelAccessScreen> {
  bool _busy = false;

  /// The limits people actually pick. A free number field invites a typo that
  /// closes a channel to everybody but one person.
  static const List<int> _useChoices = [1, 5, 10, 25, 100];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_load()));
  }

  Future<void> _load() async {
    final channel = _channel;
    if (!channel.permissions.canManageMembers) return;
    await PrivioScope.of(context).channels.loadJoinRequests(channel.id);
    if (mounted) setState(() {});
  }

  ChannelInfo get _channel =>
      PrivioScope.of(context).channels.channelById(widget.channel.id) ?? widget.channel;

  Future<void> _apply(Future<bool> Function() change) async {
    if (_busy) return;
    setState(() => _busy = true);
    final controller = PrivioScope.of(context).channels;
    final ok = await change();
    if (!mounted) return;
    setState(() => _busy = false);
    final text = AppText.of(context);
    _say(ok
        ? text.chSaved
        : controller.failure?.words(text) ?? text.feedCouldNotChangeLink);
  }

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
      _say(AppText.of(context).feedPickFutureTime);
      return;
    }
    final controller = PrivioScope.of(context).channels;
    await _apply(() => controller.setInviteSettings(_channel.id, expiresAt: when));
  }

  Future<void> _pickUses() async {
    final text = AppText.of(context);
    final chosen = await showModalBottomSheet<int?>(
      context: context,
      backgroundColor: PrivioColors.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(text.inviteNoLimit),
              onTap: () => Navigator.of(sheetContext).pop(-1),
            ),
            for (final uses in _useChoices)
              ListTile(
                title: Text('$uses'),
                onTap: () => Navigator.of(sheetContext).pop(uses),
              ),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    final controller = PrivioScope.of(context).channels;
    await _apply(
      () => chosen == -1
          ? controller.setInviteSettings(_channel.id, clearMaxUses: true)
          : controller.setInviteSettings(_channel.id, maxUses: chosen),
    );
  }

  Future<void> _replaceLink() async {
    final text = AppText.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PrivioColors.surface,
        title: Text(text.inviteReplaceTitle),
        content: Text(text.inviteReplaceBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(text.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              text.inviteReplaceIt,
              style: const TextStyle(color: PrivioColors.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final controller = PrivioScope.of(context).channels;
    await _apply(() => controller.rotateInvite(_channel.id));
  }

  Future<void> _answer(ChannelJoinRequest request, {required bool admit}) async {
    final controller = PrivioScope.of(context).channels;
    await _apply(
      () => controller.answerJoinRequest(_channel.id, request.accountId, admit: admit),
    );
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final controller = PrivioScope.of(context).channels;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final channel = _channel;
        final invite = channel.invite;
        final link = ChannelService.shareLinkFor(channel);
        final waiting = controller.knockingAt(channel.id);
        final mayManageInvites = channel.permissions.canManageInvites;
        final mayManageMembers = channel.permissions.canManageMembers;

        return Scaffold(
          backgroundColor: PrivioColors.background,
          appBar: AppBar(
            backgroundColor: PrivioColors.background,
            leading: const PrivioBackButton(),
            title: Text(text.chAccessTitle),
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: PrivioSpacing.xxxl),
            children: [
              ChannelHeader(
                channel: channel,
                imageBytes: controller.avatarFor(channel),
              ),

              // --- Who can find it ---
              ChannelSettingsGroup(
                caption: text.chAccessWho,
                // Said rather than offered as a switch that would half-work:
                // public and private decide whether the name is a plaintext
                // column or a sealed blob, and moving either way means
                // re-sealing or publishing everything.
                footnote: channel.isPublic
                    ? text.visibilityPublicBody(channel.handle ?? '')
                    : text.visibilityPrivateBody,
                children: [
                  ChannelSettingsTile(
                    icon: channel.isPublic ? Icons.public_rounded : Icons.lock_outline_rounded,
                    title: channel.isPublic ? text.channelPublic : text.channelPrivate,
                    summary: channel.isPublic
                        ? '@${channel.handle ?? ''}'
                        : text.chSummaryPrivate,
                  ),
                ],
              ),

              // --- The link ---
              if (link != null)
                ChannelSettingsGroup(
                  caption: text.chRowInvites,
                  children: [
                    ChannelSettingsTile(
                      icon: Icons.copy_rounded,
                      title: text.channelCopyLink,
                      summary: link,
                      summaryLines: 1,
                      enabled: !_busy,
                      onTap: () async {
                        await Clipboard.setData(ClipboardData(text: link));
                        _say(text.channelLinkCopied);
                      },
                    ),
                    if (mayManageInvites) ...[
                      ChannelSettingsTile(
                        icon: Icons.verified_user_outlined,
                        title: text.inviteAskMeFirst,
                        summary: text.inviteAskMeFirstNote,
                        summaryLines: 3,
                        enabled: !_busy,
                        trailing: Switch(
                          value: invite.needsApproval,
                          onChanged: _busy
                              ? null
                              : (on) => unawaited(_apply(
                                    () => controller.setInviteSettings(
                                      channel.id,
                                      needsApproval: on,
                                    ),
                                  )),
                        ),
                      ),
                      ChannelSettingsTile(
                        icon: Icons.schedule_rounded,
                        title: text.inviteExpiresLabel,
                        summary: invite.expiresAt == null
                            ? text.inviteNever
                            : MaterialLocalizations.of(context)
                                .formatMediumDate(invite.expiresAt!.toLocal()),
                        enabled: !_busy,
                        onTap: () => unawaited(_pickExpiry()),
                      ),
                      ChannelSettingsTile(
                        icon: Icons.tag_rounded,
                        title: text.inviteHowMany,
                        summary: invite.maxUses == null
                            ? text.inviteNoLimit
                            : text.inviteUsedOf(invite.uses, invite.maxUses!),
                        enabled: !_busy,
                        onTap: () => unawaited(_pickUses()),
                      ),
                      ChannelSettingsTile(
                        icon: Icons.autorenew_rounded,
                        title: text.inviteReplaceLink,
                        summary: text.inviteReplaceNote,
                        summaryLines: 3,
                        tone: ChannelTileTone.danger,
                        enabled: !_busy,
                        onTap: () => unawaited(_replaceLink()),
                      ),
                    ],
                  ],
                ),

              // --- Who is waiting ---
              if (mayManageMembers && invite.needsApproval)
                ChannelSettingsGroup(
                  caption: text.chRowRequests,
                  footnote: waiting.isEmpty ? text.chSummaryRequests(0) : null,
                  children: [
                    for (final request in waiting)
                      _RequestTile(
                        request: request,
                        busy: _busy,
                        onAdmit: () => unawaited(_answer(request, admit: true)),
                        onRefuse: () => unawaited(_answer(request, admit: false)),
                      ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Somebody waiting at the door, with the two answers an admin can give.
///
/// Admit is the filled accent button and refuse the quiet red one, so the two
/// cannot be told apart only by an icon somebody has to know.
class _RequestTile extends StatelessWidget {
  const _RequestTile({
    required this.request,
    required this.busy,
    required this.onAdmit,
    required this.onRefuse,
  });

  final ChannelJoinRequest request;
  final bool busy;
  final VoidCallback onAdmit;
  final VoidCallback onRefuse;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final theme = Theme.of(context);
    final accents = context.accents;
    final name = request.displayName ?? request.username;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: PrivioSpacing.lg,
        vertical: PrivioSpacing.md,
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 19,
            backgroundColor: accents.surface,
            child: Text(
              name.isEmpty ? '?' : name.characters.first.toUpperCase(),
              style: TextStyle(color: accents.bright, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  '@${request.username}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: PrivioColors.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: text.commonCancel,
            onPressed: busy ? null : onRefuse,
            style: IconButton.styleFrom(
              backgroundColor: PrivioColors.danger.withValues(alpha: 0.14),
            ),
            icon: const Icon(Icons.close_rounded, color: PrivioColors.danger),
          ),
          const SizedBox(width: PrivioSpacing.xs),
          IconButton.filled(
            tooltip: text.commonOk,
            onPressed: busy ? null : onAdmit,
            style: IconButton.styleFrom(
              backgroundColor: accents.accent,
              foregroundColor: accents.onAccent,
            ),
            icon: const Icon(Icons.check_rounded),
          ),
        ],
      ),
    );
  }
}
