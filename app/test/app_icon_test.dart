import 'package:flutter_test/flutter_test.dart';
import 'package:privio/core/app_icon.dart';
import 'package:privio/core/app_icon_controller.dart';
import 'package:privio/core/failure.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/disguise/launcher_disguise.dart';
import 'package:privio/theme/accent.dart';

/// A launcher that can be told what to show and what to refuse.
///
/// [showing] is the home screen: the controller writes to it through [show]
/// and reads it back through [current], so a test can put the two out of step
/// the way a failed change or a restored backup does.
class FakeLauncher implements LauncherDisguise {
  FakeLauncher({
    this.capable = const LauncherCapability(icon: true, name: false),
    this.refuses,
    this.showing = const LauncherEntry.icon(AppIconColour.green),
  });

  final LauncherCapability capable;

  /// When set, [show] throws it — the device that will not swap its icon.
  final String? refuses;

  LauncherEntry? showing;
  final List<LauncherEntry> applied = [];

  @override
  Future<LauncherCapability> capability() async => capable;

  @override
  Future<void> show(LauncherEntry entry) async {
    if (refuses != null) throw LauncherDisguiseException(refuses!);
    applied.add(entry);
    showing = entry;
  }

  @override
  Future<LauncherEntry?> current() async => showing;
}

void main() {
  late InMemorySecureStore store;
  late FakeLauncher launcher;

  Future<AppIconController> ready(FakeLauncher fake) async {
    final controller = AppIconController(store, fake)..addListener(() {});
    await controller.reconcile();
    return controller;
  }

  setUp(() {
    store = InMemorySecureStore();
    launcher = FakeLauncher();
  });

  group('picking a colour', () {
    test('asks the platform and then remembers what it agreed to', () async {
      final icon = await ready(launcher);

      await icon.choose(AppIconColour.purple);

      expect(launcher.applied.single, const LauncherEntry.icon(AppIconColour.purple));
      expect(icon.colour, AppIconColour.purple);
      expect(await store.readAppIcon(), 'purple');
      expect(icon.failure, isNull);
    });

    test('a refusal changes nothing, and says why', () async {
      // The order that matters: nothing is written before the platform agrees,
      // so a tick never appears under an icon the phone did not adopt.
      final refusing = FakeLauncher(refuses: 'The launcher refused.');
      final icon = await ready(refusing);

      await icon.choose(AppIconColour.pink);

      expect(icon.colour, AppIconColour.green, reason: 'unchanged');
      expect(await store.readAppIcon(), isNull, reason: 'nothing was stored');
      expect(icon.failure?.detail, 'The launcher refused.');
    });

    test('a platform that cannot is told apart from one that would not', () async {
      final unsupported = FakeLauncher(
        capable: const LauncherCapability(icon: false, name: false),
      );
      final icon = await ready(unsupported);
      expect(icon.supported, isFalse);

      await icon.choose(AppIconColour.blue);

      expect(unsupported.applied, isEmpty, reason: 'never asked');
      expect(icon.failure?.kind, FailureKind.appIconUnsupported);
    });

    test('restoring the default goes back to the delivered artwork', () async {
      final icon = await ready(launcher);
      await icon.choose(AppIconColour.orange);

      await icon.reset();

      expect(icon.colour, AppIconColour.green);
      expect(launcher.showing, const LauncherEntry.icon(AppIconColour.green));
    });

    test('taking the accent colour is a lookup, not a second table', () async {
      final icon = await ready(launcher);

      await icon.matchAccent(AppAccent.teal);

      expect(icon.colour, AppIconColour.teal);
      expect(AppIconColour.forAccent(AppAccent.yellow), AppIconColour.yellow);
    });
  });

  group('the stored value and the home screen', () {
    test('a stored choice survives a restart', () async {
      final first = await ready(launcher);
      await first.choose(AppIconColour.red);

      // The relaunch: a new controller over the same store and the same phone.
      final second = await ready(FakeLauncher(showing: launcher.showing));

      expect(second.colour, AppIconColour.red);
    });

    test('the launcher wins when the two disagree', () async {
      // What a failed change or a restored backup leaves behind: the app
      // remembers pink and the home screen is wearing green.
      await store.writeAppIcon('pink');
      final icon = await ready(FakeLauncher());

      expect(
        icon.colour,
        AppIconColour.green,
        reason: 'the home screen is the truth, the store is only a memory',
      );
      expect(await store.readAppIcon(), 'green', reason: 'and the memory is corrected');
    });

    test('a launcher wearing the disguise does not overwrite the colour', () async {
      await store.writeAppIcon('blue');
      final disguised = FakeLauncher(showing: const LauncherEntry.calculator());

      final icon = await ready(disguised);

      expect(
        icon.colour,
        AppIconColour.blue,
        reason: 'the calculator is not a colour, and hides one rather than replacing it',
      );
    });
  });

  group('the disguise owns the home screen while it is on', () {
    test('picking a colour under it is refused, with a reason', () async {
      final icon = await ready(launcher);

      await icon.choose(AppIconColour.yellow, disguised: true);

      expect(launcher.applied, isEmpty, reason: 'the calculator was left alone');
      expect(icon.failure?.kind, FailureKind.appIconHiddenByDisguise);
      expect(icon.colour, AppIconColour.green);
    });
  });

  group('the names line up with the accent menu', () {
    test('every icon colour has an accent of the same name, and back', () {
      // What makes "use the current accent colour" a lookup rather than a map
      // somebody has to keep in step.
      for (final colour in AppIconColour.values) {
        expect(AppAccent.forCode(colour.code), isNotNull, reason: colour.code);
        expect(colour.accent.code, colour.code);
      }
      for (final accent in AppAccent.values) {
        expect(AppIconColour.forCode(accent.code), isNotNull, reason: accent.code);
      }
    });

    test('a name this build has never heard of is not a crash', () {
      expect(AppIconColour.forCode('chartreuse'), isNull);
      expect(LauncherEntry.forWireName('chartreuse'), isNull);
      expect(LauncherEntry.forWireName(null), isNull);
    });

    test('the wire name for the disguise is not a colour', () {
      expect(const LauncherEntry.calculator().wireName, 'calculator');
      expect(LauncherEntry.forWireName('calculator')?.disguised, isTrue);
      expect(const LauncherEntry.icon(AppIconColour.pink).wireName, 'pink');
    });
  });

  group('the artwork styles', () {
    test('every style has its own wire name and its own thumbnail', () {
      final codes = AppIconStyle.values.map((s) => s.code).toSet();
      expect(codes.length, AppIconStyle.values.length, reason: 'two styles share a name');
      // A style code that collided with a colour would be a style the launcher
      // reads back as a colour, and the tick would move to the wrong grid.
      for (final colour in AppIconColour.values) {
        expect(codes.contains(colour.code), isFalse, reason: colour.code);
      }
      expect(codes.contains('calculator'), isFalse);

      final previews = AppIconStyle.values.map((s) => s.preview).toSet();
      expect(previews.length, AppIconStyle.values.length);
      for (final style in AppIconStyle.values) {
        expect(style.preview, startsWith('assets/launcher_styles/'));
      }
    });

    test('a style round-trips through the wire name', () {
      for (final style in AppIconStyle.values) {
        final entry = LauncherEntry.styled(style);
        expect(entry.wireName, style.code);
        expect(LauncherEntry.forWireName(style.code)?.style, style);
        expect(entry.disguised, isFalse);
      }
    });

    test('choosing one reaches the launcher and is stored', () async {
      final controller = await ready(launcher);
      await controller.chooseStyle(AppIconStyle.neon);

      expect(launcher.applied.single.wireName, 'neon');
      expect(controller.style, AppIconStyle.neon);
      expect(await store.readAppIcon(), 'neon');
    });

    test('and a colour afterwards clears it', () async {
      // One home screen, one icon. A style left behind under a chosen colour
      // would put a tick in both grids.
      final controller = await ready(launcher);
      await controller.chooseStyle(AppIconStyle.camo);
      await controller.choose(AppIconColour.pink);

      expect(controller.style, isNull);
      expect(controller.colour, AppIconColour.pink);
      expect(await store.readAppIcon(), 'pink');
    });

    test('a stored style survives a restart', () async {
      final first = await ready(launcher);
      await first.chooseStyle(AppIconStyle.camoShield);

      // A fresh controller over the same store and the same launcher.
      final second = await ready(launcher);
      expect(second.style, AppIconStyle.camoShield);
    });

    test('the launcher wins a disagreement about a style', () async {
      final controller = await ready(launcher);
      await controller.chooseStyle(AppIconStyle.neon);

      // What a failed change or a restored backup looks like: the home screen
      // is wearing something else.
      launcher.showing = const LauncherEntry.styled(AppIconStyle.neonMesh);
      await controller.reconcile();

      expect(controller.style, AppIconStyle.neonMesh);
      expect(await store.readAppIcon(), 'neon_mesh');
    });

    test('and a launcher back on a colour clears the style', () async {
      final controller = await ready(launcher);
      await controller.chooseStyle(AppIconStyle.neon);

      launcher.showing = const LauncherEntry.icon(AppIconColour.teal);
      await controller.reconcile();

      expect(controller.style, isNull);
      expect(controller.colour, AppIconColour.teal);
    });

    test('the disguise still wins, and nothing is stored', () async {
      final controller = await ready(launcher);
      await controller.chooseStyle(AppIconStyle.neon, disguised: true);

      expect(launcher.applied, isEmpty, reason: 'the calculator was replaced');
      expect(controller.style, isNull);
      expect(controller.failure?.kind, FailureKind.appIconHiddenByDisguise);
    });

    test('a platform that cannot change the icon refuses a style too', () async {
      final controller = await ready(
        FakeLauncher(capable: const LauncherCapability(icon: false, name: false)),
      );
      await controller.chooseStyle(AppIconStyle.camo);

      expect(controller.style, isNull);
      expect(controller.failure?.kind, FailureKind.appIconUnsupported);
    });

    test('a refusal from the device leaves the style alone', () async {
      final refusing = FakeLauncher(refuses: 'This build will not swap its icon.');
      final controller = await ready(refusing);
      await controller.chooseStyle(AppIconStyle.neon);

      expect(controller.style, isNull);
      expect(await store.readAppIcon(), isNull);
      expect(controller.failure, isNotNull);
    });

    test('restoring the original clears a style', () async {
      final controller = await ready(launcher);
      await controller.chooseStyle(AppIconStyle.neonMesh);
      await controller.reset();

      expect(controller.style, isNull);
      expect(controller.colour, AppIconColour.fallback);
      expect(launcher.applied.last.wireName, 'green');
    });
  });
}
