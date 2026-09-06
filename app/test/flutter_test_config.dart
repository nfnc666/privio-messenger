import 'dart:async';

import 'package:privio/core/passcode_vault.dart';

/// Runs before every test file in this directory.
///
/// Argon2id is deliberately expensive, and the suite touches it hundreds of
/// times — setting a lock, unlocking, every wrong code a calculator disguise
/// is fed. At production cost the disguise tests alone took over ten minutes.
/// Turning it down here keeps what those tests are actually about: the right
/// code opens, a wrong one does not, and the history follows the passcode.
///
/// `passcode_vault_test.dart` puts the real parameters back for itself, because
/// there the cost *is* the subject.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  PasscodeVault.useCheapParameters();
  await testMain();
}
