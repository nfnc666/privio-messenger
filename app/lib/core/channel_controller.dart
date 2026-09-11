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
  final Map<String, bool> _membersComplete = {};

  bool _loading = false;
  String? _error;

  List<ChannelInfo> get mine => _mine;
  List<ChannelInfo> get discovered => _discovered;
  bool get loading => _loading;

  /// The last failure worth showing, cleared by the next call that works.
  String? get error => _error;

  List<ChannelPost> postsIn(String channelId) => _posts[channelId] ?? const [];

  List<ChannelMember> membersOf(String channelId) => _members[channelId] ?? const [];

  /// Whether [membersOf] is everybody. False for a subscriber, who is shown
  /// the channel's staff instead of its audience.
  bool membersAreComplete(String channelId) => _membersComplete[channelId] ?? false;

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
    await _run(() async {
      final roster = await _channels.members(channelId);
      _members[channelId] = roster.members;
      _membersComplete[channelId] = roster.complete;
    });
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

  /// Publishes a post, with a file on it or without.
  ///
  /// An empty message is still a post when it carries a file — a picture with
  /// no caption is a thing people send.
  Future<bool> publish(
    String channelId,
    String body, {
    ChannelUpload? file,
    DateTime? publishAt,
    ChannelPollDraft? poll,
  }) async {
    final text = body.trim();
    // A poll is a post even with no words around it: the question is the text.
    if (text.isEmpty && file == null && poll == null) return false;
    return _run(() async {
      await _channels.publish(
        channelId,
        text,
        file: file,
        publishAt: publishAt,
        poll: poll,
      );
      // Re-read rather than append locally: the server assigns the id and the
      // timestamp, and a feed that disagrees with them is worse than a wait.
      _posts[channelId] = await _channels.posts(channelId);
      // A post that went into the waiting room is in neither list until this
      // runs, which looks exactly like a send that failed.
      if (publishAt != null) {
        _scheduled[channelId] = await _channels.posts(channelId, scheduled: true);
      }
    });
  }

  /// Downloads and opens a post's file, or returns null and sets [error].
  Future<Uint8List?> openAttachment(String channelId, ChannelPost post) async {
    try {
      return await _channels.openAttachment(channelId, post);
    } on ApiException catch (failure) {
      _error = _explain(failure);
    } on Object {
      _error = 'Could not open that file.';
    }
    notifyListeners();
    return null;
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
        _membersComplete.remove(channelId);
      });

  Future<bool> delete(String channelId) => _run(() async {
        await _channels.delete(channelId);
        _mine = [for (final c in _mine) if (c.id != channelId) c];
        _posts.remove(channelId);
        _members.remove(channelId);
        _membersComplete.remove(channelId);
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
        // Removing somebody advances the channel's key version on the server;
        // the replacement key does not exist until a device makes one. Doing it
        // here, on the device that just did the removing, is what turns a
        // removal into something that has actually happened rather than
        // something that will happen when an admin next opens the app.
        //
        // Failure is not fatal and is not hidden: the channel shows as awaiting
        // its key until this succeeds, here or on another device.
        await _channels.completeRotation(channelId);
        await _refreshKeyState(channelId);
      });

  Future<bool> pin(String channelId, int postId, {required bool pinned}) => _run(() async {
        await _channels.pin(channelId, postId, pinned: pinned);
        _posts[channelId] = await _channels.posts(channelId);
      });

  /// Posts waiting for their time, per channel. Only ever filled for a channel
  /// this account may publish in — the server refuses the query to anyone else.
  final Map<String, List<ChannelPost>> _scheduled = {};

  List<ChannelPost> scheduledIn(String channelId) => _scheduled[channelId] ?? const [];

  Future<void> loadScheduled(String channelId) async {
    await _run(() async {
      _scheduled[channelId] = await _channels.posts(channelId, scheduled: true);
    });
  }

  /// Rewrites a post, or moves when it appears.
  ///
  /// Reloads both lists afterwards: publishing a waiting post moves it from one
  /// to the other, and showing it in neither for a moment looks like it was
  /// lost.
  Future<bool> editPost(
    String channelId,
    ChannelPost post,
    String body, {
    DateTime? publishAt,
    bool clearSchedule = false,
  }) =>
      _run(() async {
        await _channels.edit(
          channelId,
          post,
          body,
          publishAt: publishAt,
          clearSchedule: clearSchedule,
        );
        _posts[channelId] = await _channels.posts(channelId);
        _scheduled[channelId] = await _channels.posts(channelId, scheduled: true);
      });

  /// Sends this account's whole answer to a poll and keeps the fresh tallies.
  ///
  /// Not through [_run], for the same reason a reaction is not: a spinner over
  /// the whole feed because somebody answered a poll is a worse answer than the
  /// bars simply not moving. The numbers shown are the server's, never a guess.
  Future<bool> vote(String channelId, int postId, List<int> options) async {
    try {
      final (counts, voters, mine) = await _channels.vote(channelId, postId, options);
      _posts[channelId] = [
        for (final post in postsIn(channelId))
          if (post.id == postId && post.poll != null)
            post.withPoll(post.poll!.withTally(counts, voters, mine))
          else
            post,
      ];
      _error = null;
      notifyListeners();
      return true;
    } on ApiException catch (failure) {
      _error = _explain(failure);
      notifyListeners();
      return false;
    } on Object {
      _error = 'Could not reach Privio. Check your connection.';
      notifyListeners();
      return false;
    }
  }

  /// Open threads, keyed by post id. Only the ones being looked at.
  final Map<int, List<ChannelComment>> _comments = {};

  List<ChannelComment> commentsOn(int postId) => _comments[postId] ?? const [];

  Future<bool> loadComments(String channelId, int postId) => _run(() async {
        _comments[postId] = await _channels.comments(channelId, postId);
      });

  /// Adds a comment and re-reads the thread.
  ///
  /// Re-read rather than appended locally, for the same reason a post is: the
  /// server assigns the id and the timestamp, and a thread that disagrees with
  /// them is worse than a short wait. The feed is reloaded too, so the count
  /// under the post moves with it.
  Future<bool> comment(String channelId, int postId, String body) async {
    final text = body.trim();
    if (text.isEmpty) return false;
    return _run(() async {
      await _channels.comment(channelId, postId, text);
      _comments[postId] = await _channels.comments(channelId, postId);
      _posts[channelId] = await _channels.posts(channelId);
    });
  }

  Future<bool> deleteComment(String channelId, int postId, int commentId) => _run(() async {
        await _channels.deleteComment(channelId, postId, commentId);
        _comments[postId] = [
          for (final c in commentsOn(postId)) if (c.id != commentId) c,
        ];
        _posts[channelId] = await _channels.posts(channelId);
      });

  /// Changes what the invite link is allowed to do, then re-reads the channel
  /// so the sheet shows what actually took.
  Future<bool> setInviteSettings(
    String channelId, {
    DateTime? expiresAt,
    bool clearExpiry = false,
    int? maxUses,
    bool clearMaxUses = false,
    bool? needsApproval,
  }) =>
      _run(() async {
        await _channels.setInviteSettings(
          channelId,
          expiresAt: expiresAt,
          clearExpiry: clearExpiry,
          maxUses: maxUses,
          clearMaxUses: clearMaxUses,
          needsApproval: needsApproval,
        );
        _mine = await _channels.mine();
      });

  /// Revokes the link by replacing it.
  Future<bool> rotateInvite(String channelId) => _run(() async {
        await _channels.rotateInvite(channelId);
        _mine = await _channels.mine();
      });

  final Map<String, List<ChannelJoinRequest>> _knocking = {};

  List<ChannelJoinRequest> knockingAt(String channelId) => _knocking[channelId] ?? const [];

  Future<bool> loadJoinRequests(String channelId) => _run(() async {
        _knocking[channelId] = await _channels.joinRequests(channelId);
      });

  /// Lets somebody in, or turns them away. Either way they leave the queue.
  Future<bool> answerJoinRequest(
    String channelId,
    String accountId, {
    required bool admit,
  }) =>
      _run(() async {
        await _channels.answerJoinRequest(channelId, accountId, admit: admit);
        _knocking[channelId] = [
          for (final request in knockingAt(channelId))
            if (request.accountId != accountId) request,
        ];
        // Admitting somebody moves the member count, which the list shows.
        if (admit) _mine = await _channels.mine();
      });

  /// Turns threads under posts on or off for the whole channel.
  Future<bool> setCommentsEnabled(String channelId, {required bool enabled}) => _run(() async {
        await _channels.setCommentsEnabled(channelId, enabled: enabled);
        _mine = await _channels.mine();
      });

  /// Stops somebody speaking in a channel, or lets them speak again.
  ///
  /// Not the same as removing them, and the screens say so: removal rotates the
  /// key and takes their reading with it.
  Future<bool> setBanned(
    String channelId,
    String accountId, {
    required bool banned,
  }) =>
      _run(() async => _channels.setBanned(channelId, accountId, banned: banned));

  final Map<String, List<ChannelBan>> _bans = {};

  List<ChannelBan> bansIn(String channelId) => _bans[channelId] ?? const [];

  Future<bool> loadBans(String channelId) => _run(() async {
        _bans[channelId] = await _channels.bans(channelId);
      });

  /// Changes the emojis this channel offers, then reloads it so the bar under
  /// every post redraws from the new set.
  Future<bool> setReactionEmojis(String channelId, List<String> emojis) => _run(() async {
        await _channels.setReactionEmojis(channelId, emojis);
        // The list, not `refresh()`: that one runs inside `_run` already and
        // would nest the loading flag inside itself.
        _mine = await _channels.mine();
      });

  /// Puts a reaction on a post, or takes this account's own back.
  ///
  /// Deliberately not through [_run]: that one raises the whole screen's
  /// loading flag, and a spinner over a feed because somebody tapped a heart is
  /// a worse answer than the heart simply not moving. The count that comes back
  /// is the server's, not an optimistic guess — a reaction that failed must not
  /// leave a number on screen that nobody else can see.
  Future<bool> react(
    String channelId,
    int postId,
    String emoji, {
    required bool on,
  }) async {
    try {
      final (counts, mine) = await _channels.react(channelId, postId, emoji, on: on);
      _posts[channelId] = [
        for (final post in postsIn(channelId))
          if (post.id == postId) post.withReactions(counts, mine) else post,
      ];
      _error = null;
      notifyListeners();
      return true;
    } on ApiException catch (failure) {
      _error = _explain(failure);
      notifyListeners();
      return false;
    } on Object {
      _error = 'Could not reach Privio. Check your connection.';
      notifyListeners();
      return false;
    }
  }

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

  /// Both halves of channel-key housekeeping, in one walk of the list.
  ///
  /// Answers everyone waiting for the key to a channel this device can read —
  /// a new member's padlocks only clear when somebody who holds the key next
  /// opens the app — and asks where this device is a member without one.
  ///
  /// Joining records a request on the server already. Signing in does not, so
  /// a second device of an existing member is the one that has to ask.
  Future<void> deliverPendingKeys() async {
    for (final channel in _mine) {
      try {
        // A device that has been offline through a removal comes back to a
        // channel on a version it has no key for. If it may manage members it
        // finishes the rotation; otherwise it asks, and waits visibly.
        if (!channel.hasCurrentKey) {
          if (channel.permissions.canManageMembers) {
            await _channels.completeRotation(channel.id);
          } else {
            await _channels.requestKey(channel.id);
          }
          await _refreshKeyState(channel.id);
          continue;
        }
        if (channel.hasKey) {
          await _deliverFor(channel.id);
        } else {
          await _channels.requestKey(channel.id);
        }
      } on Object {
        // One channel that cannot be served is no reason to skip the rest.
        continue;
      }
    }
  }

  /// Re-reads whether this device can still read and post to a channel.
  ///
  /// Kept separate from a full refresh because it runs after a removal and
  /// after a key arrives, and both want the padlock state updated without
  /// re-fetching every channel this account is in.
  Future<void> _refreshKeyState(String channelId) async {
    try {
      final state = await _channels.currentEpoch(channelId);
      final held = await _channels.heldEpochs(channelId);
      _mine = [
        for (final c in _mine)
          if (c.id == channelId)
            c.copyWith(
              keyEpoch: state.epoch,
              hasCurrentKey: held.contains(state.epoch),
              hasKey: held.isNotEmpty,
            )
          else
            c,
      ];
      notifyListeners();
    } on Object {
      // The state on screen stays as it was, which is the honest answer when
      // the server could not be asked.
    }
  }

  // --- Plumbing -------------------------------------------------------------

  /// Asks again for the key this device is missing, for one channel.
  ///
  /// The same two moves `deliverPendingKeys` makes on start-up — finish the
  /// rotation when this account may manage members, otherwise ask a member who
  /// holds the key — but for one channel and because somebody pressed a button.
  ///
  /// The automatic attempts are invisible and can fail quietly: a rotation that
  /// needs a member who is offline, a request nobody has answered yet. Until
  /// now a channel stuck without its key showed an explanation and offered
  /// nothing to do about it, which is a dead end wearing a paragraph.
  Future<bool> retryKey(String channelId) async {
    final channel = channelById(channelId);
    if (channel == null) return false;
    return _run(() async {
      if (channel.permissions.canManageMembers) {
        await _channels.completeRotation(channelId);
      } else {
        await _channels.requestKey(channelId);
      }
      await _refreshKeyState(channelId);
    });
  }

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
