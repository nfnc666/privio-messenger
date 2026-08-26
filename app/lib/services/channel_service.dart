import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../crypto/padding.dart';
import '../crypto/privio_crypto.dart';
import '../models/channel.dart';
import 'messaging_service.dart';

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

  // --- Keys -----------------------------------------------------------------

  Future<Uint8List?> keyFor(String channelId) => _crypto.store.readChannelKey(channelId);

  /// Remembers the key for a channel — from creating it, or from a delivery.
  Future<void> rememberKey(String channelId, Uint8List key) async {
    await _crypto.store.writeChannelKey(channelId, key);
    keyArrived.value = channelId;
  }

  Future<void> forgetKey(String channelId) => _crypto.store.deleteChannelKey(channelId);

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
    final isPublic = visibility == ChannelVisibility.public;

    final created = await _api.createChannel(
      visibility: isPublic ? 'public' : 'private',
      handle: isPublic ? handle : null,
      title: isPublic ? title : null,
      description: isPublic ? description : null,
      category: isPublic ? category : null,
      encryptedMetadata: isPublic ? null : base64Encode(await _seal(title, key)),
      restrictSaving: restrictSaving,
    );

    final id = created['id'] as String;
    await rememberKey(id, key);
    return _toInfo(created, title: title, hasKey: true);
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
      hasKey: await keyFor(channel.id) != null,
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
    final key = await keyFor(channelId);
    if (key == null) return 0;

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
        await _messaging.deliverKey(
          username: entry.key,
          scope: 'channel',
          scopeId: channelId,
          base64Key: base64Encode(key),
        );
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

  Future<List<ChannelMember>> members(String channelId) async {
    final response = await _api.channelMembers(channelId);
    return [
      for (final raw in response['members'] as List<dynamic>? ?? const [])
        ChannelMember.fromJson(raw as Map<String, dynamic>),
    ];
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

  /// Where join links point. One constant, because the host appears in the
  /// links, in the hint text of two dialogs and in the tests — and a link that
  /// used to work must keep working.
  static const String linkHost = 'privio.channel';

  /// The link to share. It holds the code and nothing else, so it is safe to
  /// post anywhere a link can be posted.
  static String linkForChannel(String inviteCode) => 'https://$linkHost/c/$inviteCode';

  static String linkForGroup(String inviteCode) => 'https://$linkHost/g/$inviteCode';

  /// Reads back a Privio join link — a channel's or a group's. Returns null on
  /// anything malformed: a link is user input, not a promise.
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
    final key = await keyFor(channelId);
    if (key == null) {
      throw StateError('No key for this channel — a post would be unreadable');
    }
    final result = await _api.publishPost(
      channelId: channelId,
      content: base64Encode(await _seal(body, key)),
    );
    return result['id'] as int;
  }

  /// The feed, newest first. Posts that will not open come back as locked
  /// placeholders rather than being dropped, so a missing key looks like a
  /// missing key instead of an empty channel.
  Future<List<ChannelPost>> posts(String channelId, {int? before, int limit = 50}) async {
    final key = await keyFor(channelId);
    final response = await _api.channelPosts(channelId, before: before, limit: limit);
    final posts = <ChannelPost>[];

    for (final raw in response['posts'] as List<dynamic>? ?? const []) {
      final entry = raw as Map<String, dynamic>;
      final body = key == null ? null : await _openSealed(entry['content'] as String, key);
      posts.add(
        ChannelPost(
          id: entry['id'] as int,
          body: body ?? '',
          opened: body != null,
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
    final key = await keyFor(id);
    final sealed = raw['encryptedMetadata'] as String?;
    final plaintextTitle = raw['title'] as String?;

    var title = plaintextTitle;
    if (title == null && sealed != null && key != null) {
      title = await _openSealed(sealed, key);
    }
    return _toInfo(raw, title: title ?? 'Private channel', hasKey: key != null);
  }

  ChannelInfo _toInfo(
    Map<String, dynamic> raw, {
    required String title,
    required bool hasKey,
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
      );
}
