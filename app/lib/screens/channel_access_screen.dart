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
import '../widgets/settings_row.dart';

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
              SettingsSection(
                caption: text.chAccessWho,
                children: [
                  SettingsRow(
                    label: channel.isPublic ? text.channelPublic : text.channelPrivate,
                    value: channel.isPublic
                        ? '@${channel.handle ?? ''}'
                        : text.chSummaryPrivate,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      PrivioSpacing.lg,
                      PrivioSpacing.sm,
                      PrivioSpacing.lg,
                      PrivioSpacing.md,
                    ),
                    child: Text(
                      // Said rather than offered as a switch that would
                      // half-work: public and private decide whether the name
                      // is a plaintext column or a sealed blob, and moving
                      // either way means re-sealing or publishing everything.
                      channel.isPublic
                          ? text.visibilityPublicBody(channel.handle ?? '')
                          : text.visibilityPrivateBody,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: PrivioColors.textTertiary),
                    ),
                  ),
                ],
              ),

              // --- The link ---
              if (link != null)
                SettingsSection(
                  caption: text.chRowInvites,
                  children: [
                    SettingsRow(
                      label: link,
                      value: text.channelCopyLink,
                      enabled: !_busy,
                      onTap: () async {
                        await Clipboard.setData(ClipboardData(text: link));
                        _say(text.channelLinkCopied);
                      },
                    ),
                    if (mayManageInvites) ...[
                      SettingsRow(
                        label: text.inviteAskMeFirst,
                        subtitle: text.inviteAskMeFirstNote,
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
                      SettingsRow(
                        label: text.inviteExpiresLabel,
                        value: invite.expiresAt == null
                            ? text.inviteNever
                            : MaterialLocalizations.of(context)
                                .formatMediumDate(invite.expiresAt!.toLocal()),
                        enabled: !_busy,
                        onTap: () => unawaited(_pickExpiry()),
                      ),
                      SettingsRow(
                        label: text.inviteHowMany,
                        value: invite.maxUses == null
                            ? text.inviteNoLimit
                            : text.inviteUsedOf(invite.uses, invite.maxUses!),
                        enabled: !_busy,
                        onTap: () => unawaited(_pickUses()),
                      ),
                      SettingsRow(
                        label: text.inviteReplaceLink,
                        subtitle: text.inviteReplaceNote,
                        destructive: true,
                        enabled: !_busy,
                        onTap: () => unawaited(_replaceLink()),
                      ),
                    ],
                  ],
                ),

              // --- Who is waiting ---
              if (mayManageMembers && invite.needsApproval)
                SettingsSection(
                  caption: text.chRowRequests,
                  children: [
                    if (waiting.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(PrivioSpacing.lg),
                        child: Text(
                          text.chSummaryRequests(0),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: PrivioColors.textTertiary),
                        ),
                      ),
                    for (final request in waiting)
                      ListTile(
                        title: Text(request.displayName ?? request.username),
                        subtitle: Text('@${request.username}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: text.commonOk,
                              onPressed: _busy
                                  ? null
                                  : () => unawaited(_answer(request, admit: true)),
                              icon: Icon(
                                Icons.check_rounded,
                                color: context.accents.accent,
                              ),
                            ),
                            IconButton(
                              tooltip: text.commonCancel,
                              onPressed: _busy
                                  ? null
                                  : () => unawaited(_answer(request, admit: false)),
                              icon: const Icon(
                                Icons.close_rounded,
                                color: PrivioColors.danger,
                              ),
                            ),
                          ],
                        ),
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
