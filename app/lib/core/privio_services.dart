import '../crypto/crypto_storage.dart';
import '../crypto/privio_crypto.dart';
import '../data/archive.dart';
import '../data/message_store.dart';
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
    required this.store,
    required this.secureStore,
    MessageArchive? archive,
  }) : archive = archive ?? const NoArchive();

  /// Where the API lives. Overridden at build time:
  /// `flutter run --dart-define=PRIVIO_API_URL=https://api.privio.app`
  static const String apiBaseUrl = String.fromEnvironment(
    'PRIVIO_API_URL',
    defaultValue: 'http://localhost:8080',
  );

  static Future<PrivioServices> create({
    String? baseUrl,
    CryptoStorage? cryptoStorage,
    SecureStore secureStore = const KeystoreSecureStore(),
  }) async {
    final api = PrivioApiClient(baseUrl: Uri.parse(baseUrl ?? apiBaseUrl));
    final crypto = await PrivioCrypto.open(cryptoStorage ?? const KeystoreCryptoStorage());
    final messaging = MessagingService(api: api, crypto: crypto);
    return PrivioServices(
      api: api,
      crypto: crypto,
      messaging: messaging,
      channels: ChannelService(api: api, crypto: crypto, messaging: messaging),
      store: InMemoryMessageStore(),
      secureStore: secureStore,
      archive: EncryptedMessageArchive(
        storage: const KeystoreArchiveStorage(),
        keyStore: secureStore,
      ),
    );
  }

  final PrivioApiClient api;
  final PrivioCrypto crypto;
  final MessagingService messaging;
  final ChannelService channels;
  final MessageStore store;
  final SecureStore secureStore;

  /// Where the decrypted history is kept between launches, sealed at rest.
  final MessageArchive archive;

  void dispose() => api.close();
}
