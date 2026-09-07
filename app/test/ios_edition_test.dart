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

  /// Every `flutter build ios` **command**, by workflow file.
  ///
  /// Commands, not the file's text: a comment that mentions the command — and
  /// there is one, explaining why the iOS job stopped using it in one piece —
  /// is prose, and matching it made this guard read the wrong 200 characters
  /// and fail on a workflow that was perfectly correct. A command is a line
  /// that begins with the command, plus the folded continuations under it.
  Map<String, List<String>> iosBuildCommands() {
    final found = <String, List<String>>{};
    final dir = Directory('${root.path}/.github/workflows');
    for (final file in dir.listSync().whereType<File>()) {
      final lines = file.readAsStringSync().split('\n');
      final commands = <String>[];
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].trimLeft().startsWith('flutter build ios')) continue;
        final buffer = StringBuffer(lines[i].trim());
        // Folded YAML (`>-`) puts each argument on its own indented line.
        for (var j = i + 1; j < lines.length; j++) {
          final next = lines[j].trim();
          if (!next.startsWith('-')) break;
          buffer.write(' $next');
        }
        commands.add(buffer.toString());
      }
      if (commands.isNotEmpty) found[file.uri.pathSegments.last] = commands;
    }
    return found;
  }

  test('there is an iOS build to check at all', () {
    expect(iosBuildCommands(), isNotEmpty, reason: 'no workflow builds for iOS any more?');
  });

  test('every iOS build is told it is the App Store edition', () {
    for (final entry in iosBuildCommands().entries) {
      for (final command in entry.value) {
        expect(
          command,
          contains('PRIVIO_EDITION=appstore'),
          reason: '${entry.key} builds iOS without saying it is the App Store edition: $command',
        );
      }
    }
  });

  test('and never as one of the Android editions', () {
    for (final entry in iosBuildCommands().entries) {
      for (final command in entry.value) {
        for (final wrong in [
          'PRIVIO_EDITION=libre',
          'PRIVIO_EDITION=direct',
          'PRIVIO_EDITION=play',
        ]) {
          expect(command, isNot(contains(wrong)), reason: '${entry.key}: $wrong on an iOS build');
        }
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
