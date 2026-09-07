import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:privio/core/edition.dart';

/// The iOS build has to say which edition it is, and say `appstore`.
///
/// It said `libre`, copied from the Android job sitting above it in the same
/// file. That produced an App Store binary that reported itself as free
/// software, offered the licence-key screen a store build must never show, and
/// registered for UnifiedPush instead of APNs — none of it visible in a build
/// log, and all of it only findable by reading the workflow.
///
/// Guarded here because the mistake is a copy-paste between two jobs that look
/// alike, which is exactly the sort that comes back.
void main() {
  final root = Directory.current.path.endsWith('/app')
      ? Directory(Directory.current.parent.path)
      : Directory.current;

  /// The lines of every job that builds for iOS, one string per workflow.
  Map<String, String> iosBuildSteps() {
    final found = <String, String>{};
    final dir = Directory('${root.path}/.github/workflows');
    for (final file in dir.listSync().whereType<File>()) {
      final text = file.readAsStringSync();
      if (!text.contains('flutter build ios')) continue;
      found[file.uri.pathSegments.last] = text;
    }
    return found;
  }

  test('there is an iOS build to check at all', () {
    expect(iosBuildSteps(), isNotEmpty, reason: 'no workflow builds for iOS any more?');
  });

  test('every iOS build is told it is the App Store edition', () {
    for (final entry in iosBuildSteps().entries) {
      // The `flutter build ios` command and whatever follows it on the folded
      // continuation lines.
      final index = entry.value.indexOf('flutter build ios');
      final command = entry.value.substring(index, index + 200);
      expect(
        command,
        contains('PRIVIO_EDITION=appstore'),
        reason: '${entry.key} builds iOS without saying it is the App Store edition',
      );
    }
  });

  test('and never as one of the Android editions', () {
    for (final entry in iosBuildSteps().entries) {
      final index = entry.value.indexOf('flutter build ios');
      final command = entry.value.substring(index, index + 200);
      for (final wrong in ['PRIVIO_EDITION=libre', 'PRIVIO_EDITION=direct', 'PRIVIO_EDITION=play']) {
        expect(command, isNot(contains(wrong)), reason: '${entry.key}: $wrong on an iOS build');
      }
    }
  });

  test('the App Store edition is the one that uses APNs and no licence key', () {
    // What the workflow is now selecting, asserted so the two halves cannot
    // drift apart: a correct define pointing at a wrong configuration would be
    // the same bug wearing a different hat.
    final appstore = PrivioEdition.parse('appstore');
    expect(appstore.pushProvider, 'apns');
    expect(appstore.usesLicenseKey, isFalse, reason: 'it was paid for in the store');
    expect(appstore.usesProprietaryServices, isTrue);
  });
}
