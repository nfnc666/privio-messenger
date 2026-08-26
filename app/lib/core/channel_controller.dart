import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/channel.dart';
import '../services/channel_service.dart';
import 'api_client.dart';
import 'privio_services.dart';

/// Drives the channel screens.
///
/// Holds the lists the UI shows and turns server error codes into sentences.
/// Keys never leave [ChannelService]; this class only knows whether a channel
/// has one, which is all the UI needs to decide between a feed and a padlock.
class ChannelController extends ChangeNotifier {
  ChannelController(this._services) {
    _services.channels.keyArrived.addListener(_onKeyArrived);
  }

  final PrivioServices _services;

  ChannelService get _channels => _services.channels;

  /// A key landed for a channel this device could not read. Refresh what is on
  /// screen rather than making the reader guess that something changed.
  void _onKeyArrived() {
    final channelId = _channels.keyArrived.value;
    if (channelId == null) return;
    unawaited(refresh());
    if (_posts.containsKey(channelId)) unawaited(loadPosts(channelId));
  }

  @override
  void dispose() {
    _services.channels.keyArrived.removeListener(_onKeyArrived);
    super.dispose();
  }

  List<ChannelInfo> _mine = const [];
  List<ChannelInfo> _discovered = const [];
  final Map<String, List<ChannelPost>> _posts = {};
  final Map<String, List<ChannelMember>> _members = {};

  bool _loading = false;
  String? _error;

  List<ChannelInfo> get mine => _mine;
  List<ChannelInfo> get discovered => _discovered;
  bool get loading => _loading;

  /// The last failure worth showing, cleared by the next call that works.
  String? get error => _error;

  List<ChannelPost> postsIn(String channelId) => _posts[channelId] ?? const [];

  List<ChannelMember> membersOf(String channelId) => _members[channelId] ?? const [];

  ChannelInfo? channelById(String id) {
    for (final channel in _mine) {
      if (channel.id == id) return channel;
    }
    for (final channel in _discovered) {
      if (channel.id == id) return channel;
    }
    return null;
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  // --- Loading --------------------------------------------------------------

  Future<void> refresh() async {
    await _run(() async => _mine = await _channels.mine());
    // Anyone who joined by a link is waiting on a member with the key. This
    // device may be that member.
    unawaited(deliverPendingKeys());
  }

  Future<void> search({String? query, String? category}) async {
    await _run(
      () async => _discovered = await _channels.discover(query: query, category: category),
    );
  }

  Future<void> loadPosts(String channelId) async {
    await _run(() async => _posts[channelId] = await _channels.posts(channelId));
    // Someone reading a channel is someone who holds its key, which makes this
    // the best moment to answer whoever joined by a link and is still waiting.
    unawaited(_deliverFor(channelId));
  }

  Future<void> _deliverFor(String channelId) async {
    try {
      await _channels.deliverPendingKeys(channelId);
    } on Object {
      // Retried on the next load; a failed delivery is not the reader's problem.
    }
  }

  Future<void> loadMembers(String channelId) async {
    await _run(() async => _members[channelId] = await _channels.members(channelId));
  }

  // --- Acting ---------------------------------------------------------------

  Future<ChannelInfo?> create({
    required ChannelVisibility visibility,
    required String title,
    String? handle,
    String? description,
    String? category,
    bool restrictSaving = false,
  }) async {
    ChannelInfo? created;
    await _run(() async {
      created = await _channels.create(
        visibility: visibility,
        title: title,
        handle: handle,
        description: description,
        category: category,
        restrictSaving: restrictSaving,
      );
      _mine = [created!, ..._mine];
    });
    return created;
  }

  Future<bool> publish(String channelId, String body) async {
    final text = body.trim();
    if (text.isEmpty) return false;
    return _run(() async {
      await _channels.publish(channelId, text);
      // Re-read rather than append locally: the server assigns the id and the
      // timestamp, and a feed that disagrees with them is worse than a wait.
      _posts[channelId] = await _channels.posts(channelId);
    });
  }

  Future<bool> join(ChannelInfo channel, {String? inviteCode}) => _run(() async {
        final joined = await _channels.join(channel, inviteCode: inviteCode);
        _mine = [joined, ..._mine.where((c) => c.id != joined.id)];
        _discovered = [
          for (final c in _discovered) if (c.id == joined.id) joined else c,
        ];
      });

  /// Opens a channel invite link: resolves the channel and joins it. The key
  /// follows on its own, delivered by a member who already has it.
  Future<ChannelInfo?> openInvite(String link) async {
    final invite = ChannelService.parseInviteLink(link);
    if (invite == null) {
      _error = 'That does not look like a Privio channel link.';
      notifyListeners();
      return null;
    }
    ChannelInfo? channel;
    await _run(() async {
      final found = await _channels.byInvite(invite.code);
      final joined = await _channels.join(found, inviteCode: invite.code);
      _mine = [joined, ..._mine.where((c) => c.id != joined.id)];
      channel = joined;
    });
    return channel;
  }

  Future<bool> leave(String channelId) => _run(() async {
        await _channels.leave(channelId);
        _mine = [for (final c in _mine) if (c.id != channelId) c];
        _posts.remove(channelId);
        _members.remove(channelId);
      });

  Future<bool> delete(String channelId) => _run(() async {
        await _channels.delete(channelId);
        _mine = [for (final c in _mine) if (c.id != channelId) c];
        _posts.remove(channelId);
        _members.remove(channelId);
      });

  Future<bool> setRole({
    required String channelId,
    required ChannelMember member,
    required String role,
    ChannelPermissions? permissions,
  }) =>
      _run(() async {
        final updated = await _channels.setRole(
          channelId: channelId,
          member: member,
          role: role,
          permissions: permissions,
        );
        _members[channelId] = [
          for (final m in membersOf(channelId)) if (m.id == updated.id) updated else m,
        ];
      });

  Future<bool> removeMember(String channelId, String accountId) => _run(() async {
        await _channels.removeMember(channelId, accountId);
        _members[channelId] = [
          for (final m in membersOf(channelId)) if (m.id != accountId) m,
        ];
      });

  Future<bool> pin(String channelId, int postId, {required bool pinned}) => _run(() async {
        await _channels.pin(channelId, postId, pinned: pinned);
        _posts[channelId] = await _channels.posts(channelId);
      });

  Future<bool> deletePost(String channelId, int postId) => _run(() async {
        await _channels.deletePost(channelId, postId);
        _posts[channelId] = [
          for (final p in postsIn(channelId)) if (p.id != postId) p,
        ];
      });

  /// The share link for a channel. Safe to post anywhere: it carries the code
  /// and no key.
  String? inviteLink(ChannelInfo channel) =>
      channel.inviteCode == null ? null : ChannelService.linkForChannel(channel.inviteCode!);

  /// Answers everyone waiting for the key to a channel this device can read.
  ///
  /// Called on every channel refresh, because a new member's padlocks only
  /// clear when someone who holds the key next opens the app.
  Future<void> deliverPendingKeys() async {
    for (final channel in _mine) {
      if (!channel.hasKey) continue;
      await _deliverFor(channel.id);
    }
  }

  // --- Plumbing -------------------------------------------------------------

  Future<bool> _run(Future<void> Function() action) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await action();
      return true;
    } on ApiException catch (failure) {
      _error = _explain(failure);
      return false;
    } on StateError catch (failure) {
      _error = failure.message;
      return false;
    } on Object {
      _error = 'Could not reach Privio. Check your connection.';
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// The permission failures deserve plain wording: they are the rules working,
  /// and a user who hits one should learn what the rule is.
  static String _explain(ApiException failure) => switch (failure.code) {
        'handle_taken' => 'That handle is already in use.',
        'channel_not_found' => 'That channel does not exist, or the link is wrong.',
        'not_a_member' => 'You are not in this channel.',
        'insufficient_permission' => 'You do not have permission to do that.',
        'cannot_change_own_role' => 'You cannot change your own role.',
        'owner_is_fixed' => 'The channel owner cannot be changed or removed.',
        'target_outranks_you' => 'That member holds permissions you do not.',
        'cannot_grant_what_you_lack' => 'You cannot grant a permission you do not hold yourself.',
        'owner_cannot_leave' => 'Hand the channel over or delete it instead.',
        'invalid_request' => failure.message,
        'rate_limited' => 'Too many requests. Wait a moment.',
        _ => failure.message,
      };
}
