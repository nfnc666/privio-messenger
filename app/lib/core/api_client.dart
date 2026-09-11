import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// A failed API call, carrying the server's stable error code.
class ApiException implements Exception {
  ApiException(this.statusCode, this.code, this.message, {this.missingDevices = const []});

  final int statusCode;
  final String code;
  final String message;

  /// Present on `device_mismatch`: the recipient devices the client did not
  /// seal a copy for. Re-fetch their prekey bundles and send again.
  final List<String> missingDevices;

  @override
  String toString() => 'ApiException($statusCode, $code): $message';
}

/// A reply that belongs to a session which has since ended.
///
/// Thrown rather than returned, and thrown from the transport rather than
/// checked at each call site, because the number of call sites only ever grows
/// and one that forgets is a cross-account data leak.
///
/// The situation is ordinary: a request goes out, the network is slow, and by
/// the time the answer arrives the person has signed out and somebody else has
/// signed in on the same phone. Applying that answer would write one account's
/// contacts, messages or profile into another account's screen. Callers are
/// expected to swallow this silently — there is nobody left to tell, because
/// the person who asked the question is gone.
class StaleSessionException implements Exception {
  const StaleSessionException();

  @override
  String toString() => 'The session that made this request has ended';
}

/// Starts work whose answer belongs to this session and may outlive it.
///
/// A sign-out makes every request still in flight stale, and the transport
/// refuses those answers by throwing [StaleSessionException]. There is nobody
/// left to tell — the person who asked the question has gone — so the throw is
/// dropped here rather than surfacing as an unhandled async error on every
/// account switch. Anything else still escapes: a real failure in detached
/// work should be as loud as it ever was.
void detached(Future<void> work) => unawaited(
      work.catchError(
        (Object _) {},
        test: (error) => error is StaleSessionException,
      ),
    );

/// Thin transport over the Privio API.
///
/// Everything this class sends is already sealed by the crypto layer: message
/// bodies, group names, attachments and backups are opaque bytes by the time
/// they get here. Keep it that way — no plaintext content may be passed to any
/// method that is not explicitly a public profile field.
class PrivioApiClient {
  PrivioApiClient({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  /// Where the API lives. The realtime socket is derived from it.
  final Uri baseUrl;
  final http.Client _client;

  String? _token;

  /// Which session the client is on.
  ///
  /// Bumped by every [useToken], so a reply can be matched against the session
  /// that asked for it. An id rather than comparing the token itself: signing
  /// back into the same account issues a *new* token but so does a rotation,
  /// and what matters is only whether the session changed between the question
  /// and the answer.
  int _session = 0;

  bool get isAuthenticated => _token != null;

  void useToken(String? token) {
    _token = token;
    _session += 1;
  }

  /// Refuses a reply whose session has ended.
  ///
  /// Called after every await on a response, so a slow request that lands
  /// after a sign-out cannot be applied to whoever signed in next.
  void _requireSameSession(int issuedOn) {
    if (_session != issuedOn) throw const StaleSessionException();
  }

  /// Auth only. A content-type is added by the caller when there is a body:
  /// declaring JSON on a bodiless GET or DELETE makes the server reject it.
  Map<String, String> get _headers => {
        if (_token != null) 'authorization': 'Bearer $_token',
      };

  Uri _url(String path, [Map<String, String>? query]) =>
      baseUrl.replace(path: path, queryParameters: query);

  Future<Map<String, dynamic>> _decode(http.Response response) async {
    final body = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw ApiException(
        response.statusCode,
        body['error'] as String? ?? 'unknown_error',
        body['message'] as String? ?? 'Request failed',
        missingDevices: (body['missingDevices'] as List<dynamic>? ?? const [])
            .cast<String>(),
      );
    }
    return body;
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
  }) async {
    final issuedOn = _session;
    final request = http.Request(method, _url(path, query))
      ..headers.addAll(_headers);
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final streamed = await _client.send(request);
    final response = await http.Response.fromStream(streamed);
    _requireSameSession(issuedOn);
    return _decode(response);
  }

  // --- Accounts -------------------------------------------------------------

  /// Registers an account. Note what is *not* here: no phone number, no email.
  Future<Map<String, dynamic>> register({
    required String username,
    required String password,
    required Map<String, dynamic> device,
    String? displayName,
  }) =>
      _send('POST', '/v1/accounts', body: {
        'username': username,
        'password': password,
        if (displayName != null) 'displayName': displayName,
        'device': device,
      },);

  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
    required Map<String, dynamic> device,
    String? totpCode,
  }) =>
      _send('POST', '/v1/sessions', body: {
        'username': username,
        'password': password,
        if (totpCode != null) 'totpCode': totpCode,
        'device': device,
      },);

  Future<Map<String, dynamic>> me() => _send('GET', '/v1/accounts/me');

  Future<void> logout() async => _send('DELETE', '/v1/sessions/current');

  Future<Map<String, dynamic>> updatePrivacy(Map<String, dynamic> privacy) =>
      _send('PATCH', '/v1/accounts/me', body: {'privacy': privacy});

  /// Points the account at an already-uploaded, already-sealed picture.
  Future<void> setAvatar(String mediaId) async =>
      _send('PUT', '/v1/accounts/me/avatar', body: {'mediaId': mediaId});

  Future<void> clearAvatar() async => _send('DELETE', '/v1/accounts/me/avatar');

  /// Sets or clears the duress code. Passing null removes it.
  ///
  /// The current password is required, and the server refuses a code equal to
  /// it — a duress code that is the password would fire on an ordinary sign-in.
  Future<Map<String, dynamic>> setDuressCode({
    required String currentPassword,
    required String? duressCode,
  }) =>
      _send('PUT', '/v1/accounts/me/duress-code', body: {
        'currentPassword': currentPassword,
        'duressCode': duressCode,
      },);

  /// The duress wipe from a device that is already signed in.
  ///
  /// Carries the duress code, not the password: at a lock screen under duress
  /// there is no password being typed. The server answers exactly as it does to
  /// a wrong password, so nothing here can be used to find out whether a code
  /// is set.
  Future<void> wipeAccount(String duressCode) async =>
      _send('POST', '/v1/accounts/me/wipe', body: {'duressCode': duressCode});

  /// Deletes the account for good. The password is required by the server, so
  /// a stolen session cannot end somebody's account.
  Future<void> deleteAccount(String currentPassword) async =>
      _send('DELETE', '/v1/accounts/me', body: {'currentPassword': currentPassword});

  // --- Two-factor -----------------------------------------------------------

  /// Starts setup and returns the shared secret, which is the only time it is
  /// ever handed out. It is not in force until [enableTotp] proves the
  /// authenticator app can produce a code from it.
  Future<Map<String, dynamic>> setUpTotp() =>
      _send('POST', '/v1/accounts/me/totp/setup');

  /// Turns the factor on, once a code from it has been shown to work.
  Future<Map<String, dynamic>> enableTotp(String code) =>
      _send('POST', '/v1/accounts/me/totp/enable', body: {'code': code});

  /// Turning it off asks for the password: a factor anyone holding an unlocked
  /// phone could remove would not be a second factor.
  Future<Map<String, dynamic>> disableTotp(String currentPassword) =>
      _send('DELETE', '/v1/accounts/me/totp', body: {'currentPassword': currentPassword});

  // --- Contacts -------------------------------------------------------------

  Future<Map<String, dynamic>> contacts() => _send('GET', '/v1/contacts');

  Future<Map<String, dynamic>> addContact(String username) =>
      _send('POST', '/v1/contacts', body: {'username': username});

  Future<Map<String, dynamic>> lookup(String username) =>
      _send('GET', '/v1/users/$username');

  /// Resolves an account id to a profile, so a message from someone not yet in
  /// your contacts can show who sent it.
  Future<Map<String, dynamic>> lookupById(String accountId) =>
      _send('GET', '/v1/users/id/$accountId');

  Future<Map<String, dynamic>> invite() => _send('GET', '/v1/contacts/invite');

  Future<void> block(String accountId) async =>
      _send('POST', '/v1/blocks', body: {'accountId': accountId});

  Future<Map<String, dynamic>> blocks() => _send('GET', '/v1/blocks');

  Future<void> unblock(String accountId) async =>
      _send('DELETE', '/v1/blocks/$accountId');

  // --- Keys and messages ----------------------------------------------------

  /// One prekey bundle per device of [username], for opening Signal sessions.
  Future<Map<String, dynamic>> preKeyBundles(String username) =>
      _send('GET', '/v1/keys/$username');

  /// [messages] holds one sealed copy per recipient device.
  ///
  /// [idempotencyKey] makes a retry safe: the server answers the second attempt
  /// with the first one's result rather than delivering the message twice.
  /// [expiresInSeconds] bounds how long the *server* keeps an envelope this
  /// device could not deliver. It is the chat's disappearing-message timer in
  /// the clear; the deletion that matters still happens on the devices, from
  /// the number sealed inside the payload. Without it an undelivered message
  /// set to vanish in thirty seconds sits on the server for the full retention
  /// window waiting for a device that may never come back.
  Future<Map<String, dynamic>> sendMessage({
    required String username,
    required List<Map<String, dynamic>> messages,
    String? idempotencyKey,
    int? expiresInSeconds,
  }) =>
      _send('POST', '/v1/messages', body: {
        'username': username,
        if (idempotencyKey != null) 'idempotencyKey': idempotencyKey,
        if (expiresInSeconds != null) 'expiresInSeconds': expiresInSeconds,
        'messages': messages,
      },);

  Future<Map<String, dynamic>> sendGroupMessage({
    required String groupId,
    required List<Map<String, dynamic>> messages,
    String? idempotencyKey,
    int? expiresInSeconds,
  }) =>
      _send('POST', '/v1/messages/group/$groupId', body: {
        if (idempotencyKey != null) 'idempotencyKey': idempotencyKey,
        if (expiresInSeconds != null) 'expiresInSeconds': expiresInSeconds,
        'messages': messages,
      },);

  Future<Map<String, dynamic>> createGroup({
    required List<String> memberIds,
    String? encryptedMetadata,
  }) =>
      _send('POST', '/v1/groups', body: {
        'memberIds': memberIds,
        if (encryptedMetadata != null) 'encryptedMetadata': encryptedMetadata,
      },);

  Future<Map<String, dynamic>> groups() => _send('GET', '/v1/groups');

  Future<Map<String, dynamic>> group(String groupId) => _send('GET', '/v1/groups/$groupId');

  /// Every device that must receive a copy of the next group message.
  Future<Map<String, dynamic>> groupDevices(String groupId) =>
      _send('GET', '/v1/groups/$groupId/devices');

  Future<void> updateGroupMetadata(String groupId, String encryptedMetadata) async =>
      _send('PATCH', '/v1/groups/$groupId', body: {'encryptedMetadata': encryptedMetadata});

  /// Look a group up by the code in a join link.
  Future<Map<String, dynamic>> groupByInvite(String code) =>
      _send('GET', '/v1/groups/invite/$code');

  Future<Map<String, dynamic>> joinGroup(String groupId, String inviteCode) =>
      _send('POST', '/v1/groups/$groupId/join', body: {'inviteCode': inviteCode});

  /// Removes one member. The same call whether it is somebody else being
  /// removed by an admin or a member showing themselves out.
  Future<void> leaveGroup(String groupId, String accountId) async =>
      _send('DELETE', '/v1/groups/$groupId/members/$accountId');

  Future<void> deleteGroup(String groupId) async =>
      _send('DELETE', '/v1/groups/$groupId');

  // --- Key delivery ---------------------------------------------------------
  //
  // A join link carries no key, so a device that has just joined says so here
  // and a member who holds the key answers with an ordinary sealed message.
  // Nothing in these calls carries key material.

  Future<void> requestChannelKey(String channelId) async =>
      _send('POST', '/v1/channels/$channelId/key-requests');

  Future<Map<String, dynamic>> channelKeyRequests(String channelId) =>
      _send('GET', '/v1/channels/$channelId/key-requests');

  /// Which key version this channel is on, and whether anybody has generated it.
  ///
  /// A null `keyId` is not an error: it means a member was removed and no
  /// device has come online to make the replacement yet.
  Future<Map<String, dynamic>> channelKeyEpoch(String channelId) =>
      _send('GET', '/v1/channels/$channelId/key-epochs/current');

  /// Claims the current epoch for a key this device generated.
  ///
  /// `claimed: false` in the answer means somebody else got there first — two
  /// admins removing two people in the same minute — and the `keyId` returned
  /// is theirs. The label says nothing about the key; the server never has one.
  Future<Map<String, dynamic>> claimChannelKeyEpoch({
    required String channelId,
    required int epoch,
    required String keyId,
  }) =>
      _send('POST', '/v1/channels/$channelId/key-epochs',
          body: {'epoch': epoch, 'keyId': keyId});

  Future<void> clearChannelKeyRequest(String channelId, String deviceId) async =>
      _send('DELETE', '/v1/channels/$channelId/key-requests/$deviceId');

  Future<void> requestGroupKey(String groupId) async =>
      _send('POST', '/v1/groups/$groupId/key-requests');

  Future<Map<String, dynamic>> groupKeyRequests(String groupId) =>
      _send('GET', '/v1/groups/$groupId/key-requests');

  Future<void> clearGroupKeyRequest(String groupId, String deviceId) async =>
      _send('DELETE', '/v1/groups/$groupId/key-requests/$deviceId');

  Future<Map<String, dynamic>> fetchEnvelopes({int limit = 100}) =>
      _send('GET', '/v1/messages', query: {'limit': '$limit'});

  /// Envelopes are redelivered until this is called, so only acknowledge what
  /// has actually been decrypted and written to the local database.
  Future<void> acknowledge(int upToId) async =>
      _send('DELETE', '/v1/messages', query: {'upTo': '$upToId'});

  // --- Channels -------------------------------------------------------------

  /// Creates a channel. The channel key never appears in this call — the
  /// caller generates it, keeps it, and hands it out in the invite link.
  Future<Map<String, dynamic>> createChannel({
    required String visibility,
    String? handle,
    String? title,
    String? description,
    String? category,
    String? encryptedMetadata,
    bool restrictSaving = false,
    String? keyId,
  }) =>
      _send('POST', '/v1/channels', body: {
        if (keyId != null) 'keyId': keyId,
        'visibility': visibility,
        if (handle != null) 'handle': handle,
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        if (category != null) 'category': category,
        if (encryptedMetadata != null) 'encryptedMetadata': encryptedMetadata,
        'restrictSaving': restrictSaving,
      },);

  Future<Map<String, dynamic>> myChannels() => _send('GET', '/v1/channels');

  /// Search over public channels only. A private channel is never listed here.
  Future<Map<String, dynamic>> discoverChannels({String? query, String? category}) =>
      _send('GET', '/v1/channels/discover', query: {
        if (query != null && query.isNotEmpty) 'q': query,
        if (category != null && category.isNotEmpty) 'category': category,
      },);

  /// The only way to reach a private channel.
  Future<Map<String, dynamic>> channelByInvite(String code) =>
      _send('GET', '/v1/channels/invite/$code');

  /// A public channel by handle — exact, because a link names one channel.
  Future<Map<String, dynamic>> channelByHandle(String handle) =>
      _send('GET', '/v1/channels/by-handle/$handle');

  Future<Map<String, dynamic>> channel(String channelId) =>
      _send('GET', '/v1/channels/$channelId');

  Future<Map<String, dynamic>> joinChannel(String channelId, {String? inviteCode}) =>
      _send('POST', '/v1/channels/$channelId/join', body: {
        if (inviteCode != null) 'inviteCode': inviteCode,
      },);

  Future<void> leaveChannel(String channelId) async =>
      _send('DELETE', '/v1/channels/$channelId/members/me');

  /// Points a channel at a picture that has already been uploaded.
  ///
  /// The server enforces which media kind goes with which visibility rather
  /// than trusting the caller — a private channel pointing at the unsealed kind
  /// would publish a picture its owner believes is sealed — so a 400 here is an
  /// answer about the upload, not a bug.
  Future<void> setChannelAvatar(String channelId, String mediaId) async =>
      _send('PUT', '/v1/channels/$channelId/avatar', body: {'mediaId': mediaId});

  Future<void> clearChannelAvatar(String channelId) async =>
      _send('DELETE', '/v1/channels/$channelId/avatar');

  /// Who is in a channel.
  ///
  /// Paged and searched on the server, because a channel with thousands of
  /// subscribers cannot hand the whole list to a phone to filter. `role:
  /// 'admins'` asks for the short list the admin screen shows, which every
  /// member may see — who runs a channel is not a secret from the people in it.
  Future<Map<String, dynamic>> channelMembers(
    String channelId, {
    int? limit,
    String? cursor,
    String? query,
    String? role,
  }) =>
      _send('GET', '/v1/channels/$channelId/members', query: {
        if (limit != null) 'limit': '$limit',
        if (cursor != null) 'cursor': cursor,
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
        if (role != null) 'role': role,
      });

  /// Put people into a channel directly.
  ///
  /// Answers two lists: who went in, and who has to be invited instead because
  /// their own privacy setting does not allow being added.
  Future<Map<String, dynamic>> addChannelMembers(
    String channelId,
    List<String> accountIds,
  ) =>
      _send('POST', '/v1/channels/$channelId/members', body: {'accountIds': accountIds});

  /// Silence a channel for this account, everywhere it is signed in.
  Future<Map<String, dynamic>> muteChannel(String channelId, {DateTime? until}) =>
      _send('PUT', '/v1/channels/$channelId/mute', body: {
        if (until != null) 'until': until.toUtc().toIso8601String(),
      });

  Future<Map<String, dynamic>> unmuteChannel(String channelId) =>
      _send('DELETE', '/v1/channels/$channelId/mute');

  /// What this account may do about a livestream right now.
  ///
  /// `available: false` where the deployment has no media server, which is what
  /// the screen draws as unavailable-with-a-reason rather than as a dead button.
  Future<Map<String, dynamic>> channelLive(String channelId) =>
      _send('GET', '/v1/channels/$channelId/live');

  Future<Map<String, dynamic>> startChannelLive(String channelId) =>
      _send('POST', '/v1/channels/$channelId/live');

  Future<Map<String, dynamic>> endChannelLive(String channelId) =>
      _send('DELETE', '/v1/channels/$channelId/live');

  /// Write to a channel's own inbox. The bytes are sealed before they get here.
  Future<Map<String, dynamic>> writeToChannelInbox(
    String channelId,
    String base64Content,
  ) =>
      _send('POST', '/v1/channels/$channelId/inbox', body: {'content': base64Content});

  Future<Map<String, dynamic>> channelInbox(String channelId, {int limit = 50}) =>
      _send('GET', '/v1/channels/$channelId/inbox', query: {'limit': '$limit'});

  Future<Map<String, dynamic>> markChannelInboxAnswered(String channelId, int messageId) =>
      _send('PUT', '/v1/channels/$channelId/inbox/$messageId');

  /// Promote or demote a member. The server refuses to grant a permission the
  /// caller does not hold, so a rejection here is a real answer, not a bug.
  Future<Map<String, dynamic>> setChannelRole({
    required String channelId,
    required String accountId,
    required String role,
    Map<String, dynamic>? permissions,
  }) =>
      _send('PUT', '/v1/channels/$channelId/members/$accountId/role', body: {
        'role': role,
        if (permissions != null) 'permissions': permissions,
      },);

  Future<void> removeChannelMember(String channelId, String accountId) async =>
      _send('DELETE', '/v1/channels/$channelId/members/$accountId');

  Future<Map<String, dynamic>> updateChannel(
    String channelId, {
    String? title,
    String? description,
    String? category,
    String? encryptedMetadata,
    int? metadataKeyEpoch,
    bool? restrictSaving,
    List<String>? reactionEmojis,
    bool? commentsEnabled,
    bool? showSenderName,
    bool? welcomeEnabled,
    String? welcomeMessage,
    // Three-state on purpose: not passed leaves the colour alone, an explicit
    // null clears it back to the app's own. A nullable parameter cannot say
    // which of the two was meant, so the caller sets the flag.
    bool clearAccent = false,
    String? accent,
    bool clearBackground = false,
    String? background,
    bool clearDiscussionGroup = false,
    String? discussionGroupId,
    bool? directMessagesEnabled,
  }) =>
      _send('PATCH', '/v1/channels/$channelId', body: {
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        if (category != null) 'category': category,
        if (encryptedMetadata != null) 'encryptedMetadata': encryptedMetadata,
        // Which key sealed the name being uploaded. Without it a new member of
        // a rotated private channel reads every post and not the channel's own
        // name, because the name is still under epoch 1.
        if (metadataKeyEpoch != null) 'metadataKeyEpoch': metadataKeyEpoch,
        if (restrictSaving != null) 'restrictSaving': restrictSaving,
        // The menu under a post. Changing it leaves what is already there
        // alone — see migration 017.
        if (reactionEmojis != null) 'reactionEmojis': reactionEmojis,
        // Whether posts have threads under them at all.
        if (commentsEnabled != null) 'commentsEnabled': commentsEnabled,
        if (showSenderName != null) 'showSenderName': showSenderName,
        if (welcomeEnabled != null) 'welcomeEnabled': welcomeEnabled,
        // Public channels only. The server refuses this for a private channel
        // rather than storing its welcome text in the clear — a private
        // channel's goes inside the sealed metadata with its title.
        if (welcomeMessage != null) 'welcomeMessage': welcomeMessage,
        if (clearAccent || accent != null) 'accent': accent,
        if (clearBackground || background != null) 'background': background,
        if (clearDiscussionGroup || discussionGroupId != null)
          'discussionGroupId': discussionGroupId,
        if (directMessagesEnabled != null) 'directMessagesEnabled': directMessagesEnabled,
      },);

  /// Moves a channel past a key version whose key nobody holds.
  ///
  /// The server refuses if anything has been published under it — an epoch
  /// somebody can read is not an orphan — so this cannot strand content.
  Future<Map<String, dynamic>> abandonChannelKeyEpoch({
    required String channelId,
    required int epoch,
  }) =>
      _send('POST', '/v1/channels/$channelId/key-epochs/abandon', body: {'epoch': epoch});

  Future<void> deleteChannel(String channelId) async =>
      _send('DELETE', '/v1/channels/$channelId');

  /// [content] is base64 of the sealed post; the server stores it unread.
  Future<Map<String, dynamic>> publishPost({
    required String channelId,
    required String content,
    String? mediaId,
    int? keyEpoch,
    DateTime? publishAt,
    Map<String, dynamic>? poll,
  }) =>
      _send('POST', '/v1/channels/$channelId/posts', body: {
        'content': content,
        if (mediaId != null) 'mediaId': mediaId,
        // When it should appear. The server treats a time in the past as now,
        // so a clock that is a minute slow does not back-date a post.
        if (publishAt != null) 'publishAt': publishAt.toUtc().toIso8601String(),
        // The poll's *shape* only: how many options, how many may be picked,
        // when it closes. The question and the answers are inside `content`.
        if (poll != null) 'poll': poll,
        // Which key sealed it. The server refuses anything older than the
        // channel's current epoch, which is what stops a post prepared before a
        // removal from reaching the person who was removed.
        if (keyEpoch != null) 'keyEpoch': keyEpoch,
      },);

  Future<Map<String, dynamic>> channelPosts(
    String channelId, {
    int? before,
    int limit = 50,
    bool scheduled = false,
  }) =>
      _send('GET', '/v1/channels/$channelId/posts', query: {
        if (before != null) 'before': '$before',
        'limit': '$limit',
        // The author's own waiting room. The server refuses it to anybody who
        // cannot publish, so this is not what keeps it private.
        if (scheduled) 'scheduled': 'true',
      },);

  /// Rewrites a post. Author only — the server checks, and an admin who can
  /// delete a post still cannot put words in its author's mouth.
  ///
  /// [publishAt] absent leaves the schedule alone; `clearSchedule` publishes a
  /// waiting post now. The two are separate because "do not touch the time" and
  /// "the time is now" are different instructions.
  Future<Map<String, dynamic>> editPost({
    required String channelId,
    required int postId,
    required String content,
    int? keyEpoch,
    DateTime? publishAt,
    bool clearSchedule = false,
  }) =>
      _send('PATCH', '/v1/channels/$channelId/posts/$postId', body: {
        'content': content,
        if (keyEpoch != null) 'keyEpoch': keyEpoch,
        if (clearSchedule)
          'publishAt': null
        else if (publishAt != null)
          'publishAt': publishAt.toUtc().toIso8601String(),
      },);

  Future<void> pinPost(String channelId, int postId, {required bool pinned}) async =>
      _send('PUT', '/v1/channels/$channelId/posts/$postId/pin', body: {'pinned': pinned});

  /// Puts a reaction on a post, or takes this account's own back.
  ///
  /// Both answer with the post's fresh counts, so a tap does not need the whole
  /// feed fetched again to show a number going up. The emoji has to be one the
  /// channel offers; the server refuses anything else.
  Future<Map<String, dynamic>> reactToPost(
    String channelId,
    int postId,
    String emoji,
  ) =>
      _send(
        'PUT',
        '/v1/channels/$channelId/posts/$postId/reactions',
        body: {'emoji': emoji},
      );

  Future<Map<String, dynamic>> unreactToPost(
    String channelId,
    int postId,
    String emoji,
  ) =>
      _send(
        'DELETE',
        '/v1/channels/$channelId/posts/$postId/reactions',
        query: {'emoji': emoji},
      );

  Future<void> deletePost(String channelId, int postId) async =>
      _send('DELETE', '/v1/channels/$channelId/posts/$postId');

  /// This account's whole answer to a poll, replacing whatever was there.
  ///
  /// The whole answer each time rather than one vote at a time: changing a
  /// single-choice answer would otherwise be two calls with a moment in
  /// between where the person has voted twice or not at all. An empty list
  /// takes the vote back.
  Future<Map<String, dynamic>> voteInPoll(
    String channelId,
    int postId,
    List<int> options,
  ) =>
      _send('PUT', '/v1/channels/$channelId/posts/$postId/votes', body: {
        'options': options,
      },);

  // --- Comments -------------------------------------------------------------

  /// The thread under a post, oldest first — a conversation reads forwards.
  Future<Map<String, dynamic>> channelComments(
    String channelId,
    int postId, {
    int? after,
    int limit = 100,
  }) =>
      _send('GET', '/v1/channels/$channelId/posts/$postId/comments', query: {
        if (after != null) 'after': '$after',
        'limit': '$limit',
      },);

  /// Adds one. Sealed with the channel key before it gets here, like a post.
  Future<Map<String, dynamic>> postComment({
    required String channelId,
    required int postId,
    required String content,
    int? keyEpoch,
  }) =>
      _send('POST', '/v1/channels/$channelId/posts/$postId/comments', body: {
        'content': content,
        if (keyEpoch != null) 'keyEpoch': keyEpoch,
      },);

  /// Removes one: your own, or anyone's if you may delete posts.
  Future<void> deleteComment(String channelId, int postId, int commentId) async =>
      _send('DELETE', '/v1/channels/$channelId/posts/$postId/comments/$commentId');

  // --- Ownership, reporting and numbers --------------------------------------

  /// Hands the channel to another member.
  ///
  /// The password, not the session: every other admin action here can be
  /// undone by the owner, and this one cannot.
  Future<void> transferChannel({
    required String channelId,
    required String toAccountId,
    required String currentPassword,
  }) async =>
      _send('POST', '/v1/channels/$channelId/owner', body: {
        'accountId': toAccountId,
        'currentPassword': currentPassword,
      },);

  /// Reports a channel. The reason is one of a fixed set — see the screen for
  /// why there is no free-text field.
  Future<void> reportChannel(String channelId, String reason) async =>
      _send('POST', '/v1/channels/$channelId/report', body: {'reason': reason});

  /// What the channel adds up to, for whoever runs it.
  Future<Map<String, dynamic>> channelStats(String channelId) =>
      _send('GET', '/v1/channels/$channelId/stats');

  // --- Invite links ---------------------------------------------------------

  /// What the link is allowed to do. Absent fields are left alone; an explicit
  /// null clears a limit, which is why the two flags are separate.
  Future<Map<String, dynamic>> setInviteSettings(
    String channelId, {
    DateTime? expiresAt,
    bool clearExpiry = false,
    int? maxUses,
    bool clearMaxUses = false,
    bool? needsApproval,
  }) =>
      _send('PUT', '/v1/channels/$channelId/invite', body: {
        if (clearExpiry)
          'expiresAt': null
        else if (expiresAt != null)
          'expiresAt': expiresAt.toUtc().toIso8601String(),
        if (clearMaxUses)
          'maxUses': null
        else if (maxUses != null)
          'maxUses': maxUses,
        if (needsApproval != null) 'needsApproval': needsApproval,
      },);

  /// Revokes the link by replacing it. Every copy of the old one stops
  /// resolving at once, and the use counter starts again from nothing.
  Future<Map<String, dynamic>> rotateInvite(String channelId) =>
      _send('POST', '/v1/channels/$channelId/invite/rotate');

  /// Who is waiting at the door. Admins only; the server refuses the rest.
  Future<Map<String, dynamic>> joinRequests(String channelId) =>
      _send('GET', '/v1/channels/$channelId/join-requests');

  Future<void> answerJoinRequest(
    String channelId,
    String accountId, {
    required bool admit,
  }) async =>
      _send(
        admit ? 'POST' : 'DELETE',
        '/v1/channels/$channelId/join-requests/$accountId',
      );

  // --- Silencing ------------------------------------------------------------

  /// Stops somebody commenting and reacting, without removing them.
  ///
  /// Deliberately lighter than removal, which rotates the key and cuts them off
  /// from reading as well.
  Future<void> banFromChannel(String channelId, String accountId) async =>
      _send('PUT', '/v1/channels/$channelId/bans/$accountId');

  Future<void> unbanFromChannel(String channelId, String accountId) async =>
      _send('DELETE', '/v1/channels/$channelId/bans/$accountId');

  /// Who is silenced. Admins only — the server refuses everybody else, because
  /// the list would name who else reads the channel.
  Future<Map<String, dynamic>> channelBans(String channelId) =>
      _send('GET', '/v1/channels/$channelId/bans');

  // --- Devices --------------------------------------------------------------

  /// How many one-time prekeys the server still holds for this device.
  Future<int> preKeyCount() async =>
      (await _send('GET', '/v1/keys/count'))['remaining'] as int;

  Future<void> uploadPreKeys(List<Map<String, dynamic>> keys) async =>
      _send('POST', '/v1/keys/one-time', body: {'keys': keys});

  Future<void> rotateSignedPreKey(Map<String, dynamic> signedPreKey) async =>
      _send('PUT', '/v1/keys/signed-prekey', body: signedPreKey);

  Future<Map<String, dynamic>> devices() => _send('GET', '/v1/devices');

  Future<void> revokeDevice(String deviceId) async =>
      _send('DELETE', '/v1/devices/$deviceId');

  /// Registers, or with both arguments null clears, how this device is woken.
  ///
  /// For `unifiedpush` the token is an endpoint URL the server will POST to,
  /// so it is validated there rather than trusted — see the server's
  /// util/outbound.ts. For APNs and FCM it is an opaque vendor handle.
  Future<void> registerPushToken({
    required String? provider,
    required String? token,
  }) async =>
      _send('PUT', '/v1/devices/current/push', body: {
        'provider': provider,
        'token': token,
      },);

  // --- Licensing ------------------------------------------------------------

  /// What this server is and whether it sells licences at all.
  ///
  /// The only call the app makes before anyone has signed in. It has to be:
  /// the key screen comes first, and whether to show it is the server's answer,
  /// not the build's — a self-hosted deployment says `licenseRequired: false`
  /// and is never asked for a key.
  Future<Map<String, dynamic>> serverInfo() => _send('GET', '/v1/server');

  /// Where this deployment's STUN and TURN servers are, with credentials for
  /// the relay if it has one.
  ///
  /// Authenticated, because a TURN credential is somebody's bandwidth.
  Future<Map<String, dynamic>> iceServers() => _send('GET', '/v1/calls/ice');

  /// What this account's license looks like from the server's side.
  ///
  /// `required` is the field that matters most: a self-hosted deployment
  /// answers false, and a client that sees it must not ask anyone for a key.
  Future<Map<String, dynamic>> licenseStatus() => _send('GET', '/v1/licenses/me');

  /// Redeems a key for the signed-in account. Rate limited hard on the server:
  /// the key is the only credential, so guessing must never be cheap.
  Future<Map<String, dynamic>> redeemLicense(String licenseKey) =>
      _send('POST', '/v1/licenses/redeem', body: {'licenseKey': licenseKey});

  // --- Media and backup -----------------------------------------------------

  /// An uploaded blob: where it lives, and what opens it.
  ///
  /// The token is handed back once and never stored server-side, so it has to
  /// travel inside the sealed payload with the media key. Losing it means the
  /// bytes cannot be fetched again, which is the point.
  Future<({String id, String? token})> uploadMedia(
    List<int> sealedBytes, {
    bool avatar = false,
    bool channelAvatar = false,
    int? expiresInSeconds,
  }) async {
    // Three kinds, and the kind decides who may download. `channel_avatar` is
    // the one that is served to anyone — a public channel's picture is drawn on
    // a web page by people who hold no key — so it is only ever passed for
    // bytes that were deliberately not sealed.
    final kind = channelAvatar
        ? const {'kind': 'channel_avatar'}
        : avatar
            ? const {'kind': 'avatar'}
            : null;
    // An attachment to a message that is set to disappear is worth keeping only
    // as long as the message can still be fetched and read. Passed to the
    // server because a timer that only runs on a screen leaves the ciphertext
    // where it was; the server clamps it, and never lengthens the default.
    final query = expiresInSeconds == null
        ? kind
        : {...?kind, 'expiresInSeconds': '$expiresInSeconds'};
    final issuedOn = _session;
    final response = await _client.post(
      _url('/v1/media', query),
      headers: {..._headers, 'content-type': 'application/octet-stream'},
      body: sealedBytes,
    );
    _requireSameSession(issuedOn);
    final body = await _decode(response);
    return (id: body['id'] as String, token: body['token'] as String?);
  }

  Future<List<int>> downloadMedia(String id, {String? token}) async {
    final issuedOn = _session;
    final response = await _client.get(
      _url('/v1/media/$id'),
      headers: {
        ..._headers,
        if (token != null) 'x-privio-media-token': token,
      },
    );
    _requireSameSession(issuedOn);
    if (response.statusCode >= 400) await _decode(response);
    return response.bodyBytes;
  }

  Future<Map<String, dynamic>> uploadBackup(List<int> sealedBytes) async {
    final issuedOn = _session;
    final response = await _client.put(
      _url('/v1/backup'),
      headers: {..._headers, 'content-type': 'application/octet-stream'},
      body: sealedBytes,
    );
    _requireSameSession(issuedOn);
    return _decode(response);
  }

  Future<Map<String, dynamic>> backupInfo() => _send('GET', '/v1/backup');

  /// The sealed backup itself. Ciphertext on the way down, exactly as it went
  /// up: the server has never been able to read a byte of it.
  Future<List<int>> downloadBackup() async {
    final issuedOn = _session;
    final response = await _client.get(_url('/v1/backup/content'), headers: _headers);
    _requireSameSession(issuedOn);
    if (response.statusCode >= 400) await _decode(response);
    return response.bodyBytes;
  }

  void close() => _client.close();
}
