import 'package:flutter/material.dart';

import 'core/app_state.dart';
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
        home: const _StageRouter(),
      ),
    );
  }
}

class _StageRouter extends StatelessWidget {
  const _StageRouter();

  @override
  Widget build(BuildContext context) {
    final state = PrivioScope.of(context);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: switch (state.stage) {
        AppStage.splash || AppStage.initialising => const SplashScreen(),
        AppStage.welcome => WelcomeScreen(
            // Registration is a V1 milestone still in flight; until it lands,
            // Get Started drops into the app so the shell can be reviewed.
            onGetStarted: () => state.completeOnboarding('privio_user'),
            onImportBackup: () => state.completeOnboarding('privio_user'),
          ),
        AppStage.locked => const PinScreen(),
        AppStage.ready => const NavShell(),
      },
    );
  }
}
