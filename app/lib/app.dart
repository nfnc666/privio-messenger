import 'package:flutter/material.dart';

import 'core/app_state.dart';
import 'screens/activation_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/call_screen.dart';
import 'screens/nav_shell.dart';
import 'screens/pin_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/welcome_screen.dart';
import 'theme/privio_theme.dart';

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

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    // Leaving the app re-arms the lock, so returning to it asks for the PIN.
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
            child: _CallOverlay(child: child ?? const SizedBox.shrink()),
          );
        },
        home: const _StageRouter(),
      ),
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
            // Restoring starts by signing back into the account: a backup holds
            // history, not an identity, so the device needs one of its own
            // before there is anywhere to put the history. The backup screen is
            // where the recovery key goes in, and this says so on the way.
            onImportBackup: () => _openAuth(context, AuthMode.signIn, restoring: true),
          ),
        AppStage.locked => const PinScreen(),
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
