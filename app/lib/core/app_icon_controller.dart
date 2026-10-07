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
  AppIconStyle? _style;
  bool _supported = false;
  bool _busy = false;
  Failure? _failure;

  /// What the home screen is showing, as far as anything here knows.
  ///
  /// Meaningless while [style] is set: a style is a whole picture rather than a
  /// hue, so there is no colour it corresponds to. The screen reads [style]
  /// first and falls back to this.
  AppIconColour get colour => _colour;

  /// The artwork style the home screen is showing, or null when it is one of
  /// the colours.
  AppIconStyle? get style => _style;

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
    final code = await _store.readAppIcon();
    // A style and a colour share the one stored slot, because the home screen
    // has one icon. Styles are tried first: their codes cannot collide with a
    // colour's, and reading a style as "no colour stored" would silently put
    // the tick back under green.
    final storedStyle = AppIconStyle.forCode(code);
    if (storedStyle != null) {
      if (storedStyle != _style) {
        _style = storedStyle;
        notifyListeners();
      }
    } else {
      final stored = AppIconColour.forCode(code);
      if (stored != null && (stored != _colour || _style != null)) {
        _colour = stored;
        _style = null;
        notifyListeners();
      }
    }

    final capability = await _launcher.capability();
    final actual = await _launcher.current();
    var changed = capability.icon != _supported;
    _supported = capability.icon;

    // A disguised launcher is not a colour, and it is not this setting's to
    // undo: the icon stays stored as whatever was chosen, and the home screen
    // goes on showing the calculator until the disguise is switched off.
    if (actual != null && !actual.disguised) {
      final actualStyle = actual.style;
      if (actualStyle != null && actualStyle != _style) {
        _style = actualStyle;
        await _store.writeAppIcon(actualStyle.code);
        changed = true;
      } else if (actualStyle == null && (actual.colour != _colour || _style != null)) {
        _colour = actual.colour;
        _style = null;
        await _store.writeAppIcon(actual.colour.code);
        changed = true;
      }
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

    await _apply(LauncherEntry.icon(colour));
  }

  /// Puts one of the artwork styles on the home screen.
  ///
  /// The same rules as a colour, for the same reasons: refused on a platform
  /// that cannot, refused under an active disguise, and stored only after the
  /// platform has agreed.
  Future<void> chooseStyle(AppIconStyle style, {bool disguised = false}) async {
    if (_busy) return;
    _failure = null;

    if (!_supported) {
      _failure = const Failure(FailureKind.appIconUnsupported);
      notifyListeners();
      return;
    }
    if (disguised) {
      _failure = const Failure(FailureKind.appIconHiddenByDisguise);
      notifyListeners();
      return;
    }

    await _apply(LauncherEntry.styled(style));
  }

  /// The one place that talks to the platform and writes the result.
  ///
  /// Both pickers end up here rather than keeping a copy of the "ask, then
  /// store" rule each: two copies are two chances for one of them to store
  /// before asking.
  Future<void> _apply(LauncherEntry entry) async {
    _busy = true;
    notifyListeners();
    try {
      await _launcher.show(entry);
      _style = entry.style;
      if (entry.style == null) _colour = entry.colour;
      await _store.writeAppIcon(entry.wireName);
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
