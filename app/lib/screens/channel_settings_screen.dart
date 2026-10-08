import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../l10n/app_localizations.dart';
import '../l10n/failure_text.dart';
import '../models/channel.dart';
import '../services/channel_service.dart';
import '../theme/privio_colors.dart';
import '../widgets/channel_header.dart';
import '../widgets/privio_back_button.dart';
import '../widgets/channel_settings_tiles.dart';
import 'channel_access_screen.dart';
import 'channel_admins_screen.dart';
import 'channel_posts_screen.dart';
import 'channel_profile_edit_screen.dart';
import 'channel_subscribers_screen.dart';

/// Everything a channel is set to, in one place, under its own headings.
///
/// This replaces a settings page that was a single list of rows in the order
/// another messenger puts them, each with a differently coloured icon tile.
/// What is different here is not the colours:
///
/// * **The header is compact and left-aligned.** A picture, a name and one line
///   of description on one row, rather than a third of a phone spent on a
///   centred circle before the first setting.
/// * **Rows carry their current value.** "What is this channel set to" is the
///   question somebody opens this screen with, and every row answers it without
///   being opened — *Public · @handle*, *3 administrators*, *Signature on*.
/// * **One accent, used for what is interactive.** Not a blue megaphone beside a
///   red heart beside a purple hand: every icon sits in a tile of the person's
///   own accent and means "this does something", so it cannot also mean six
///   unrelated things. Red is kept for what cannot be undone.
/// * **The title owns its line.** The summary sits under it, never beside it, so
///   a long description or a large text size cannot squeeze the title into a
///   column one letter wide — which the first version did on a real phone.
/// * **Order carries the weight.** No row is drawn larger than another to say it
///   matters more; the sections say that, and the dangerous ones sit last,
///   after a gap, under their own caption.
///
/// Rows appear only where the permission does. That is a courtesy to the
/// reader, not a security measure — every one of these is checked again on the
/// server, which is where it counts.
class ChannelSettingsScreen extends StatefulWidget {
  const ChannelSettingsScreen({required this.channel, super.key});

  final ChannelInfo channel;

  @override
  State<ChannelSettingsScreen> createState() => _ChannelSettingsScreenState();
}

class _ChannelSettingsScreenState extends State<ChannelSettingsScreen> {
  ChannelLive? _live;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_load()));
  }

  Future<void> _load() async {
    final controller = PrivioScope.of(context).channels;
    final channel = _channel;
    // Asked for rather than assumed: whether anybody is waiting at the door is
    // a summary this screen shows, and a stale zero is worse than a blank.
    if (channel.permissions.canManageMembers && channel.invite.needsApproval) {
      await controller.loadJoinRequests(channel.id);
    }
    final live = await controller.live(channel.id);
    if (mounted) setState(() => _live = live);
  }

  ChannelInfo get _channel =>
      PrivioScope.of(context).channels.channelById(widget.channel.id) ?? widget.channel;

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => screen));
    if (mounted) await _load();
  }

  // --- The things that cannot be undone -------------------------------------

  Future<void> _transfer() async {
    // The admin screen owns handing a channel on: it is the screen that knows
    // who the candidates are. This is a way in, not a second implementation.
    await _open(ChannelAdminsScreen(channel: _channel));
  }

  Future<void> _delete() async {
    final channel = _channel;
    final text = AppText.of(context);
    final typed = TextEditingController();

    final sure = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PrivioColors.surface,
        title: Text(text.chDeleteTitle(channel.title)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text.chDeleteBody),
            const SizedBox(height: PrivioSpacing.md),
            // Typed back rather than a second "are you sure": a confirmation
            // somebody can tap through twice is one tap of muscle memory from
            // being no confirmation at all.
            TextField(
              controller: typed,
              autofocus: true,
              decoration: InputDecoration(hintText: text.chDeleteConfirmHint),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(text.commonCancel),
          ),
          ListenableBuilder(
            listenable: typed,
            builder: (_, __) => TextButton(
              onPressed: typed.text.trim() == channel.title
                  ? () => Navigator.of(dialogContext).pop(true)
                  : null,
              child: Text(
                text.chDeleteAction,
                style: TextStyle(
                  color: typed.text.trim() == channel.title
                      ? PrivioColors.danger
                      : PrivioColors.textTertiary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
    typed.dispose();
    if (sure != true || !mounted) return;

    setState(() => _busy = true);
    final controller = PrivioScope.of(context).channels;
    final gone = await controller.delete(channel.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!gone) {
      _say(controller.failure?.words(AppText.of(context)) ??
          AppText.of(context).chCouldNotDelete);
      return;
    }
    _say(AppText.of(context).chDeleted);
    // Two pops: this screen and the feed behind it. The channel is gone from
    // both, and leaving the feed up would leave a screen pointed at nothing.
    Navigator.of(context).pop('deleted');
  }

  Future<void> _leave() async {
    final text = AppText.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PrivioColors.surface,
        title: Text(text.channelLeaveTitle),
        content: Text(text.channelLeaveBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(text.channelStay),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              text.groupLeave,
              style: const TextStyle(color: PrivioColors.danger),
            ),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    final controller = PrivioScope.of(context).channels;
    if (await controller.leave(_channel.id) && mounted) {
      Navigator.of(context).pop('left');
    }
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // --- Summaries ------------------------------------------------------------

  String _visibilitySummary(AppText text, ChannelInfo channel) => channel.isPublic
      ? text.chSummaryPublic('@${channel.handle ?? ''}')
      : text.chSummaryPrivate;

  String _livestreamSummary(AppText text) {
    final live = _live;
    if (live == null || !live.available) return text.chSummaryLivestreamOff;
    return live.isRunning
        ? text.chSummaryLivestreamRunning
        : text.chSummaryLivestreamReady;
  }

  @override
  Widget build(BuildContext context) {
    final state = PrivioScope.of(context);
    final text = AppText.of(context);
    final controller = state.channels;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final channel = _channel;
        final permissions = channel.permissions;
        final link = ChannelService.shareLinkFor(channel);
        final description = channel.description?.trim();

        return Scaffold(
          backgroundColor: PrivioColors.background,
          appBar: AppBar(
            backgroundColor: PrivioColors.background,
            leading: const PrivioBackButton(),
            title: Text(text.channelSettings),
          ),
          body: Stack(
            children: [
              ListView(
                padding: const EdgeInsets.only(bottom: PrivioSpacing.xxxl),
                children: [
                  ChannelHeader(
                    card: true,
                    channel: channel,
                    imageBytes: controller.avatarFor(channel),
                    // The audience, not the description: the description is
                    // what the first row under here is about, and a header
                    // that said it first would make that row redundant.
                    showDescription: false,
                  ),

                  // --- Channel profile ---
                  ChannelSettingsGroup(
                    caption: text.chSectionProfile,
                    children: [
                      ChannelSettingsTile(
                        icon: Icons.badge_outlined,
                        title: text.chRowProfile,
                        summary: (description?.isNotEmpty ?? false)
                            ? description
                            : text.chSummaryNoDescription,
                        enabled: permissions.canEditChannel,
                        onTap: () => unawaited(
                          _open(ChannelProfileEditScreen(channel: channel)),
                        ),
                      ),
                      ChannelSettingsTile(
                        icon: Icons.link_rounded,
                        title: text.chRowLink,
                        summary: link ?? text.chSummaryNoLink,
                        summaryLines: 1,
                        onTap: link == null
                            ? null
                            : () => unawaited(_open(ChannelAccessScreen(channel: channel))),
                      ),
                    ],
                  ),

                  // --- Access & invitations ---
                  ChannelSettingsGroup(
                    caption: text.chSectionAccess,
                    children: [
                      ChannelSettingsTile(
                        icon: channel.isPublic
                            ? Icons.public_rounded
                            : Icons.lock_outline_rounded,
                        title: text.chRowVisibility,
                        summary: _visibilitySummary(text, channel),
                        onTap: () => unawaited(_open(ChannelAccessScreen(channel: channel))),
                      ),
                      if (permissions.canManageInvites)
                        ChannelSettingsTile(
                          icon: Icons.person_add_alt_1_rounded,
                          title: text.chRowInvites,
                          summary: channel.invite.needsApproval
                              ? text.inviteNeedsApproval
                              : text.inviteOpenJoin,
                          onTap: () =>
                              unawaited(_open(ChannelAccessScreen(channel: channel))),
                        ),
                      if (permissions.canManageMembers && channel.invite.needsApproval)
                        ChannelSettingsTile(
                          icon: Icons.how_to_reg_rounded,
                          title: text.chRowRequests,
                          summary: text.chSummaryRequests(
                            controller.knockingAt(channel.id).length,
                          ),
                          onTap: () =>
                              unawaited(_open(ChannelAccessScreen(channel: channel))),
                        ),
                    ],
                  ),

                  // --- Team & members ---
                  ChannelSettingsGroup(
                    caption: text.chSectionTeam,
                    children: [
                      ChannelSettingsTile(
                        icon: Icons.admin_panel_settings_outlined,
                        title: text.chRowAdmins,
                        summary: text.chSummaryAdmins(controller.adminsOf(channel.id).length),
                        onTap: () =>
                            unawaited(_open(ChannelAdminsScreen(channel: channel))),
                      ),
                      ChannelSettingsTile(
                        icon: Icons.groups_rounded,
                        title: text.chRowSubscribers,
                        summary: text.chSummarySubscribers(channel.memberCount),
                        onTap: () =>
                            unawaited(_open(ChannelSubscribersScreen(channel: channel))),
                      ),
                    ],
                  ),

                  // --- Posts & interaction ---
                  ChannelSettingsGroup(
                    caption: text.chSectionPosts,
                    footnote: permissions.canEditChannel ? null : text.chReadOnlyNote,
                    children: [
                      ChannelSettingsTile(
                        icon: Icons.add_reaction_outlined,
                        title: text.chRowReactions,
                        summary: text.chSummaryReactions(channel.reactionEmojis.length),
                        enabled: permissions.canEditChannel,
                        onTap: () => Navigator.of(context).pop('reactions'),
                      ),
                      ChannelSettingsTile(
                        icon: Icons.forum_outlined,
                        title: text.chRowDiscussion,
                        status: channel.commentsEnabled,
                        enabled: permissions.canEditChannel,
                        onTap: () => unawaited(_open(ChannelPostsScreen(channel: channel))),
                      ),
                      ChannelSettingsTile(
                        icon: Icons.draw_outlined,
                        title: text.chRowSignature,
                        status: channel.showSenderName,
                        enabled: permissions.canEditChannel,
                        onTap: () => unawaited(_open(ChannelPostsScreen(channel: channel))),
                      ),
                      if (permissions.canEditChannel) ...[
                        ChannelSettingsTile(
                          icon: Icons.chat_bubble_outline_rounded,
                          title: text.chRowDirect,
                          status: channel.directMessagesEnabled,
                          onTap: () =>
                              unawaited(_open(ChannelPostsScreen(channel: channel))),
                        ),
                        ChannelSettingsTile(
                          icon: Icons.waving_hand_outlined,
                          title: text.chRowWelcome,
                          status: channel.welcome.enabled,
                          onTap: () =>
                              unawaited(_open(ChannelPostsScreen(channel: channel))),
                        ),
                        ChannelSettingsTile(
                          icon: Icons.palette_outlined,
                          title: text.chRowAppearance,
                          summary: channel.appearance.accent == null &&
                                  channel.appearance.background == null
                              ? text.commonDefault
                              : text.commonCustom,
                          onTap: () =>
                              unawaited(_open(ChannelPostsScreen(channel: channel))),
                        ),
                      ],
                    ],
                  ),

                  // --- Integrations ---
                  ChannelSettingsGroup(
                    caption: text.chSectionIntegrations,
                    footnote: text.chIntegrationsNote,
                    children: [
                      ChannelSettingsTile(
                        icon: Icons.sensors_rounded,
                        title: text.chRowLivestream,
                        summary: _livestreamSummary(text),
                        // The feed owns the livestream flow, which needs the
                        // player. This says what state it is in and sends you
                        // where it happens rather than starting a second one.
                        onTap: () => Navigator.of(context).pop('live'),
                      ),
                      if (permissions.canEditChannel)
                        ChannelSettingsTile(
                          icon: Icons.insights_rounded,
                          title: text.chRowStatistics,
                          onTap: () => Navigator.of(context).pop('stats'),
                        ),
                    ],
                  ),

                  // --- What cannot be undone ---
                  const SizedBox(height: PrivioSpacing.lg),
                  ChannelSettingsGroup(
                    caption: text.chSectionDanger,
                    tone: ChannelTileTone.danger,
                    footnote: text.chDangerNote,
                    children: [
                      if (channel.role == 'owner')
                        ChannelSettingsTile(
                          icon: Icons.swap_horiz_rounded,
                          title: text.chRowTransfer,
                          tone: ChannelTileTone.danger,
                          enabled: !_busy,
                          onTap: () => unawaited(_transfer()),
                        ),
                      if (permissions.canDeleteChannel)
                        ChannelSettingsTile(
                          icon: Icons.delete_outline_rounded,
                          title: text.chRowDelete,
                          tone: ChannelTileTone.danger,
                          enabled: !_busy,
                          onTap: () => unawaited(_delete()),
                        ),
                      if (channel.isMember && channel.role != 'owner')
                        ChannelSettingsTile(
                          icon: Icons.logout_rounded,
                          title: text.chRowLeave,
                          tone: ChannelTileTone.danger,
                          enabled: !_busy,
                          onTap: () => unawaited(_leave()),
                        ),
                    ],
                  ),
                ],
              ),
              if (_busy)
                const ColoredBox(
                  color: Color(0x99000000),
                  child: Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        );
      },
    );
  }
}
