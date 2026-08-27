import 'dart:typed_data';

import '../core/api_client.dart';
import '../core/secure_store.dart';
import '../data/backup.dart';
import '../data/message_store.dart';
import '../data/recovery_key.dart';

/// How often a backup is made without being asked for.
enum BackupInterval { off, daily, weekly }

extension BackupIntervalLabel on BackupInterval {
  String get label => switch (this) {
        BackupInterval.off => 'Off',
        BackupInterval.daily => 'Daily',
        BackupInterval.weekly => 'Weekly',
      };

  Duration? get period => switch (this) {
        BackupInterval.off => null,
        BackupInterval.daily => const Duration(days: 1),
        BackupInterval.weekly => const Duration(days: 7),
      };
}

/// What the server says it is holding for this account.
class RemoteBackup {
  const RemoteBackup({required this.byteSize, required this.version, required this.updatedAt});

  final int byteSize;
  final int version;
  final DateTime updatedAt;

  String get readableSize {
    if (byteSize < 1024) return '$byteSize B';
    if (byteSize < 1024 * 1024) return '${(byteSize / 1024).toStringAsFixed(0)} KB';
    return '${(byteSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Backups, sealed on this device and unreadable anywhere else.
///
/// The server is a place to put bytes. It is handed ciphertext, it hands the
/// same ciphertext back, and it cannot do anything else with it — there is no
/// reset, no recovery flow, no support ticket that opens a backup. That is the
/// deliberate cost of the guarantee, and the UI says so rather than implying a
/// safety net that is not there.
class BackupService {
  BackupService({
    required PrivioApiClient api,
    required SecureStore store,
    required MessageStore messages,
  })  : _api = api,
        _store = store,
        _messages = messages;

  final PrivioApiClient _api;
  final SecureStore _store;
  final MessageStore _messages;

  /// The recovery key for this device, generating one on first use.
  ///
  /// Generated rather than derived from anything: a key derived from a password
  /// is only as good as the password, and this one has to stand alone.
  Future<RecoveryKey> recoveryKey() async {
    final stored = await _store.readRecoveryKey();
    final parsed = stored == null ? null : RecoveryKey.parse(stored);
    if (parsed != null) return parsed;

    final generated = RecoveryKey.generate();
    await _store.writeRecoveryKey(generated.formatted);
    return generated;
  }

  /// Replaces the recovery key — used after restoring on a new device, where
  /// the key came from the person rather than from here.
  Future<void> adoptRecoveryKey(RecoveryKey key) =>
      _store.writeRecoveryKey(key.formatted);

  Future<BackupInterval> interval() async {
    final stored = await _store.readBackupInterval();
    return BackupInterval.values.firstWhere(
      (value) => value.name == stored,
      orElse: () => BackupInterval.weekly,
    );
  }

  Future<void> setInterval(BackupInterval value) =>
      _store.writeBackupInterval(value.name);

  Future<DateTime?> lastBackupAt() => _store.readLastBackupAt();

  /// The sealed bytes of a backup of what is on this device right now.
  ///
  /// Split out from uploading so the same bytes can be written to a file the
  /// user keeps themselves: a backup on a server you do not run is a different
  /// kind of trust from one on a disk you do.
  Future<Uint8List> build() async => BackupCodec.seal(
        _messages.conversations(),
        recovery: await recoveryKey(),
      );

  /// Seals and uploads. Returns the size that went up.
  Future<int> backUpNow() async {
    final sealed = await build();
    await _api.uploadBackup(sealed);
    await _store.writeLastBackupAt(DateTime.now());
    return sealed.length;
  }

  /// Backs up if the interval has come round. Called when the app goes away,
  /// which is the moment a backup is both cheap and most likely to matter.
  Future<bool> backUpIfDue() async {
    final period = (await interval()).period;
    if (period == null) return false;
    final last = await lastBackupAt();
    if (last != null && DateTime.now().difference(last) < period) return false;
    try {
      await backUpNow();
      return true;
    } on Object {
      // A missed automatic backup is not worth an error in someone's face; the
      // next one will catch it, and the screen shows when the last one was.
      return false;
    }
  }

  /// What the server holds, or null when it holds nothing.
  Future<RemoteBackup?> remote() async {
    try {
      final info = await _api.backupInfo();
      return RemoteBackup(
        byteSize: info['byteSize'] as int? ?? 0,
        version: info['version'] as int? ?? 1,
        updatedAt: DateTime.tryParse(info['updatedAt'] as String? ?? '')?.toLocal() ??
            DateTime.now(),
      );
    } on ApiException catch (failure) {
      if (failure.code == 'no_backup') return null;
      rethrow;
    }
  }

  /// Downloads and opens the backup, and replaces the local history with it.
  ///
  /// Replaces rather than merges: two histories of the same conversation cannot
  /// be interleaved without guessing, and a restore is something people do to a
  /// device that has nothing on it.
  Future<BackupContents> restoreFromServer(RecoveryKey key) async {
    final sealed = Uint8List.fromList(await _api.downloadBackup());
    return _apply(sealed, key);
  }

  /// The same, from a file the user kept.
  Future<BackupContents> restoreFromFile(Uint8List sealed, RecoveryKey key) =>
      _apply(sealed, key);

  Future<BackupContents> _apply(Uint8List sealed, RecoveryKey key) async {
    final contents = await BackupCodec.open(sealed, key);
    _messages.restore(contents.conversations);
    await adoptRecoveryKey(key);
    return contents;
  }

  /// A name that says what the file is and when it was made, without saying
  /// whose it is.
  static String fileNameFor(DateTime when) {
    String two(int value) => value.toString().padLeft(2, '0');
    return 'privio-backup-${when.year}${two(when.month)}${two(when.day)}.privio';
  }

  /// The recovery key as it goes into a QR code, for moving to a new device.
  static String qrPayload(RecoveryKey key) => 'privio://recovery/${key.formatted}';

  /// Reads back what [qrPayload] wrote, or a key typed in by hand.
  static RecoveryKey? parseScanned(String scanned) {
    const prefix = 'privio://recovery/';
    final body = scanned.startsWith(prefix) ? scanned.substring(prefix.length) : scanned;
    return RecoveryKey.parse(body);
  }
}
