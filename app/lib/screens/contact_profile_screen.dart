import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../calls/call.dart';
import '../calls/call_signal.dart';
import '../core/app_state.dart';
import '../core/api_client.dart';
import '../core/contact_profile_controller.dart';
import '../data/message_store.dart';
import '../l10n/app_localizations.dart';
import '../theme/accent.dart';
import '../theme/privio_colors.dart';
import '../widgets/avatar.dart';
import '../widgets/photo_viewer.dart';
import '../widgets/privio_back_button.dart';
import 'chat_screen.dart';

class ContactProfileScreen extends StatefulWidget {
  const ContactProfileScreen({required this.accountId, this.returnToChat = false, super.key});

  final String accountId;
  final bool returnToChat;

  @override
  State<ContactProfileScreen> createState() => _ContactProfileScreenState();
}

class _ContactProfileScreenState extends State<ContactProfileScreen> with WidgetsBindingObserver {
  ContactProfileController? _controller;
  Uint8List? _avatar;
  String? _avatarId;
  Timer? _expiry;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    _controller = ContactProfileController(PrivioScope.of(context).services.api, widget.accountId)
      ..addListener(_changed);
    unawaited(_controller!.load());
  }

  void _changed() {
    if (!mounted) return;
    final profile = _controller!.profile;
    if (profile == null) {
      _avatar = null;
      _avatarId = null;
    } else if (profile.avatarMediaId != _avatarId) {
      _avatar = null;
      _avatarId = profile.avatarMediaId;
      unawaited(_loadAvatar(profile));
    }
    _expiry?.cancel();
    final expires = profile?.status.expiresAt;
    if (expires != null && expires.isAfter(DateTime.now())) {
      _expiry = Timer(expires.difference(DateTime.now()), () {
        if (mounted) setState(() {});
      });
    }
    setState(() {});
  }

  Future<void> _loadAvatar(ContactProfile profile) async {
    final state = PrivioScope.of(context);
    final controller = _controller!;
    final key = state.services.store.conversationWith(profile.id)?.user?.profileKey;
    try {
      // A profile lookup grants no decryption key. Never bypass E2EE visibility.
      final bytes = profile.id == state.accountId
          ? state.conversations.ownAvatar
          : key == null || profile.avatarMediaId == null
              ? null
              : await state.services.messaging.openAvatar(profile.avatarMediaId!, base64Decode(key));
      if (mounted && controller.active && identical(controller.profile, profile)) {
        setState(() => _avatar = bytes);
      }
    } on Object {
      // Missing key or unavailable picture: keep the initials, never an old image.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_controller?.load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _expiry?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _change(Future<void> Function() operation) async {
    final state = PrivioScope.of(context);
    final controller = _controller!;
    final success = await controller.change(operation);
    if (!mounted || !controller.active) return;
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppText.of(context).contactProfileError)));
    } else {
      try {
        await state.conversations.refreshContacts();
        if (controller.active) await state.security.loadBlocks();
      } on StaleSessionException {
        // The route belongs to the old login, not the replacement account.
      }
    }
  }

  void _message(ContactProfile profile) {
    final controller = _controller!;
    if (!controller.active || controller.busy || profile.isBlocked) return;
    if (widget.returnToChat) {
      Navigator.of(context).pop();
      return;
    }
    PrivioScope.of(context).services.store.upsertUser(KnownUser(
      accountId: profile.id,
      username: profile.username,
      displayName: profile.displayName,
      avatarMediaId: profile.avatarMediaId,
    ));
    // Replace only this profile, not the underlying group or its draft.
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => ChatScreen(accountId: profile.id, title: profile.displayName),
    ));
  }

  Future<void> _call(ContactProfile profile, CallMedia media) async {
    if (!_controller!.active || _controller!.busy || profile.isBlocked) return;
    await PrivioScope.of(context).services.calls.place(
      CallParty(accountId: profile.id, username: profile.username), media: media,
    );
  }

  Future<void> _toggleBlock(ContactProfile profile) async {
    final controller = _controller!;
    final text = AppText.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(profile.isBlocked ? text.blockedUnblockTitle(profile.displayName) : text.chatBlock),
        content: Text(profile.isBlocked ? text.blockedUnblockBody : text.contactProfileBlockNote),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(text.commonCancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(profile.isBlocked ? text.blockedUnblock : text.chatBlock)),
        ],
      ),
    );
    if (!mounted || !controller.active || confirmed != true) return;
    // Blocking must not silently delete history or the underlying chat draft.
    await _change(() => profile.isBlocked ? controller.api.unblock(profile.id) : controller.api.block(profile.id));
  }

  @override
  Widget build(BuildContext context) {
    final state = PrivioScope.of(context);
    final text = AppText.of(context);
    final controller = _controller!;
    final profile = controller.profile;
    final own = widget.accountId == state.accountId;
    Widget body;
    if (!controller.active) {
      body = Center(child: Text(text.contactProfileSessionEnded));
    } else if (controller.loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (profile == null) {
      body = Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(controller.missing ? text.contactProfileMissing : text.contactProfileError),
        TextButton(onPressed: controller.load, child: Text(text.commonRetry)),
      ],),);
    } else {
      final seen = profile.lastSeenAt?.toLocal();
      body = ListView(padding: const EdgeInsets.all(PrivioSpacing.gutter), children: [
        Center(child: InkWell(
          onTap: _avatar == null ? null : () => PhotoViewer.open(context, bytes: _avatar!, name: profile.displayName),
          child: PrivioAvatar(label: profile.displayName, size: 112, seed: profile.id.hashCode.abs(), imageBytes: _avatar),
        ),),
        const SizedBox(height: PrivioSpacing.lg),
        Text(profile.displayName, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
        Text('@${profile.username}', textAlign: TextAlign.center),
        const SizedBox(height: PrivioSpacing.md),
        SelectableText('PRIVIO-ID: ${profile.id}', textAlign: TextAlign.center),
        if (profile.status.isSet) Padding(
          padding: const EdgeInsets.all(PrivioSpacing.md),
          child: Text([profile.status.emoji, profile.status.text].whereType<String>().join(' '), textAlign: TextAlign.center),
        ),
        if (seen != null) Text(text.contactsLastSeen(profile.username,
          '${MaterialLocalizations.of(context).formatMediumDate(seen)} ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(seen))}',
        ), textAlign: TextAlign.center,),
        if (!own) ...[
          const SizedBox(height: PrivioSpacing.lg),
          if (profile.isBlocked) Text(text.chatBlocked(profile.displayName), textAlign: TextAlign.center),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: context.accents.accent),
            onPressed: controller.busy || profile.isBlocked ? null : () => _message(profile),
            child: Text(text.contactProfileMessage),
          ),
          if (!profile.isBlocked) ...[
            ListTile(leading: const Icon(Icons.call_outlined), title: Text(text.chatVoiceCall), onTap: controller.busy ? null : () => _call(profile, CallMedia.audio)),
            ListTile(leading: const Icon(Icons.videocam_outlined), title: Text(text.chatVideoCall), onTap: controller.busy ? null : () => _call(profile, CallMedia.video)),
          ],
          ListTile(
            leading: Icon(profile.isContact ? Icons.person_remove_outlined : Icons.person_add_outlined),
            title: Text(profile.isContact ? text.contactProfileRemove : text.contactsAddTitle),
            onTap: controller.busy ? null : () => _change(() async {
              if (profile.isContact) {
                await controller.api.removeContact(profile.id);
              } else {
                await controller.api.addContactById(profile.id);
              }
            }),
          ),
          ListTile(leading: const Icon(Icons.block), title: Text(profile.isBlocked ? text.blockedUnblock : text.chatBlock), onTap: controller.busy ? null : () => _toggleBlock(profile)),
        ],
      ],);
    }
    return Scaffold(appBar: AppBar(leading: const PrivioBackButton(), title: Text(text.contactProfileTitle)), body: body);
  }
}
