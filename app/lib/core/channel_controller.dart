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

  /// Just the people running each channel, which is a different list from the
  /// audience and is visible to every member.
  final Map<String, List<ChannelMember>> _admins = {};

  /// Where the next page of members starts, or null at the end.
  final Map<String, String?> _memberCursor = {};

  /// Big enough that a small channel arrives in one go, small enough that a
  /// large one does not stall the screen.
  static const int _memberPage = 60;

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
    detached(deliverPendingKeys());
    // Pictures are fetched after the list is already on screen, not before:
    // a channel list should not wait on an image.
    detached(loadAvatars(_mine));
  }

  Future<void> search({String? query, String? category}) async {
    await _run(
      () async => _discovered = await _channels.discover(query: query, category: category),
    );
    detached(loadAvatars(_discovered));
  }

  Future<void> loadPosts(String channelId) async {
    final fetched = await _run(() async {
      _posts[channelId] = await _channels.posts(channelId);
      // Kept, so opening this channel without a network shows what was here
      // last time rather than an empty feed. Sealed with everything else, and
      // only when something actually changed.
      _cachePosts(channelId);
    });
    // Nothing came back and nothing is held: the channel is genuinely empty as
    // far as this device knows. Nothing came back but something *is* held: the
    // cache stands, which is the whole point of having one.
    if (!fetched && _posts[channelId] == null) _posts[channelId] = const [];
    // Someone reading a channel is someone who holds its key, which makes this
    // the best moment to answer whoever joined by a link and is still waiting.
    detached(_deliverFor(channelId));
  }

  /// Marks a channel read up to its newest visible post.
  ///
  /// Called when somebody opens it. The number goes to the server rather than
  /// staying here, so reading a channel on a phone clears its badge on a
  /// laptop — and the server refuses to move it backwards, so a device that was
  /// offline cannot un-read what has already been read somewhere else.
  Future<void> markRead(String channelId) async {
    final posts = postsIn(channelId);
    if (posts.isEmpty) return;
    final newest = posts.map((p) => p.id).reduce((a, b) => a > b ? a : b);
    final channel = channelById(channelId);
    // Nothing to say: the server already has this, or something further on.
    if (channel != null && channel.lastReadPostId >= newest) return;

    // The badge clears now rather than after a round trip. Reading something
    // is the kind of act whose effect should be immediate, and the worst case
    // is a number that corrects itself on the next listing.
    if (channel != null) {
      _replace(channel.copyWith(unreadCount: 0, lastReadPostId: newest));
      notifyListeners();
    }
    await _run(() async {
      final at = await _channels.markRead(channelId, newest);
      final current = channelById(channelId);
      if (current != null) _replace(current.copyWith(lastReadPostId: at));
    });
  }

  /// Hands the cached posts to whoever persists them.
  ///
  /// A callback rather than a direct dependency on the archive: the controller
  /// has no business knowing how a history is sealed, and the one place that
  /// does already seals the conversations.
  void Function(Map<String, List<ChannelPost>>)? onPostsChanged;

  /// What each channel's posts looked like the last time they were cached.
  ///
  /// Compared before asking for a write, because the archive holds *every*
  /// conversation and re-sealing all of it because somebody opened a channel
  /// and nothing had changed is a real cost for nothing. Folding a few numbers
  /// per post is orders of magnitude cheaper than the write it avoids.
  final Map<String, String> _cachedFingerprint = {};

  static String _fingerprint(List<ChannelPost> posts) {
    final buffer = StringBuffer()..write(posts.length);
    for (final post in posts) {
      buffer
        ..write(';')
        ..write(post.id)
        ..write(',')
        ..write(post.editedAt?.millisecondsSinceEpoch ?? 0)
        ..write(',')
        ..write(post.commentCount)
        ..write(',')
        // The totals, not who reacted — the server never says who, and the
        // cache has nothing more to go on than the feed does.
        ..write(post.reactions.values.fold<int>(0, (a, b) => a + b));
    }
    return buffer.toString();
  }

  void _cachePosts(String channelId) {
    final posts = _posts[channelId] ?? const <ChannelPost>[];
    final now = _fingerprint(posts);
    // Nothing here and nothing was: there is nothing to write down.
    if (posts.isEmpty && !_cachedFingerprint.containsKey(channelId)) return;
    if (_cachedFingerprint[channelId] == now) return;
    _cachedFingerprint[channelId] = now;
    onPostsChanged?.call(_posts);
  }

  /// Takes posts back from a restored archive.
  ///
  /// Only where nothing has been fetched for that channel in this run: a cache
  /// must never overwrite what the server has just said.
  void restorePosts(Map<String, List<ChannelPost>> cached) {
    var changed = false;
    for (final entry in cached.entries) {
      if (_posts.containsKey(entry.key)) continue;
      _posts[entry.key] = entry.value;
      // Recorded as already written, or the next load would re-seal an archive
      // that already holds exactly this.
      _cachedFingerprint[entry.key] = _fingerprint(entry.value);
      changed = true;
    }
    if (changed) notifyListeners();
  }

  Future<void> _deliverFor(String channelId) async {
    try {
      await _channels.deliverPendingKeys(channelId);
    } on Object {
      // Retried on the next load; a failed delivery is not the reader's problem.
    }
  }

  /// The first page of a channel's members.
  ///
  /// Paged rather than fetched whole: the old call took the first five hundred
  /// and said nothing about the rest, which reads on screen exactly like a
  /// complete list of a channel that happens to have five hundred people in it.
  Future<void> loadMembers(String channelId, {String? query}) async {
    await _run(() async {
      final roster = await _channels.members(channelId, limit: _memberPage, query: query);
      _members[channelId] = roster.members;
      _membersComplete[channelId] = roster.complete;
      _memberCursor[channelId] = roster.nextCursor;
    });
  }

  /// The next page, appended. A no-op once there is nothing after.
  Future<void> loadMoreMembers(String channelId, {String? query}) async {
    final cursor = _memberCursor[channelId];
    if (cursor == null) return;
    await _run(() async {
      final roster = await _channels.members(
        channelId,
        limit: _memberPage,
        cursor: cursor,
        query: query,
      );
      _members[channelId] = [...membersOf(channelId), ...roster.members];
      _memberCursor[channelId] = roster.nextCursor;
    });
  }

  /// Just the people running the channel, which every member may see.
  Future<void> loadAdmins(String channelId) async {
    await _run(() async {
      final roster = await _channels.members(channelId, role: 'admins', limit: 200);
      _admins[channelId] = roster.members;
    });
  }

  List<ChannelMember> adminsOf(String channelId) => _admins[channelId] ?? const [];

  /// Whether another page of members exists.
  bool hasMoreMembers(String channelId) => _memberCursor[channelId] != null;

  /// Puts people in directly where their own settings allow it.
  ///
  /// Returns who could not be added, so the screen offers them a link instead
  /// of reporting a success that did not happen to everybody.
  Future<({List<String> added, List<String> invite})?> addMembers(
    String channelId,
    List<String> accountIds,
  ) async {
    ({List<String> added, List<String> invite})? result;
    final ok = await _run(() async {
      result = await _channels.addMembers(channelId, accountIds);
      await loadMembers(channelId);
    });
    return ok ? result : null;
  }

  // --- Muting ---------------------------------------------------------------

  /// Silences a channel for this account, for a while or for good.
  ///
  /// The channel in the list is updated straight away rather than waiting for a
  /// refresh: muting something is the kind of act whose effect should be
  /// visible in the same breath.
  Future<bool> mute(String channelId, {DateTime? until}) => _run(() async {
        final result = await _channels.mute(channelId, until: until);
        final channel = channelById(channelId);
        if (channel != null) {
          _replace(channel.copyWith(muted: result.muted, mutedUntil: result.until));
        }
      });

  Future<bool> unmute(String channelId) => _run(() async {
        await _channels.unmute(channelId);
        final channel = channelById(channelId);
        if (channel != null) _replace(channel.copyWith(muted: false, clearMutedUntil: true));
      });

  // --- Livestreams ----------------------------------------------------------

  /// What can be done about a livestream, including "nothing, and why".
  Future<ChannelLive?> live(String channelId) async {
    ChannelLive? found;
    final ok = await _run(() async {
      found = await _channels.live(channelId);
    });
    return ok ? found : null;
  }

  Future<ChannelLive?> startLive(String channelId) async {
    ChannelLive? started;
    final ok = await _run(() async {
      started = await _channels.startLive(channelId);
    });
    return ok ? started : null;
  }

  Future<bool> endLive(String channelId) => _run(() => _channels.endLive(channelId));

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

  /// Joins, which is what the button on the preview does.
  ///
  /// [inviteCode] falls back to the code the channel was previewed with: a
  /// private channel needs it again here, and by this point the link that
  /// carried it is long gone.
  Future<bool> join(ChannelInfo channel, {String? inviteCode}) => _run(() async {
        final joined = await _channels.join(
          channel,
          inviteCode: inviteCode ?? _previewCodes[channel.id],
        );
        _mine = [joined, ..._mine.where((c) => c.id != joined.id)];
        _discovered = [
          for (final c in _discovered) if (c.id == joined.id) joined else c,
        ];
      });

  /// Looks up what a link names. **Does not join.**
  ///
  /// It used to join, right here, the moment a link was opened. That is the
  /// wrong shape for a link somebody was sent: opening it is reading an
  /// invitation, not accepting one, and a person who taps a link out of
  /// curiosity should not find themselves a member of a stranger's channel
  /// with their name in its list. What this returns is a channel the screen
  /// shows with a Join button — and for somebody who is already a member, that
  /// screen is simply the channel.
  ///
  /// The invite code is kept with the result: a private channel needs it again
  /// at the moment of joining, and by then the link is gone.
  Future<ChannelInfo?> openInvite(String link) async {
    final target = ChannelService.parseLink(link);
    if (target == null) {
      _error = 'That does not look like a Privio channel link.';
      notifyListeners();
      return null;
    }
    return preview(target);
  }

  /// The invite code a previewed channel was reached by, if it was reached by
  /// one. Needed again when the Join button is pressed.
  final Map<String, String> _previewCodes = {};

  String? codeFor(String channelId) => _previewCodes[channelId];

  /// Fetches what a link names, without joining anything.
  Future<ChannelInfo?> preview(ChannelLinkTarget target) async {
    ChannelInfo? channel;
    await _run(() async {
      switch (target) {
        case ChannelLinkByCode(:final code):
          final found = await _channels.byInvite(code);
          _previewCodes[found.id] = code;
          channel = found;
        case ChannelLinkByHandle(:final handle):
          channel = await _channels.byHandle(handle);
      }
    });
    return channel;
  }

  // --- Pictures -------------------------------------------------------------

  /// Opened channel pictures, keyed by media id.
  ///
  /// By media id rather than by channel: replacing a picture gives it a new id,
  /// so the new one cannot be served out of the old one's slot, and nothing has
  /// to be invalidated by hand.
  ///
  /// In memory only, like contact pictures. A private channel's picture is
  /// ciphertext everywhere but here, and writing the opened bytes to disk would
  /// undo that for the sake of a cache that a relaunch rebuilds in one request.
  final Map<String, Uint8List> _avatars = {};

  /// Media ids already tried and not worth trying again this run.
  ///
  /// Without it a channel whose picture cannot be opened — the bytes are gone,
  /// the key has not arrived — is re-fetched on every rebuild of every list it
  /// appears in.
  final Set<String> _avatarMisses = {};

  /// The channel's picture, if it has been fetched. Null draws a monogram.
  Uint8List? avatarFor(ChannelInfo channel) =>
      channel.avatarMediaId == null ? null : _avatars[channel.avatarMediaId!];

  /// Fetches the pictures of channels that have one and have not been fetched.
  ///
  /// Quiet on failure: a missing picture is a cosmetic problem, and a channel
  /// list that fails to load because one image was unreachable would be a much
  /// worse one.
  Future<void> loadAvatars(Iterable<ChannelInfo> channels) async {
    var loaded = false;
    for (final channel in channels) {
      final id = channel.avatarMediaId;
      if (id == null || !channel.hasAvatar) continue;
      if (_avatars.containsKey(id) || _avatarMisses.contains(id)) continue;
      try {
        final bytes = await _channels.avatarBytes(channel);
        if (bytes == null) {
          _avatarMisses.add(id);
          continue;
        }
        _avatars[id] = bytes;
        loaded = true;
      } on Object {
        _avatarMisses.add(id);
      }
    }
    if (loaded) notifyListeners();
  }

  /// Gives a channel a picture, or replaces the one it has.
  ///
  /// The service decides how it is stored — unsealed for a public channel,
  /// sealed with the channel key for a private one — because that follows from
  /// what the channel is and must not be a choice a screen can get wrong.
  /// The channel as it stands after the change, or null if it did not happen.
  ///
  /// Returned rather than only stored: the feed screen holds its own copy of
  /// the channel and has to be handed the new one, exactly as leaving, joining
  /// and renaming already do. Relying on the screen to find it again through
  /// the lists is what made a successful upload look like nothing at all.
  ChannelInfo? lastAvatarChange;

  Future<bool> setAvatar(ChannelInfo channel, Uint8List picked) => _run(() async {
        final updated = await _channels.setAvatar(channel, picked);
        _replace(updated);
        lastAvatarChange = updated;
        // Put the bytes in the cache from what was just uploaded rather than
        // fetching them back: the round trip can fail on a slow network and
        // leave a channel that has a picture showing none.
        final bytes = await _channels.avatarBytes(updated);
        if (bytes != null) _avatars[updated.avatarMediaId!] = bytes;
      });

  Future<bool> clearAvatar(ChannelInfo channel) => _run(() async {
        final updated = await _channels.clearAvatar(channel);
        _avatars.remove(channel.avatarMediaId);
        _avatarMisses.remove(channel.avatarMediaId);
        _replace(updated);
        lastAvatarChange = updated;
      });

  /// Puts a changed channel back into whichever list it was in.
  ///
  /// **Adds it when it is in neither.** It used to only rewrite entries that
  /// were already there, which quietly dropped the update for a channel reached
  /// before `refresh()` had run or opened straight from a link: the write
  /// succeeded on the server, `channelById` went on answering null, and the
  /// screen kept showing the copy it was built with. A picture set that way
  /// never appeared, with nothing anywhere saying why.
  /// Puts a channel into this controller's lists without a round trip.
  ///
  /// For a screen that already holds one — opened from a link, or handed over
  /// by whatever pushed it — so it is answerable by [channelById] straight
  /// away rather than only after the next refresh. The same door [_replace]
  /// uses, so there is one way a channel gets into these lists.
  void adopt(ChannelInfo channel) {
    _replace(channel);
    notifyListeners();
  }

  void _replace(ChannelInfo channel) {
    final inMine = _mine.any((c) => c.id == channel.id);
    final inDiscovered = _discovered.any((c) => c.id == channel.id);
    if (!inMine && !inDiscovered) {
      _mine = [..._mine, channel];
      return;
    }
    _mine = [for (final c in _mine) if (c.id == channel.id) channel else c];
    _discovered = [for (final c in _discovered) if (c.id == channel.id) channel else c];
  }

  Future<bool> leave(String channelId) => _run(() async {
        await _channels.leave(channelId);
        _mine = [for (final c in _mine) if (c.id != channelId) c];
        _posts.remove(channelId);
        _members.remove(channelId);
        _membersComplete.remove(channelId);
      });

  Future<bool> delete(String channelId) => _run(() async {
        final gone = channelById(channelId)?.avatarMediaId;
        await _channels.delete(channelId);
        if (gone != null) _avatars.remove(gone);
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

  /// Hands the channel to another member.
  ///
  /// Reloads afterwards because everything on the screen changes: the caller is
  /// an admin now, and the controls they had a moment ago are somebody else's.
  Future<bool> transfer({
    required String channelId,
    required String toAccountId,
    required String currentPassword,
  }) =>
      _run(() async {
        await _channels.transfer(
          channelId: channelId,
          toAccountId: toAccountId,
          currentPassword: currentPassword,
        );
        _mine = await _channels.mine();
        _members.remove(channelId);
      });

  Future<bool> report(String channelId, ChannelReportReason reason) =>
      _run(() async => _channels.report(channelId, reason));

  final Map<String, ChannelStats> _stats = {};

  ChannelStats? statsFor(String channelId) => _stats[channelId];

  Future<bool> loadStats(String channelId) => _run(() async {
        _stats[channelId] = await _channels.stats(channelId);
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

  /// Saves the edit screen in one request, then reloads so every screen showing
  /// this channel redraws from what the server actually stored.
  Future<bool> saveSettings(
    ChannelInfo channel, {
    String? title,
    String? description,
    bool? showSenderName,
    bool? welcomeEnabled,
    String? welcomeMessage,
    bool clearAccent = false,
    String? accent,
    bool clearBackground = false,
    String? background,
    bool clearDiscussionGroup = false,
    String? discussionGroupId,
    bool? directMessagesEnabled,
    bool? commentsEnabled,
  }) =>
      _run(() async {
        await _channels.saveSettings(
          channel,
          title: title,
          description: description,
          showSenderName: showSenderName,
          welcomeEnabled: welcomeEnabled,
          welcomeMessage: welcomeMessage,
          clearAccent: clearAccent,
          accent: accent,
          clearBackground: clearBackground,
          background: background,
          clearDiscussionGroup: clearDiscussionGroup,
          discussionGroupId: discussionGroupId,
          directMessagesEnabled: directMessagesEnabled,
          commentsEnabled: commentsEnabled,
        );
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

  /// The share link for a channel.
  ///
  /// A public channel's is its handle and carries no capability at all; a
  /// private one's is its invite code, which is the capability and is safe to
  /// post anywhere because it is unguessable and carries no key.
  String? inviteLink(ChannelInfo channel) => ChannelService.shareLinkFor(channel);

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
    } on ChannelAvatarRejected catch (failure) {
      // Somebody picked a PDF. That is not a connection problem, and saying it
      // is one sends them to check their wifi over a file they can simply
      // choose again.
      _error = failure.message;
      return false;
    } on ChannelKeyPending catch (failure) {
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
