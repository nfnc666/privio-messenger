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
  final state = AppState(
    pushWake: PushWakeListener(),
    links: PlatformIncomingLinks(),
  );

  // The one thing read before the first frame.
  //
  // The splash is drawn in the account's accent — the mark, the rain behind it,
  // the progress bar — so reading the stored colour after the app is on screen
  // shows brand green for a frame and then the real choice. `initialise()`
  // loads it too, but that runs with the splash already visible.
  //
  // Capped rather than simply awaited. This is a local keystore read with no
  // network behind it, but it is still a platform channel, and an app that
  // could be held on a black screen by one is an app one wedged channel can
  // stop from starting. Past the cap the launch goes ahead in green and
  // `initialise()` corrects it, which is the old behaviour rather than a new
  // failure.
  await state.accent.preload().timeout(
        const Duration(milliseconds: 500),
        onTimeout: () {},
      );

  runApp(PrivioApp(state: state));
}
