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

  bool get isAuthenticated => _token != null;

  void useToken(String? token) => _token = token;

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
    final request = http.Request(method, _url(path, query))
      ..headers.addAll(_headers);
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final streamed = await _client.send(request);
    return _decode(await http.Response.fromStream(streamed));
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

  Future<Map<String, dynamic>> addContact(String username, {String? alias}) =>
      _send('POST', '/v1/contacts', body: {
        'username': username,
        if (alias != null) 'alias': alias,
      },);

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
  Future<Map<String, dynamic>> sendMessage({
    required String username,
    required List<Map<String, dynamic>> messages,
    String? idempotencyKey,
  }) =>
      _send('POST', '/v1/messages', body: {
        'username': username,
        if (idempotencyKey != null) 'idempotencyKey': idempotencyKey,
        'messages': messages,
      },);

  Future<Map<String, dynamic>> sendGroupMessage({
    required String groupId,
    required List<Map<String, dynamic>> messages,
    String? idempotencyKey,
  }) =>
      _send('POST', '/v1/messages/group/$groupId', body: {
        if (idempotencyKey != null) 'idempotencyKey': idempotencyKey,
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

  Future<void> leaveGroup(String groupId, String accountId) async =>
      _send('DELETE', '/v1/groups/$groupId/members/$accountId');

  // --- Key delivery ---------------------------------------------------------
  //
  // A join link carries no key, so a device that has just joined says so here
  // and a member who holds the key answers with an ordinary sealed message.
  // Nothing in these calls carries key material.

  Future<void> requestChannelKey(String channelId) async =>
      _send('POST', '/v1/channels/$channelId/key-requests');

  Future<Map<String, dynamic>> channelKeyRequests(String channelId) =>
      _send('GET', '/v1/channels/$channelId/key-requests');

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
  }) =>
      _send('POST', '/v1/channels', body: {
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

  Future<Map<String, dynamic>> channel(String channelId) =>
      _send('GET', '/v1/channels/$channelId');

  Future<Map<String, dynamic>> joinChannel(String channelId, {String? inviteCode}) =>
      _send('POST', '/v1/channels/$channelId/join', body: {
        if (inviteCode != null) 'inviteCode': inviteCode,
      },);

  Future<void> leaveChannel(String channelId) async =>
      _send('DELETE', '/v1/channels/$channelId/members/me');

  Future<Map<String, dynamic>> channelMembers(String channelId) =>
      _send('GET', '/v1/channels/$channelId/members');

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
    bool? restrictSaving,
  }) =>
      _send('PATCH', '/v1/channels/$channelId', body: {
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        if (category != null) 'category': category,
        if (encryptedMetadata != null) 'encryptedMetadata': encryptedMetadata,
        if (restrictSaving != null) 'restrictSaving': restrictSaving,
      },);

  Future<void> deleteChannel(String channelId) async =>
      _send('DELETE', '/v1/channels/$channelId');

  /// [content] is base64 of the sealed post; the server stores it unread.
  Future<Map<String, dynamic>> publishPost({
    required String channelId,
    required String content,
    String? mediaId,
  }) =>
      _send('POST', '/v1/channels/$channelId/posts', body: {
        'content': content,
        if (mediaId != null) 'mediaId': mediaId,
      },);

  Future<Map<String, dynamic>> channelPosts(String channelId, {int? before, int limit = 50}) =>
      _send('GET', '/v1/channels/$channelId/posts', query: {
        if (before != null) 'before': '$before',
        'limit': '$limit',
      },);

  Future<void> pinPost(String channelId, int postId, {required bool pinned}) async =>
      _send('PUT', '/v1/channels/$channelId/posts/$postId/pin', body: {'pinned': pinned});

  Future<void> deletePost(String channelId, int postId) async =>
      _send('DELETE', '/v1/channels/$channelId/posts/$postId');

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

  /// Uploads bytes that are already encrypted; returns the object id to put in
  /// the message alongside the key.
  Future<String> uploadMedia(List<int> sealedBytes) async {
    final response = await _client.post(
      _url('/v1/media'),
      headers: {..._headers, 'content-type': 'application/octet-stream'},
      body: sealedBytes,
    );
    final body = await _decode(response);
    return body['id'] as String;
  }

  Future<List<int>> downloadMedia(String id) async {
    final response = await _client.get(_url('/v1/media/$id'), headers: _headers);
    if (response.statusCode >= 400) await _decode(response);
    return response.bodyBytes;
  }

  Future<Map<String, dynamic>> uploadBackup(List<int> sealedBytes) async {
    final response = await _client.put(
      _url('/v1/backup'),
      headers: {..._headers, 'content-type': 'application/octet-stream'},
      body: sealedBytes,
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> backupInfo() => _send('GET', '/v1/backup');

  /// The sealed backup itself. Ciphertext on the way down, exactly as it went
  /// up: the server has never been able to read a byte of it.
  Future<List<int>> downloadBackup() async {
    final response = await _client.get(_url('/v1/backup/content'), headers: _headers);
    if (response.statusCode >= 400) await _decode(response);
    return response.bodyBytes;
  }

  void close() => _client.close();
}
