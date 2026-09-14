import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:privio/core/app_icon.dart';

/// The four places an icon colour is named — Dart, the Android manifest, the
/// Kotlin that reads it, the Swift that reads it, and the asset catalogues —
/// have to agree, and nothing else in the suite would notice if they stopped.
///
/// A typo here does not fail a build on this machine: there is no Android SDK
/// and no Xcode in it, so the native sources are never compiled. It fails on a
/// phone, once, as an icon that does not change. This reads the files instead.
void main() {
  String read(String path) => File(path).readAsStringSync();

  const densities = ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi'];

  group('Android', () {
    final manifest = read('android/app/src/main/AndroidManifest.xml');
    final kotlin = read('android/app/src/main/kotlin/app/privio/privio/MainActivity.kt');

    test('every entry Kotlin can be asked for exists in the manifest', () {
      final table = kotlin.substring(kotlin.indexOf('val ALIASES'));
      final named = RegExp(r'"app\.privio\.privio\.(\w+)"')
          .allMatches(table)
          .map((m) => m.group(1)!)
          .toSet()
        // The two that come from constants rather than literals in the table.
        ..addAll(['DefaultLauncher', 'CalculatorLauncher']);
      final declared = RegExp(r'android:name="\.(\w+)"[\s\S]{0,60}?targetActivity')
          .allMatches(manifest)
          .map((m) => m.group(1)!)
          .toSet();

      expect(named, declared, reason: 'an alias named on one side and not the other');
    });

    test('the channel speaks every colour Dart has, and no others', () {
      final table = kotlin.substring(kotlin.indexOf('val ALIASES'));
      final entries = RegExp(r'"(\w+)" to ').allMatches(table).map((m) => m.group(1)!).toSet();

      expect(
        entries,
        {for (final colour in AppIconColour.values) colour.code, 'calculator'},
        reason: 'the wire names have to match AppIconColour plus the disguise',
      );
    });

    test('every icon an alias points at exists at every density', () {
      final icons = RegExp(r'android:icon="@mipmap/(\w+)"')
          .allMatches(manifest)
          .map((m) => m.group(1)!)
          .toSet();
      expect(icons, hasLength(AppIconColour.values.length + 1), reason: 'colours + calculator');

      for (final icon in icons) {
        for (final density in densities) {
          expect(
            File('android/app/src/main/res/mipmap-$density/$icon.png').existsSync(),
            isTrue,
            reason: '$icon missing at $density',
          );
        }
      }
    });

    test('every adaptive icon points at a foreground that is there', () {
      final dir = Directory('android/app/src/main/res/mipmap-anydpi-v26');
      final files = dir.listSync().whereType<File>().toList();
      expect(files, hasLength(AppIconColour.values.length), reason: 'one per colour');

      for (final file in files) {
        final foreground = RegExp(r'foreground android:drawable="@mipmap/(\w+)"')
            .firstMatch(file.readAsStringSync())
            ?.group(1);
        expect(foreground, isNotNull, reason: '${file.path} names no foreground');
        for (final density in densities) {
          expect(
            File('android/app/src/main/res/mipmap-$density/$foreground.png').existsSync(),
            isTrue,
            reason: '$foreground missing at $density',
          );
        }
      }
    });
  });

  group('iOS', () {
    test('every alternate the build settings list is in the catalogue', () {
      final project = read('ios/Runner.xcodeproj/project.pbxproj');
      final listed = RegExp(r'"(AppIcon-\w+)"')
          .allMatches(project)
          .map((m) => m.group(1)!)
          .toSet();
      final onDisk = Directory('ios/Runner/Assets.xcassets')
          .listSync()
          .whereType<Directory>()
          .map((d) => d.path.split('/').last)
          .where((n) => n.endsWith('.appiconset'))
          .map((n) => n.replaceAll('.appiconset', ''))
          .toSet();

      expect(
        listed,
        {
          for (final colour in AppIconColour.values)
            if (colour != AppIconColour.fallback) 'AppIcon-${colour.code}',
        },
        reason: 'green is the primary icon and has no alternate of its own',
      );
      expect(onDisk.difference(listed), {'AppIcon'});
    });

    test('the compiler is told to include them', () {
      final project = read('ios/Runner.xcodeproj/project.pbxproj');
      // Three Runner configurations: Debug, Release, Profile. A setting on two
      // of them is a build where one configuration quietly has no alternates.
      expect(
        'ASSETCATALOG_COMPILER_ALTERNATE_APP_ICON_NAMES'.allMatchesIn(project),
        3,
      );
      expect('ASSETCATALOG_COMPILER_INCLUDE_ALL_APP_ICON_ASSETS = YES'.allMatchesIn(project), 3);
      expect(
        'ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;'.allMatchesIn(project),
        3,
        reason: 'the primary icon, and therefore the store icon, is unchanged',
      );
    });

    test('every listed set holds every image its Contents.json promises', () {
      for (final colour in AppIconColour.values) {
        if (colour == AppIconColour.fallback) continue;
        final dir = 'ios/Runner/Assets.xcassets/AppIcon-${colour.code}.appiconset';
        final contents = jsonDecode(read('$dir/Contents.json')) as Map<String, dynamic>;
        for (final image in contents['images'] as List<dynamic>) {
          final filename = (image as Map<String, dynamic>)['filename'] as String?;
          if (filename == null) continue;
          expect(File('$dir/$filename').existsSync(), isTrue, reason: '$dir/$filename');
        }
      }
    });

    test('the Swift names the same colours Dart does', () {
      final swift = read('ios/Runner/LauncherIcon.swift');
      // From the `= [` rather than the declaration: the type annotation is
      // `[String: String?]`, whose bracket would close the slice early.
      final start = swift.indexOf('= [', swift.indexOf('private static let icons'));
      final table = swift.substring(start, swift.indexOf(']', start));
      final entries =
          RegExp(r'"(\w+)":').allMatches(table).map((m) => m.group(1)!).toSet();

      expect(entries, {for (final colour in AppIconColour.values) colour.code});
    });

    test('the handler is compiled into the target', () {
      // A source file Xcode does not know about is a channel with nothing on
      // the other end, which looks exactly like an unsupported device.
      final project = read('ios/Runner.xcodeproj/project.pbxproj');
      expect('LauncherIcon.swift in Sources'.allMatchesIn(project), 2);
      expect(File('ios/Runner/LauncherIcon.swift').existsSync(), isTrue);
    });
  });
}

extension on String {
  int allMatchesIn(String haystack) => RegExp(RegExp.escape(this)).allMatches(haystack).length;
}
