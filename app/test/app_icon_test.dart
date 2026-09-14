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
}
