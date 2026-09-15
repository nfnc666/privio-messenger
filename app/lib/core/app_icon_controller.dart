import 'package:flutter/foundation.dart';

import '../disguise/launcher_disguise.dart';
import '../theme/accent.dart';
import 'app_icon.dart';
import 'failure.dart';
import 'secure_store.dart';

/// Which icon the home screen shows, and whether the platform would say so.
///
/// **Per installation, not per account.** A home-screen icon belongs to the
/// phone: there is one of it, everyone who unlocks the device sees it, and it
/// does not change when somebody signs in as somebody else. That is the
/// opposite rule from the accent colour, deliberately — the accent is what
/// *this account* sees inside the app, and the icon is what *this device*
/// shows outside it.
///
/// **Stored only after the platform agreed.** The value here is what the home
/// screen is showing, not what was asked for. A change that failed leaves both
/// alone, and [reconcile] re-reads the platform whenever the settings screen
/// opens: a stored value is this app's memory and the launcher is the truth,
/// and the two can part company — a failed change, a restored backup, a
/// manufacturer build that takes the call and does nothing.
class AppIconController extends ChangeNotifier {
  AppIconController(this._store, this._launcher);

  final SecureStore _store;
  final LauncherDisguise _launcher;

  AppIconColour _colour = AppIconColour.fallback;
  bool _supported = false;
  bool _busy = false;
  Failure? _failure;

  /// What the home screen is showing, as far as anything here knows.
  AppIconColour get colour => _colour;

  /// Whether this platform can change it at all. False on the web and on any
  /// build with nothing on the other end of the channel.
  bool get supported => _supported;

  /// True while a change is in flight. The launcher can take a moment.
  bool get busy => _busy;

  /// Why the last change did not happen, as a case for the screen to say.
  Failure? get failure => _failure;

  /// Reads the stored choice and then checks it against the platform.
  ///
  /// Called at start-up and again whenever the settings screen opens. The
  /// stored value is used first so the screen has something to draw, and then
  /// corrected if the launcher disagrees — which is the direction that matters:
  /// showing a tick under a colour the home screen is not wearing is the one
  /// mistake this setting cannot afford.
  Future<void> reconcile() async {
    final stored = AppIconColour.forCode(await _store.readAppIcon());
    if (stored != null && stored != _colour) {
      _colour = stored;
      notifyListeners();
    }

    final capability = await _launcher.capability();
    final actual = await _launcher.current();
    var changed = capability.icon != _supported;
    _supported = capability.icon;

    // A disguised launcher is not a colour, and it is not this setting's to
    // undo: the icon stays stored as whatever was chosen, and the home screen
    // goes on showing the calculator until the disguise is switched off.
    if (actual != null && !actual.disguised && actual.colour != _colour) {
      _colour = actual.colour;
      await _store.writeAppIcon(actual.colour.code);
      changed = true;
    }
    if (changed) notifyListeners();
  }

  /// Puts [colour] on the home screen.
  ///
  /// Nothing is stored until the platform has confirmed. `setAlternateIconName`
  /// on iOS and the alias swap on Android can both refuse, and a setting that
  /// wrote its answer before asking would show a tick under an icon the phone
  /// never adopted.
  Future<void> choose(AppIconColour colour, {bool disguised = false}) async {
    if (_busy) return;
    _failure = null;

    if (!_supported) {
      _failure = const Failure(FailureKind.appIconUnsupported);
      notifyListeners();
      return;
    }

    // The disguise owns the home screen while it is on. Quietly replacing the
    // calculator with a coloured Privio icon would undo a security setting
    // through a cosmetic one.
    if (disguised) {
      _failure = const Failure(FailureKind.appIconHiddenByDisguise);
      notifyListeners();
      return;
    }

    _busy = true;
    notifyListeners();
    try {
      await _launcher.show(LauncherEntry.icon(colour));
      _colour = colour;
      await _store.writeAppIcon(colour.code);
    } on LauncherDisguiseException catch (refusal) {
      // The platform's own words. It knows why and this does not.
      _failure = Failure.server(refusal.message);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Takes the colour the interface is currently drawn in.
  Future<void> matchAccent(AppAccent accent, {bool disguised = false}) =>
      choose(AppIconColour.forAccent(accent), disguised: disguised);

  /// Back to the delivered artwork.
  Future<void> reset({bool disguised = false}) =>
      choose(AppIconColour.fallback, disguised: disguised);

  void clearFailure() {
    if (_failure == null) return;
    _failure = null;
    notifyListeners();
  }
}
