import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/app_state.dart';
import 'services/incoming_links.dart';
import 'services/push_wake.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Month names, weekday names and the order of day/month/year for every
  // language the app speaks. Without this, `DateFormat` throws the moment a
  // date is drawn in anything but the default locale — which is most of them.
  await initializeDateFormatting();

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
  // Channel links arriving from outside the app are wired in here for the same
  // reason push is: the platform belongs at the composition root, and every
  // test gets an app that no link ever arrives at.
  runApp(
    PrivioApp(
      state: AppState(
        pushWake: PushWakeListener(),
        links: PlatformIncomingLinks(),
      ),
    ),
  );
}
