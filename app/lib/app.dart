import 'package:flutter/material.dart';

import 'core/app_state.dart';
import 'models/channel.dart';
import 'screens/channel_feed_screen.dart';
import 'screens/activation_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/calculator_screen.dart';
import 'screens/call_screen.dart';
import 'screens/nav_shell.dart';
import 'screens/pin_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/welcome_screen.dart';
import 'theme/privio_colors.dart';
import 'theme/privio_theme.dart';
import 'widgets/privio_logo.dart';

/// The root widget: owns [AppState] and picks the screen for the current stage.
class PrivioApp extends StatefulWidget {
  const PrivioApp({super.key, this.state});

  /// Injectable for tests; production builds let the app create its own.
  final AppState? state;

  @override
  State<PrivioApp> createState() => _PrivioAppState();
}

class _PrivioAppState extends State<PrivioApp> with WidgetsBindingObserver {
  late final AppState _state = widget.state ?? AppState();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _state.initialise();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _state.dispose();
    super.dispose();
  }

  /// What the OS last said the app was doing. Held so the cover can go up the
  /// moment it stops being `resumed`.
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    setState(() => _lifecycle = lifecycleState);

    // Covering and locking are two different moments, and running them together
    // gets one of them wrong.
    //
    // `inactive` is where the screenshot happens: it is the frame the app
    // switcher photographs, and on iOS it is also a pulled-down notification
    // shade, an incoming call, a permission dialog. Content has to be off
    // screen by then — but locking there would ask for the passcode every time
    // somebody glanced at their notifications.
    //
    // `paused` is where the app has actually been left, and that is where the
    // lock is armed.
    if (lifecycleState == AppLifecycleState.paused ||
        lifecycleState == AppLifecycleState.detached) {
      _state.lock();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PrivioScope(
      notifier: _state,
      child: MaterialApp(
        title: 'Privio',
        debugShowCheckedModeBanner: false,
        theme: PrivioTheme.dark(),
        darkTheme: PrivioTheme.dark(),
        themeMode: ThemeMode.dark,
        // The one appearance setting that is real, applied where every screen
        // sees it rather than by each screen remembering to. Read through the
        // scope rather than off the field, so changing it redraws the app
        // instead of waiting for the next relaunch.
        builder: (context, child) {
          final scale = PrivioScope.of(context).textScale;
          return MediaQuery.withClampedTextScaling(
            minScaleFactor: scale,
            maxScaleFactor: scale,
            // The cover goes outermost: a call screen is content too, and the
            // app switcher must not photograph who is on it.
            child: PrivacyCover(
              hidden: _lifecycle != AppLifecycleState.resumed,
              // Inside the cover and above the navigator: the opener needs a
              // navigator to push onto, and it must not be photographed by the
              // app switcher any more than anything else is.
              child: _DeepLinkOpener(
                child: _CallOverlay(child: child ?? const SizedBox.shrink()),
              ),
            ),
          );
        },
        home: const _StageRouter(),
      ),
    );
  }
}

/// Opens whatever a link named, once the app is in a state to open it.
///
/// Sits above the stage router so it survives the screen underneath changing —
/// which it does exactly when this matters, as somebody finishes signing in.
///
/// It waits for [AppStage.ready] and nothing else. A link that arrives at the
/// lock screen waits for the passcode; one that arrives on a device with no
/// account waits through signing up and the activation step. Whoever tapped the
/// invitation ends up looking at it, whenever that turns out to be.
///
/// **It never joins.** It fetches what the link names and pushes the channel
/// screen, which shows a Join button to somebody who is not a member and the
/// feed to somebody who is.
class _DeepLinkOpener extends StatefulWidget {
  const _DeepLinkOpener({required this.child});

  final Widget child;

  @override
  State<_DeepLinkOpener> createState() => _DeepLinkOpenerState();
}

class _DeepLinkOpenerState extends State<_DeepLinkOpener> {
  /// True while a link is being resolved, so a rebuild does not start a second
  /// fetch of the same one.
  bool _opening = false;

  Future<void> _open(AppState state, ChannelLinkTarget target) async {
    if (_opening) return;
    _opening = true;
    final controller = state.channels;
    final channel = await controller.preview(target);
    if (!mounted) {
      _opening = false;
      return;
    }

    // Taken only now. Cleared on read, a target would be lost if the fetch
    // failed, and the person would be left with nothing and no explanation.
    state.deepLinks.taken();
    _opening = false;

    if (channel == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            controller.error ??
                'That link does not point at a channel any more. Ask whoever '
                    'sent it for a new one.',
          ),
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ChannelFeedScreen(channel: channel)),
    );
  }

  void _reportUnreadable(AppState state) {
    state.deepLinks.taken();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('That does not look like a Privio channel link.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = PrivioScope.of(context);

    return ListenableBuilder(
      listenable: state.deepLinks,
      builder: (context, child) {
        final target = state.deepLinks.pending;
        // Only once there is somewhere to put it. Everything else waits.
        if (state.stage == AppStage.ready) {
          if (target != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _open(state, target));
          } else if (state.deepLinks.unreadable) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _reportUnreadable(state));
          }
        }
        return child!;
      },
      child: widget.child,
    );
  }
}

class _StageRouter extends StatelessWidget {
  const _StageRouter();

  void _openAuth(BuildContext context, AuthMode mode, {bool restoring = false}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AuthScreen(mode: mode, restoring: restoring),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = PrivioScope.of(context);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: switch (state.stage) {
        AppStage.splash || AppStage.initialising => const SplashScreen(),
        // Before the account, not after: a key is what the hosted service is
        // paid for, and asking once the user is already inside would be asking
        // them to pay for something they were let into for free.
        AppStage.welcome => WelcomeScreen(
            onGetStarted: () => _openAuth(context, AuthMode.signUp),
            onSignIn: () => _openAuth(context, AuthMode.signIn),
            // Restoring starts by signing back into the account: a backup holds
            // history, not an identity, so the device needs one of its own
            // before there is anywhere to put the history. The backup screen is
            // where the recovery key goes in, and this says so on the way.
            onImportBackup: () => _openAuth(context, AuthMode.signIn, restoring: true),
          ),
        // A disguise replaces the lock screen; it does not sit in front of
        // it. Two screens to get past would be two screens to ask about.
        AppStage.locked => state.disguise == null
            ? const PinScreen()
            : CalculatorScreen(skin: state.disguise!),
        AppStage.activation => const ActivationScreen(),
        AppStage.ready => const NavShell(),
      },
    );
  }
}

/// A live call, over everything.
///
/// It goes in the [MaterialApp] builder rather than in the stage router, which
/// is where it was first put and where it did not work: the router is the
/// `home` route, so a call screen swapped in there rendered *underneath* any
/// screen the user had pushed. Someone starting a call from a chat watched the
/// callee's phone ring and saw their own chat, with no way to hang up. Here it
/// is above the navigator, so it covers whatever is open.
///
/// It is still gated on the app being unlocked: the lock screen is the whole
/// point of the lock screen. Until Privio can wake a closed app for a call, an
/// incoming one can only arrive while it is open anyway.
class _CallOverlay extends StatelessWidget {
  const _CallOverlay({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final state = PrivioScope.of(context);
    if (state.stage != AppStage.ready) return child;

    return ListenableBuilder(
      listenable: state.services.calls,
      builder: (context, under) {
        final call = state.services.calls.current;
        if (call == null || !call.isLive) return under!;
        return Stack(
          children: [under!, Positioned.fill(child: CallScreen(call: call))],
        );
      },
      child: child,
    );
  }
}

/// What the app switcher gets to photograph.
///
/// A locked app is not a private one if the thumbnail beside it still shows the
/// conversation that was open: the OS takes that picture on the way out, before
/// any lock is armed, and it survives in the switcher for anyone who picks the
/// phone up. So the content is covered the moment the app stops being the thing
/// on screen, whatever it was showing and however deep in the navigator it was.
///
/// It wears the disguise when there is one. A device set to open as a
/// calculator, showing a Privio splash in the app switcher, has told the person
/// holding it exactly what the disguise was hiding.
class PrivacyCover extends StatelessWidget {
  const PrivacyCover({required this.hidden, required this.child, super.key});

  /// Names the covering surface itself, which is the thing worth finding: this
  /// widget is always in the tree, and only sometimes covering anything.
  static const Key coverKey = ValueKey('privacy-cover');

  final bool hidden;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!hidden) return child;
    final state = PrivioScope.of(context);
    final skin = state.disguise;
    return Stack(
      children: [
        // Kept in the tree, not thrown away: this is a screenshot being taken,
        // not a screen being left, and rebuilding the whole app on the way back
        // would lose the scroll position and every open composer.
        child,
        Positioned.fill(
          key: coverKey,
          child: skin == null ? const _NeutralCover() : CalculatorScreen(skin: skin),
        ),
      ],
    );
  }
}

/// The cover for a device with no disguise: the app's own mark on its own
/// background, and nothing that was on screen a moment ago.
class _NeutralCover extends StatelessWidget {
  const _NeutralCover();

  @override
  Widget build(BuildContext context) => const ColoredBox(
        color: PrivioColors.background,
        child: Center(child: PrivioMark(size: 72)),
      );
}
