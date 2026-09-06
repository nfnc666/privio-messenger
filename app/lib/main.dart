import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'core/app_state.dart';
import 'services/push_wake.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Privio is portrait-only and dark-only: a rotated or light-themed system UI
  // would break the black-on-black look the brand depends on.
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.black,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // The platform's push callbacks are wired in here, at the one place that
  // knows there is a platform. `AppState` is handed the listener rather than
  // reaching for a method channel itself.
  runApp(PrivioApp(state: AppState(pushWake: PushWakeListener())));
}
