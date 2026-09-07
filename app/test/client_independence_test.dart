import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The client must be buildable by somebody who has never seen the server.
///
/// That is the whole premise of the planned split: the app is public, the
/// central server is not. It is easy to break by accident — a shared constant
/// imported across the boundary, a test fixture reaching into `server/`, a
/// generated file checked in from somewhere else — and it breaks silently,
/// because in this repository both trees are sitting right there.
///
/// So it is asserted rather than assumed, from the source rather than from a
/// build: what the app compiles from must not mention the server tree.
void main() {
  final appRoot = Directory.current.path.endsWith('/app')
      ? Directory.current
      : Directory('${Directory.current.path}/app');

  List<File> dartFiles(String under) {
    final dir = Directory('${appRoot.path}/$under');
    if (!dir.existsSync()) return const [];
    return dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
  }

  test('no client source reaches into the server tree', () {
    final offenders = <String>[];
    for (final file in [...dartFiles('lib'), ...dartFiles('test')]) {
      final source = file.readAsStringSync();
      for (final line in source.split('\n')) {
        final trimmed = line.trimLeft();
        if (!trimmed.startsWith('import ') && !trimmed.startsWith('export ')) continue;
        // A relative import climbing out of `app/`, or anything naming the
        // server package. Both would make the client unbuildable on its own.
        if (trimmed.contains('../../server') ||
            trimmed.contains("package:privio_server") ||
            trimmed.contains("'server/")) {
          offenders.add('${file.path}: $trimmed');
        }
      }
    }
    expect(offenders, isEmpty, reason: 'the client would not build without the server source');
  });

  test('the app declares no path dependency outside its own directory', () {
    // A `path:` dependency pointing up and out would tie the public client to
    // a directory that will not be in the public repository.
    final pubspec = File('${appRoot.path}/pubspec.yaml').readAsStringSync();
    final outward = RegExp(r'path:\s*\.\./').allMatches(pubspec).map((m) => m.group(0));
    expect(outward, isEmpty, reason: 'found a dependency reaching outside app/');
  });

  test('the API the client speaks is documented in the public tree', () {
    // A public client and a private server meet at a documented interface. If
    // that document is not in the client's own repository, whoever forks the
    // client has an app that talks to something they cannot read about.
    final doc = File('${appRoot.path}/../docs/server-api.md');
    expect(
      doc.existsSync(),
      isTrue,
      reason: 'docs/server-api.md is what makes the client independently buildable',
    );
    final text = doc.readAsStringSync();
    for (final route in ['/v1/accounts', '/v1/messages', '/v1/licenses/redeem']) {
      expect(text, contains(route), reason: 'the API document must cover $route');
    }
  });
}
