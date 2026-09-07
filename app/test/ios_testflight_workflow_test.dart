import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The signed iOS build is the one workflow that holds a real Apple identity
/// and can put a build in front of testers. Three properties of it are worth
/// asserting rather than trusting to review, because all three are the kind of
/// thing an edit makes true by accident:
///
///  * it only ever runs because somebody started it,
///  * it does not upload to TestFlight unless that run asked for it, and
///  * no secret is ever written somewhere a log can keep it.
///
/// This reads the workflow as text on purpose. A YAML parser would need a
/// dependency the client does not otherwise have, and the properties here are
/// about what the file says.
void main() {
  final root = Directory.current.path.endsWith('/app')
      ? Directory(Directory.current.parent.path)
      : Directory.current;
  final file = File('${root.path}/.github/workflows/ios-testflight.yml');
  final text = file.existsSync() ? file.readAsStringSync() : '';

  test('the signed build workflow exists', () {
    expect(file.existsSync(), isTrue, reason: 'no ${file.path}');
  });

  test('it can only be started by hand', () {
    // Anything else would sign — and possibly distribute — because a branch
    // moved. The `on:` block ends at the first line that is back at column 0.
    final on = text.substring(text.indexOf('\non:') + 1);
    final block = on.substring(0, on.indexOf(RegExp(r'\n[a-z]', multiLine: true), 1));
    expect(block, contains('workflow_dispatch'));
    expect(block, isNot(contains('push:')), reason: 'a push must not sign a build');
    expect(block, isNot(contains('pull_request')), reason: 'a pull request must not sign a build');
    expect(block, isNot(contains('schedule')), reason: 'nothing here should happen on a timer');
    expect(block, isNot(contains('release:')));
  });

  test('the TestFlight upload is off unless the run asks for it', () {
    final upload = text.substring(text.indexOf('      upload:'));
    final declaration = upload.substring(0, upload.indexOf('      bundle_id:'));
    expect(
      declaration,
      contains(RegExp(r'''default:\s*"no"''')),
      reason: 'uploading to TestFlight must be a decision, not a default',
    );

    expect(
      text,
      contains("if: inputs.upload == 'yes'"),
      reason: 'the upload step must be conditional on the input',
    );
    // And the condition guards the step that actually talks to Apple.
    final guard = text.indexOf("if: inputs.upload == 'yes'");
    final uploadCall = text.indexOf('altool --upload-app');
    expect(uploadCall, greaterThan(guard));
    expect(
      text.substring(guard, uploadCall),
      isNot(contains('\n      - name:')),
      reason: 'another step slipped between the guard and the upload',
    );
  });

  test('secrets only ever reach the shell as environment variables', () {
    // `run:` lines that interpolate a secret bake it into the command line,
    // where `set -x`, an error message or a crash report can print it.
    for (final line in text.split('\n')) {
      final trimmed = line.trimLeft();
      if (!trimmed.startsWith('run:') && !trimmed.startsWith('- run:')) continue;
      expect(line, isNot(contains(r'${{ secrets.')), reason: 'secret on a run line: $line');
    }
    // The whole file, for the two shapes that leak one on purpose.
    expect(text, isNot(contains(r'echo "$ASC_PRIVATE_KEY')));
    expect(text, isNot(contains('base64 ~/private_keys')));
    expect(text, isNot(contains('set -x')));
  });

  test('the key material is removed however the run ends', () {
    final cleanup = text.indexOf('Remove the key material');
    expect(cleanup, greaterThan(0), reason: 'nothing cleans up the signing identity');
    final step = text.substring(cleanup);
    expect(step, contains('if: always()'), reason: 'a cancelled run leaves the key behind');
    expect(step, contains('rm -rf ~/private_keys'));
    expect(step, contains('delete-keychain'));
  });

  test('it refuses a server address the app could not use', () {
    // iOS blocks plain HTTP, so an http:// build installs and never connects —
    // a failure that looks like a broken app rather than a wrong input.
    expect(text, contains('api_url must start with https://'));
  });

  test('the build is the App Store edition and carries a build number', () {
    final index = text.indexOf('flutter build ios --config-only');
    expect(index, greaterThan(0));
    final command = text.substring(index, index + 300);
    expect(command, contains('PRIVIO_EDITION=appstore'));
    expect(command, contains('--build-number='));
    expect(
      command,
      contains('PRIVIO_API_URL'),
      reason: 'without it the build talks to localhost and is useless on a phone',
    );
  });

  test('push is entitled, and the release build uses production APNs', () {
    // `Info.plist` asking for the remote-notification background mode is half
    // of it; without the entitlement the token request fails on the device.
    final entitlements = File('${root.path}/app/ios/Runner/Runner.entitlements');
    expect(entitlements.existsSync(), isTrue, reason: 'no entitlements file');
    expect(entitlements.readAsStringSync(), contains('aps-environment'));

    final project =
        File('${root.path}/app/ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    expect(
      'CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;'.allMatches(project).length,
      3,
      reason: 'all three Runner configurations have to point at it',
    );
    expect('APS_ENVIRONMENT = production;'.allMatches(project).length, 1);
    expect('APS_ENVIRONMENT = development;'.allMatches(project).length, 2);
  });
}
