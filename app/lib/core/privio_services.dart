import 'dart:async';

import '../calls/call.dart';
import '../calls/ice_servers.dart';
import '../calls/webrtc_call_peer.dart';
import '../crypto/crypto_storage.dart';
import '../crypto/privio_crypto.dart';
import '../data/archive.dart';
import '../data/message_store.dart';
import '../media/voice_player.dart';
import '../media/voice_recorder.dart';
import '../services/backup_service.dart';
import '../services/call_service.dart';
import '../services/channel_service.dart';
import '../services/messaging_service.dart';
import 'api_client.dart';
import 'secure_store.dart';

/// Everything the app needs that is not a widget, assembled once.
///
/// Deliberately a plain object rather than a service-locator package: it is
/// created at startup, handed down through the widget tree, and swapped whole
/// in tests.
class PrivioServices {
  PrivioServices({
    required this.api,
    required this.crypto,
    required this.messaging,
    required this.channels,
    CallService? calls,
    required this.recorder,
    required this.player,
    required this.backup,
    required this.store,
    required this.secureStore,
    MessageArchive? archive,
  }) : archive = archive ?? const NoArchive() {
    // Assembled here rather than in the initialiser list because it is built
    // out of three of the fields above. A caller may still pass its own, which
    // is how a test drives a call without a microphone in the room.
    ice = IceServerCache(api: api);
    this.calls = calls ??
        CallService(
          messaging: messaging,
          peers: (iceServers) => WebRtcCallPeer(iceServers: iceServers),
          ice: ice,
          lookUp: (accountId) async {
            final known = store.conversationWith(accountId)?.user;
            return known == null ? null : CallParty(accountId: accountId, username: known.username);
          },
          store: secureStore,
        );
  }

  /// Where the API lives. Overridden at build time:
  /// `flutter run --dart-define=PRIVIO_API_URL=https://api.privio.app`
  static const String apiBaseUrl = String.fromEnvironment(
    'PRIVIO_API_URL',
    defaultValue: 'http://localhost:8080',
  );

  static Future<PrivioServices> create({
    String? baseUrl,
    CryptoStorage? cryptoStorage,
    SecureStore? secureStore,
  }) async {
    // One instance, shared: it holds the archive key the passcode opened, and
    // two of them would mean one half of the app locked out of the other.
    final secure = secureStore ?? KeystoreSecureStore();
    final api = PrivioApiClient(baseUrl: Uri.parse(baseUrl ?? apiBaseUrl));
    final crypto = await PrivioCrypto.open(cryptoStorage ?? const KeystoreCryptoStorage());
    final messaging = MessagingService(api: api, crypto: crypto);
    final store = InMemoryMessageStore();
    return PrivioServices(
      api: api,
      crypto: crypto,
      messaging: messaging,
      channels: ChannelService(api: api, crypto: crypto, messaging: messaging),
      recorder: PluginVoiceRecorder(),
      player: JustAudioVoicePlayer(),
      backup: BackupService(api: api, store: secure, messages: store),
      store: store,
      secureStore: secure,
      archive: EncryptedMessageArchive(
        storage: const KeystoreArchiveStorage(),
        keyStore: secure,
      ),
    );
  }

  final PrivioApiClient api;
  final PrivioCrypto crypto;
  final MessagingService messaging;
  final ChannelService channels;

  /// Calls. The media is libwebrtc's; the signalling that sets it up travels
  /// as ordinary sealed payloads, so the addresses inside it are not the
  /// server's to read.
  late final CallService calls;

  /// Where this deployment's STUN and TURN servers are, held between calls.
  ///
  /// Filled when the app is up rather than when a call starts: asking at the
  /// moment of a call would tell the server that one is about to happen, and
  /// the signalling is sealed precisely so it cannot know that.
  late final IceServerCache ice;

  /// Recording and playback sit behind interfaces for the same reason the
  /// keystore does: the whole voice-message path is testable without hardware,
  /// and the one part that genuinely needs a microphone stays in one file.
  final VoiceRecorder recorder;
  final VoicePlayer player;

  /// Backups: sealed here, opaque everywhere else.
  final BackupService backup;
  final MessageStore store;
  final SecureStore secureStore;

  /// Where the decrypted history is kept between launches, sealed at rest.
  final MessageArchive archive;

  void dispose() {
    calls.dispose();
    unawaited(recorder.dispose());
    unawaited(player.dispose());
    api.close();
  }
}
