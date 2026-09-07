import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../crypto/padding.dart';
import '../crypto/privio_crypto.dart';
import '../models/channel.dart';
import 'messaging_service.dart';

/// A channel whose current key this device does not have.
///
/// Thrown rather than returned, and never swallowed into a silent fallback:
/// publishing under the previous key is exactly what a rotation exists to
/// prevent, so "I cannot post yet" has to reach the screen as a sentence
/// somebody can act on.
class ChannelKeyPending implements Exception {
  const ChannelKeyPending({
    required this.channelId,
    required this.epoch,
    required this.awaitingGeneration,
  });

  final String channelId;

  /// The version this channel is on now.
  final int epoch;

  /// True when nobody has generated the new key yet — somebody was removed and
  /// no device that could make the replacement has been online since. False
  /// when it exists and simply has not reached this device.
  final bool awaitingGeneration;

  /// What to put in front of the person trying to post.
  String get message => awaitingGeneration
      ? 'This channel is changing its key after a member left. You can post '
          'again once someone who manages the channel opens Privio.'
      : 'Waiting for the new channel key to reach this device. Your post is '
          'not lost — try again in a moment.';

  @override
  String toString() => message;
}

/// Channels, sealed end to end.
///
/// A channel has one symmetric key. Posts are encrypted with it before they
/// leave the device, so the server stores a feed it cannot read — for a public
/// channel just as much as a private one. What differs between the two is
/// discovery, not confidentiality: a public channel's title and description are
/// plaintext because search cannot run over ciphertext, and a private channel
/// sends even those sealed.
///
/// An invite link is meant to be shared — posted on a website, sent through
/// another messenger — so it carries no key, only the code that names the
/// channel. The key follows separately: the joining device records a request,
/// and any member who already holds the key seals it to them over the Signal
/// session between the two accounts. The server routes both halves and can read
/// neither.
class ChannelService {
  ChannelService({
    required PrivioApiClient api,
    required PrivioCrypto crypto,
    required MessagingService messaging,
  })  : _api = api,
        _crypto = crypto,
        _messaging = messaging;

  final PrivioApiClient _api;
  final PrivioCrypto _crypto;
  final MessagingService _messaging;

  static final AesGcm _cipher = AesGcm.with256bits();
  static const int _nonceLength = 12;

  /// The id of the channel whose key just arrived, so a feed sitting on a
  /// screenful of padlocks can unlock itself instead of waiting to be reopened.
  final ValueNotifier<String?> keyArrived = ValueNotifier<String?>(null);

  final Random _random = Random.secure();

  /// The current epoch of each channel, as the server last reported it.
  final Map<String, int> _epochs = {};

  // --- Keys -----------------------------------------------------------------

  /// The key for one version of a channel.
  Future<Uint8List?> keyFor(String channelId, int epoch) =>
      _crypto.store.readChannelKey(channelId, epoch);

  /// Remembers a key for one version — from creating the channel, from
  /// generating a replacement, or from a delivery.
  ///
  /// Old versions are kept. A member who was here before a removal holds
  /// several, and each one opens the posts that were sealed with it: dropping
  /// them would take history away from exactly the people the rotation exists
  /// to protect.
  Future<void> rememberKey(String channelId, int epoch, Uint8List key) async {
    final existing = await _crypto.store.readChannelKey(channelId, epoch);
    if (existing != null) {
      // A key for an epoch this device already holds is a redelivery or a
      // replay. Overwriting would be the one way a stale event could take a
      // channel backwards, so it does not happen.
      return;
    }
    await _crypto.store.writeChannelKey(channelId, epoch, key);
    keyArrived.value = channelId;
  }

  Future<void> forgetKey(String channelId) => _crypto.store.deleteChannelKey(channelId);

  /// Which versions this device can open.
  Future<List<int>> heldEpochs(String channelId) =>
      _crypto.store.channelKeyEpochs(channelId);

  /// Which versions a new member is given, and therefore what history they get.
  ///
  /// Decided in one place and deliberately, because it is the question a
  /// rotation raises and the one it is easiest to answer by accident:
  ///
  /// **A private channel: the current version only.** Somebody joining today
  /// was not in the room yesterday. Handing over every earlier key would mean a
  /// person removed on Monday could rejoin under a new account on Tuesday and
  /// have the lot back — which would make the rotation decorative. Older posts
  /// stay padlocked for them, and the feed says so rather than hiding them.
  ///
  /// **A public channel: every version this device holds.** Anyone may join a
  /// public channel, so anyone may hold its keys; that is what "public" means
  /// and the security model already says so. Withholding history there would
  /// not keep a determined reader out for five minutes — they can join under
  /// any account, or ask somebody — while making the channel worse for everyone
  /// who joins honestly. On a public channel a rotation is about the membership
  /// list, who is sent the feed and who may post. It is not, and must not be
  /// presented as, a way of putting past posts beyond somebody's reach.
  Future<List<int>> epochsToShareWith(String channelId) async {
    final state = await currentEpoch(channelId);
    final channel = await byId(channelId);
    if (!channel.isPublic) return [state.epoch];
    final held = await heldEpochs(channelId);
    return held.isEmpty ? [state.epoch] : held;
  }

  /// Puts a key where a version of this app from before epochs would have left
  /// it, so the migration path can be driven in a test.
  @visibleForTesting
  Future<void> writeLegacyKey(String channelId, Uint8List key) =>
      _crypto.store.writeLegacyChannelKey(channelId, key);

  /// The unconfirmed candidate, so a test can check it was written before the
  /// network call rather than after it.
  @visibleForTesting
  Future<({int epoch, String keyId, Uint8List key})?> pendingKeyForTest(String channelId) =>
      _crypto.store.readPendingChannelKey(channelId);

  /// The same storage, so a test can build a second service over it — which is
  /// what a restart looks like from in here.
  @visibleForTesting
  PrivioCrypto get cryptoForTest => _crypto;

  // --- Key versions ---------------------------------------------------------

  /// What the server says this channel's current key version is.
  Future<({int epoch, String? keyId})> currentEpoch(String channelId) async {
    final response = await _api.channelKeyEpoch(channelId);
    final epoch = (response['epoch'] as num?)?.toInt() ?? 1;
    _epochs[channelId] = epoch;
    return (epoch: epoch, keyId: response['keyId'] as String?);
  }

  /// Whether this device can publish to, and fully read, this channel right now.
  Future<bool> hasCurrentKey(String channelId) async {
    final state = await currentEpoch(channelId);
    return await keyFor(channelId, state.epoch) != null;
  }

  /// Completes a rotation: generates the next key, claims it, and hands it out.
  ///
  /// Called after a removal, and whenever a device notices the channel is on an
  /// epoch it has no key for. Only somebody who may manage members gets here —
  /// a subscriber generating keys would be a subscriber deciding who reads the
  /// channel next, which is the very permission being rotated.
  ///
  /// Two things this has to survive, and the order of operations is what makes
  /// it survive them.
  ///
  /// **The race.** Two admins removing two people in the same minute both see
  /// the epoch go up and both generate a key. If both were distributed, half
  /// the members would hold one and half the other, with posts nobody could
  /// read and no error anywhere. So the epoch is claimed first, the database
  /// settles who won, and the loser throws its key away and asks for the
  /// winner's rather than distributing a second one.
  ///
  /// **The crash.** The candidate key is written down *before* the claim goes
  /// out, not after. A device that claimed successfully and then died — or
  /// whose reply was lost on the way back — comes back holding the same
  /// candidate and the same label, sends the identical claim, is told it
  /// already won, and carries on from there. Without that ordering the epoch
  /// would be reserved to a key that exists nowhere, which is a channel nobody
  /// can publish to and nobody can repair.
  ///
  /// A candidate is never distributed until the server has confirmed it won.
  ///
  /// Returns true when this device now holds the current key — whether it made
  /// it, resumed it, or already had it.
  Future<bool> completeRotation(String channelId) async {
    final state = await currentEpoch(channelId);

    // Already have it: either nothing rotated, or somebody's delivery arrived
    // first. Nothing to claim, and nothing to overwrite — but not necessarily
    // nothing to do.
    //
    // This used to return here, and that was a way for a rotation to end up
    // permanently half-finished. The claim is one step; re-sealing the
    // channel's name under the new key and answering whoever is waiting for
    // that key are the others, and they run after the promotion — so a device
    // that lost its connection in between came back, saw it already held the
    // current key, and returned without ever finishing them. The name then
    // stayed sealed under a key that members who joined later are deliberately
    // never given, for the life of the channel.
    if (await keyFor(channelId, state.epoch) != null) {
      await _crypto.store.clearPendingChannelKey(channelId);
      await _finishRotation(channelId, state.epoch);
      return true;
    }

    final pending = await _crypto.store.readPendingChannelKey(channelId);

    // A candidate left over from an epoch the channel has since moved past.
    // It can never be promoted — that epoch is settled or abandoned — so it is
    // dropped rather than carried around as key material nobody will use.
    if (pending != null && pending.epoch != state.epoch) {
      await _crypto.store.clearPendingChannelKey(channelId);
      return _resumeFrom(channelId, state, null);
    }

    return _resumeFrom(channelId, state, pending);
  }

  Future<bool> _resumeFrom(
    String channelId,
    ({int epoch, String? keyId}) state,
    ({int epoch, String keyId, Uint8List key})? pending,
  ) async {
    // Somebody else's key already holds this epoch, and it is not the candidate
    // in hand. There is nothing to claim; what is needed is the key itself,
    // which only a member can send.
    if (state.keyId != null && state.keyId != pending?.keyId) {
      await _crypto.store.clearPendingChannelKey(channelId);
      await requestKey(channelId);
      return false;
    }

    // Either resuming an attempt whose outcome was never learned, or starting
    // one. Both send the same shape of request; the difference is only whether
    // the candidate was generated a moment ago or before a crash.
    final candidate = pending?.key ??
        Uint8List.fromList(await (await _cipher.newSecretKey()).extractBytes());
    final keyId = pending?.keyId ?? _newKeyId();

    if (pending == null) {
      // Before the network call. Always.
      await _crypto.store.writePendingChannelKey(
        channelId,
        epoch: state.epoch,
        keyId: keyId,
        key: candidate,
      );
    }

    final Map<String, dynamic> claim;
    try {
      claim = await _api.claimChannelKeyEpoch(
        channelId: channelId,
        epoch: state.epoch,
        keyId: keyId,
      );
    } on Object {
      // Refused, or the reply never came back. The candidate stays on disk so
      // the next attempt sends the same one and finds out what became of it.
      // Nothing is distributed and nothing is written as the channel's key.
      return false;
    }

    if (claim['claimed'] != true) {
      // Lost. The candidate is deleted without ever having been the channel's
      // key: a key that is not the agreed one is worse than no key, because it
      // looks like progress.
      await _crypto.store.clearPendingChannelKey(channelId);
      await requestKey(channelId);
      return false;
    }

    // Confirmed ours, and only now does it become the channel's key. Promoting
    // before this point is what would let an unconfirmed candidate be handed
    // to other members.
    await rememberKey(channelId, state.epoch, candidate);
    await _crypto.store.clearPendingChannelKey(channelId);

    // Everything after this is repeatable and safe to interrupt: a restart in
    // the middle of distribution leaves the key stored, and the next pass sends
    // it to whoever has not had it. Members who already have it ignore a
    // second copy — see rememberKey.
    await _finishRotation(channelId, state.epoch);
    await distributeKey(channelId, state.epoch);
    return true;
  }

  /// The part of a rotation that comes after the key is the channel's key.
  ///
  /// Kept separate because it has to run on both paths — the device that just
  /// claimed the epoch, and the device that comes back later already holding
  /// it. Both are idempotent: the re-seal is skipped when the name is already
  /// under the current key, and answering key requests is driven by what is
  /// still outstanding on the server.
  ///
  /// Nothing here is allowed to fail the rotation. The key is promoted and the
  /// channel is usable; what is left is repair work, and it is retried on the
  /// next pass rather than turned into an error on this one.
  Future<void> _finishRotation(String channelId, int epoch) async {
    await _resealMetadata(channelId, epoch);
    try {
      await deliverPendingKeys(channelId);
    } on Object {
      // Whoever is waiting stays waiting, and asks again.
    }
  }

  /// Moves past an epoch whose key nobody has.
  ///
  /// The device that generated it is gone — wiped, uninstalled, lost — and
  /// took the only copy with it. The channel cannot be published to, the epoch
  /// cannot be claimed again with a different key without splitting the channel
  /// in two, and falling back to the previous key would hand the future back to
  /// whoever was removed.
  ///
  /// So the stuck version is abandoned and the channel moves forward to a fresh
  /// one, which this device then claims by the ordinary path. The server
  /// refuses to abandon a version that has posts under it, so nothing readable
  /// can be stranded by this.
  ///
  /// Deliberately not automatic. "Nobody has sent me the key" and "nobody can
  /// send me the key" look identical from here, and the difference is usually
  /// that an admin has not opened the app since Tuesday. Spending an epoch on
  /// that guess would make every slow delivery into a rotation.
  Future<bool> abandonOrphanedEpoch(String channelId) async {
    final state = await currentEpoch(channelId);
    if (await keyFor(channelId, state.epoch) != null) return false;
    try {
      await _api.abandonChannelKeyEpoch(channelId: channelId, epoch: state.epoch);
    } on Object {
      return false;
    }
    await _crypto.store.clearPendingChannelKey(channelId);
    return completeRotation(channelId);
  }

  /// Re-seals a private channel's name under the current key.
  ///
  /// Without this the name stays sealed under epoch 1 for the life of the
  /// channel, and a member who joined after a rotation — given only the current
  /// key, deliberately — can read every new post and not the channel's own
  /// name. Public channels have a plaintext title and need none of this.
  ///
  /// Best effort *per attempt*: a failure here costs a name on somebody's
  /// screen and must not undo a rotation that has otherwise completed. It is
  /// not best effort overall — it is attempted again on every later pass until
  /// the name is under the current key, because there is no other repair for
  /// it and nothing else notices.
  ///
  /// The server says which version sealed the name, so a device that is
  /// already current does nothing: the check is one read the caller was making
  /// anyway, and it keeps this from becoming a write on every poll.
  Future<void> _resealMetadata(String channelId, int epoch) async {
    try {
      final raw = await _api.channel(channelId);
      if (raw['visibility'] == 'public') return;
      final sealedUnder = (raw['metadataKeyEpoch'] as num?)?.toInt() ?? 1;
      if (sealedUnder >= epoch) return;
      final channel = await _open(raw);
      if (channel.title.isEmpty || channel.title == 'Private channel') return;
      final key = await keyFor(channelId, epoch);
      if (key == null) return;
      await _api.updateChannel(
        channelId,
        encryptedMetadata: base64Encode(await _seal(channel.title, key)),
        metadataKeyEpoch: epoch,
      );
    } on Object {
      // Left for the next pass, which now happens.
    }
  }

  /// Seals the current key to every remaining member.
  ///
  /// One message per account, over the Signal session the two already have. The
  /// server routes it and cannot read it, which is what keeps a rotation from
  /// being a moment where the key passes through the relay.
  Future<int> distributeKey(String channelId, int epoch) async {
    final key = await keyFor(channelId, epoch);
    if (key == null) return 0;

    final roster = await members(channelId);
    var sent = 0;
    for (final member in roster.members) {
      if (member.username.isEmpty) continue;
      try {
        await _messaging.deliverKey(
          username: member.username,
          scope: 'channel',
          scopeId: channelId,
          base64Key: base64Encode(key),
          keyEpoch: epoch,
        );
        sent++;
      } on Object {
        // One unreachable member does not hold up the rest. They will ask, and
        // the request path answers them.
        continue;
      }
    }
    return sent;
  }

  /// A random label for a key, so devices can agree which key an epoch means.
  ///
  /// Random rather than a hash of the key: a label derived from key material is
  /// a question about how much it leaks, and there is no reason to have to
  /// answer it. This one is 128 bits of nothing.
  String _newKeyId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  // --- Channels -------------------------------------------------------------

  /// Creates a channel and keeps its fresh key on this device.
  ///
  /// A private channel uploads its title sealed, so the server holds a channel
  /// it cannot name. A public one has to upload the title in the clear to be
  /// discoverable — that is the trade the visibility choice makes, and it stops
  /// at the title: the posts are sealed either way.
  Future<ChannelInfo> create({
    required ChannelVisibility visibility,
    required String title,
    String? handle,
    String? description,
    String? category,
    bool restrictSaving = false,
  }) async {
    final key = Uint8List.fromList(
      await (await _cipher.newSecretKey()).extractBytes(),
    );
    final keyId = _newKeyId();
    final isPublic = visibility == ChannelVisibility.public;

    final created = await _api.createChannel(
      visibility: isPublic ? 'public' : 'private',
      handle: isPublic ? handle : null,
      title: isPublic ? title : null,
      description: isPublic ? description : null,
      category: isPublic ? category : null,
      encryptedMetadata: isPublic ? null : base64Encode(await _seal(title, key)),
      restrictSaving: restrictSaving,
      keyId: keyId,
    );

    final id = created['id'] as String;
    // Epoch 1, claimed at birth by the same rule every later epoch follows, so
    // there is no special case for "the first key" anywhere.
    await rememberKey(id, 1, key);
    return _toInfo(created, title: title, hasKey: true, hasCurrentKey: true);
  }

  /// The channels this account is in, with private titles opened where the key
  /// is on this device.
  Future<List<ChannelInfo>> mine() async {
    final response = await _api.myChannels();
    final channels = <ChannelInfo>[];
    for (final raw in response['channels'] as List<dynamic>? ?? const []) {
      channels.add(await _open(raw as Map<String, dynamic>));
    }
    return channels;
  }

  Future<List<ChannelInfo>> discover({String? query, String? category}) async {
    final response = await _api.discoverChannels(query: query, category: category);
    final channels = <ChannelInfo>[];
    for (final raw in response['channels'] as List<dynamic>? ?? const []) {
      channels.add(await _open(raw as Map<String, dynamic>));
    }
    return channels;
  }

  Future<ChannelInfo> byInvite(String code) async =>
      _open(await _api.channelByInvite(code));

  Future<ChannelInfo> byId(String channelId) async =>
      _open(await _api.channel(channelId));

  /// Joins.
  ///
  /// The server queues a key request for this device as part of the join, so
  /// there is nothing more to do here: the key arrives as a message once a
  /// member who holds it next opens the app.
  Future<ChannelInfo> join(ChannelInfo channel, {String? inviteCode}) async {
    final result = await _api.joinChannel(channel.id, inviteCode: inviteCode);
    final added = result['joined'] as bool? ?? false;
    return channel.copyWith(
      role: result['role'] as String? ?? 'subscriber',
      permissions: ChannelPermissions.fromJson(
        result['permissions'] as Map<String, dynamic>?,
      ),
      hasKey: (await heldEpochs(channel.id)).isNotEmpty,
      // The list this came from was fetched before the join, so it is one short.
      memberCount: added ? channel.memberCount + 1 : channel.memberCount,
    );
  }

  /// Asks again for a key that never arrived.
  Future<void> requestKey(String channelId) => _api.requestChannelKey(channelId);

  /// Answers everyone waiting for this channel's key.
  ///
  /// Runs on any member that holds the key, not only admins: making delivery
  /// wait for an admin to open the app would leave new members looking at
  /// padlocks for days. Returns how many accounts were served.
  Future<int> deliverPendingKeys(String channelId) async {
    final state = await currentEpoch(channelId);
    final key = await keyFor(channelId, state.epoch);
    if (key == null) return 0;

    final epochsToSend = await epochsToShareWith(channelId);

    final response = await _api.channelKeyRequests(channelId);
    final requests = [
      for (final raw in response['requests'] as List<dynamic>? ?? const [])
        raw as Map<String, dynamic>,
    ];
    if (requests.isEmpty) return 0;

    // One delivery per account: sending covers every device that account has,
    // so a second request from the same person needs no second message.
    final byUsername = <String, List<String>>{};
    for (final request in requests) {
      byUsername
          .putIfAbsent(request['username'] as String, () => [])
          .add(request['deviceId'] as String);
    }

    var served = 0;
    for (final entry in byUsername.entries) {
      try {
        for (final epoch in epochsToSend) {
          final forEpoch = epoch == state.epoch ? key : await keyFor(channelId, epoch);
          if (forEpoch == null) continue;
          await _messaging.deliverKey(
            username: entry.key,
            scope: 'channel',
            scopeId: channelId,
            base64Key: base64Encode(forEpoch),
            keyEpoch: epoch,
          );
        }
        for (final deviceId in entry.value) {
          await _api.clearChannelKeyRequest(channelId, deviceId);
        }
        served++;
      } on Object {
        // One unreachable member must not hold up the rest; the request stays
        // queued and is retried on the next pass.
        continue;
      }
    }
    return served;
  }

  /// Leaves and drops the key: staying able to read a channel you have left is
  /// not a feature.
  Future<void> leave(String channelId) async {
    await _api.leaveChannel(channelId);
    await forgetKey(channelId);
  }

  Future<void> delete(String channelId) async {
    await _api.deleteChannel(channelId);
    await forgetKey(channelId);
  }

  /// Who is in a channel — and whether that is all of them.
  ///
  /// A subscriber is answered with the people who run the channel and their own
  /// row, not the audience; only a member who may manage members gets the whole
  /// list. `complete` is the server saying which of the two this is, so the
  /// screen can say so too rather than passing a staff list off as everybody.
  Future<({List<ChannelMember> members, bool complete})> members(String channelId) async {
    final response = await _api.channelMembers(channelId);
    return (
      members: [
        for (final raw in response['members'] as List<dynamic>? ?? const [])
          ChannelMember.fromJson(raw as Map<String, dynamic>),
      ],
      complete: response['complete'] as bool? ?? false,
    );
  }

  /// Appoints or demotes. The server rejects granting anything the caller does
  /// not hold, so a failure here is the rule working, not a bug to route around.
  Future<ChannelMember> setRole({
    required String channelId,
    required ChannelMember member,
    required String role,
    ChannelPermissions? permissions,
  }) async {
    final result = await _api.setChannelRole(
      channelId: channelId,
      accountId: member.id,
      role: role,
      permissions: permissions?.toJson(),
    );
    return member.copyWith(
      role: result['role'] as String? ?? role,
      permissions: ChannelPermissions.fromJson(
        result['permissions'] as Map<String, dynamic>?,
      ),
    );
  }

  Future<void> removeMember(String channelId, String accountId) =>
      _api.removeChannelMember(channelId, accountId);

  /// Where join links point. Two constants, because each host appears in the
  /// links it generates, in the hint text of a dialog and in the tests — and a
  /// link that used to work must keep working.
  static const String channelLinkHost = 'privio.channel';
  static const String groupLinkHost = 'privio.group';

  /// The link to share. It holds the code and nothing else, so it is safe to
  /// post anywhere a link can be posted.
  static String linkForChannel(String inviteCode) =>
      'https://$channelLinkHost/c/$inviteCode';

  static String linkForGroup(String inviteCode) => 'https://$groupLinkHost/g/$inviteCode';

  /// Reads back a Privio join link — a channel's or a group's.
  ///
  /// What decides the kind is the `/c/` or `/g/` in the path, not the host: a
  /// link that has been shortened, wrapped by a mail scanner or re-hosted still
  /// names the same channel. Returns null on anything malformed — a link is
  /// user input, not a promise.
  static ChannelInvite? parseInviteLink(String link) {
    final uri = Uri.tryParse(link.trim());
    if (uri == null) return null;
    final segments = uri.pathSegments;

    const kinds = {'c': InviteKind.channel, 'g': InviteKind.group};
    for (final entry in kinds.entries) {
      final index = segments.indexOf(entry.key);
      if (index < 0 || index + 1 >= segments.length) continue;
      final code = segments[index + 1];
      if (code.isEmpty) continue;
      return ChannelInvite(code: code, kind: entry.value);
    }
    return null;
  }

  // --- Posts ----------------------------------------------------------------

  /// Publishes a post, sealed and padded.
  ///
  /// Padding matters more here than in a chat: a channel's post lengths are
  /// visible to the server for every subscriber at once, and a run of exact
  /// lengths is a fingerprint of the text.
  Future<int> publish(String channelId, String body) async {
    // The epoch is read now rather than remembered from the last time this
    // screen was opened. A post composed before somebody was removed and sent
    // afterwards is the exact case this milestone exists for: sealing it with
    // the key that is in hand would publish it to the person who was just
    // thrown out.
    final state = await currentEpoch(channelId);
    final key = await keyFor(channelId, state.epoch);
    if (key == null) {
      throw ChannelKeyPending(
        channelId: channelId,
        epoch: state.epoch,
        // Nobody has generated it yet, or it has not reached this device. The
        // difference matters to what the screen says.
        awaitingGeneration: state.keyId == null,
      );
    }

    try {
      final result = await _api.publishPost(
        channelId: channelId,
        content: base64Encode(await _seal(body, key)),
        keyEpoch: state.epoch,
      );
      return result['id'] as int;
    } on ApiException catch (failure) {
      // The epoch moved between reading it and publishing — somebody was
      // removed in those few hundred milliseconds. The server refused rather
      // than storing a post under a superseded key, which is the check working.
      // One retry, sealed again under whatever is current now.
      if (failure.code != 'stale_key_epoch') rethrow;
      final now = await currentEpoch(channelId);
      final fresh = await keyFor(channelId, now.epoch);
      if (fresh == null) {
        throw ChannelKeyPending(
          channelId: channelId,
          epoch: now.epoch,
          awaitingGeneration: now.keyId == null,
        );
      }
      final result = await _api.publishPost(
        channelId: channelId,
        content: base64Encode(await _seal(body, fresh)),
        keyEpoch: now.epoch,
      );
      return result['id'] as int;
    }
  }

  /// The feed, newest first. Posts that will not open come back as locked
  /// placeholders rather than being dropped, so a missing key looks like a
  /// missing key instead of an empty channel.
  Future<List<ChannelPost>> posts(String channelId, {int? before, int limit = 50}) async {
    final response = await _api.channelPosts(channelId, before: before, limit: limit);
    final posts = <ChannelPost>[];
    // One read per epoch rather than one per post: a feed of fifty posts spans
    // two or three key versions, not fifty.
    final keys = <int, Uint8List?>{};

    for (final raw in response['posts'] as List<dynamic>? ?? const []) {
      final entry = raw as Map<String, dynamic>;
      final epoch = (entry['keyEpoch'] as num?)?.toInt() ?? 1;
      final key = keys.putIfAbsent(epoch, () => null) ?? await keyFor(channelId, epoch);
      keys[epoch] = key;
      final body = key == null ? null : await _openSealed(entry['content'] as String, key);
      posts.add(
        ChannelPost(
          id: entry['id'] as int,
          body: body ?? '',
          opened: body != null,
          keyEpoch: epoch,
          createdAt:
              DateTime.tryParse(entry['createdAt'] as String? ?? '')?.toLocal() ??
                  DateTime.now(),
          authorUsername: entry['authorUsername'] as String?,
          pinned: entry['pinned'] as bool? ?? false,
        ),
      );
    }
    return posts;
  }

  Future<void> pin(String channelId, int postId, {required bool pinned}) =>
      _api.pinPost(channelId, postId, pinned: pinned);

  Future<void> deletePost(String channelId, int postId) =>
      _api.deletePost(channelId, postId);

  // --- Sealing --------------------------------------------------------------

  Future<Uint8List> _seal(String text, Uint8List key) async {
    final box = await _cipher.encrypt(
      MessagePadding.pad(utf8.encode(text)),
      secretKey: SecretKey(key),
    );
    return Uint8List.fromList([...box.nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  Future<String?> _openSealed(String base64Sealed, Uint8List key) async {
    try {
      final bytes = base64Decode(base64Sealed);
      final macLength = _cipher.macAlgorithm.macLength;
      if (bytes.length <= _nonceLength + macLength) return null;
      final plain = await _cipher.decrypt(
        SecretBox(
          bytes.sublist(_nonceLength, bytes.length - macLength),
          nonce: bytes.sublist(0, _nonceLength),
          mac: Mac(bytes.sublist(bytes.length - macLength)),
        ),
        secretKey: SecretKey(key),
      );
      return utf8.decode(MessagePadding.unpad(plain));
    } on Object {
      // A wrong key, a rotated key, or a corrupt post. None of them should take
      // the feed down with them.
      return null;
    }
  }

  Future<ChannelInfo> _open(Map<String, dynamic> raw) async {
    final id = raw['id'] as String;
    final epoch = (raw['keyEpoch'] as num?)?.toInt() ?? 1;
    final held = await heldEpochs(id);
    final sealed = raw['encryptedMetadata'] as String?;
    final plaintextTitle = raw['title'] as String?;

    var title = plaintextTitle;
    if (title == null && sealed != null) {
      // The server says which key sealed the name. It is re-sealed on every
      // rotation, so this is normally the current epoch — which is the whole
      // point: a member who joined after a rotation holds exactly that one key
      // and can read the channel's name with it, without being handed any of
      // the old message keys.
      //
      // The named epoch is tried first and the rest afterwards, so a device
      // that is mid-rotation — holding the old key while the re-seal is still
      // in flight — still shows a name instead of a placeholder.
      final metadataEpoch = (raw['metadataKeyEpoch'] as num?)?.toInt() ?? 1;
      for (final candidate in [metadataEpoch, ...held.reversed]) {
        final key = await keyFor(id, candidate);
        if (key == null) continue;
        title = await _openSealed(sealed, key);
        if (title != null) break;
      }
    }
    return _toInfo(
      raw,
      title: title ?? 'Private channel',
      hasKey: held.isNotEmpty,
      keyEpoch: epoch,
      // The state the screen has to be able to show: in the channel, holding
      // old keys, and unable to read what is being posted now.
      hasCurrentKey: held.contains(epoch),
    );
  }

  ChannelInfo _toInfo(
    Map<String, dynamic> raw, {
    required String title,
    required bool hasKey,
    int keyEpoch = 1,
    bool? hasCurrentKey,
  }) =>
      ChannelInfo(
        id: raw['id'] as String,
        visibility: raw['visibility'] == 'public'
            ? ChannelVisibility.public
            : ChannelVisibility.private,
        title: title,
        handle: raw['handle'] as String?,
        description: raw['description'] as String?,
        category: raw['category'] as String?,
        memberCount: raw['memberCount'] as int? ?? 0,
        role: raw['role'] as String?,
        permissions: ChannelPermissions.fromJson(
          raw['permissions'] as Map<String, dynamic>?,
        ),
        inviteCode: raw['inviteCode'] as String?,
        restrictSaving: raw['restrictSaving'] as bool? ?? false,
        hasKey: hasKey,
        keyEpoch: keyEpoch,
        hasCurrentKey: hasCurrentKey ?? hasKey,
      );
}
