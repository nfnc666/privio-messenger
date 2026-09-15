import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:privio/core/api_client.dart';
import 'package:privio/core/app_state.dart';
import 'package:privio/core/edition.dart';
import 'package:privio/core/secure_store.dart';
import 'package:privio/l10n/app_localizations.dart';
import 'package:privio/screens/notifications_screen.dart';
import 'package:privio/services/wake_up.dart';

class NotificationState extends AppState {
  NotificationState(this.controller) : super(store: InMemorySecureStore());
  final WakeUpController controller;
  @override
  WakeUpController get wakeUp => controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const unified = MethodChannel('app.privio/unifiedpush');
  const vendor = MethodChannel('app.privio/push');
  const permissions = MethodChannel('app.privio/notifications');
  late List<String> unifiedCalls;
  late List<String> vendorCalls;
  late List<String> permissionCalls;
  late List<Map<String, dynamic>> requests;
  late WakeUpController controller;
  var opensSettings = true;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    unifiedCalls = [];
    vendorCalls = [];
    permissionCalls = [];
    requests = [];
    opensSettings = true;
    messenger.setMockMethodCallHandler(unified, (call) async {
      unifiedCalls.add(call.method);
      if (call.method == 'isAvailable') return true;
      if (call.method == 'register') return 'https://ntfy.example/endpoint';
      return null;
    });
    messenger.setMockMethodCallHandler(vendor, (call) async {
      vendorCalls.add(call.method);
      if (call.method == 'isAvailable') return true;
      if (call.method == 'token') return 'apns-token';
      return null;
    });
    messenger.setMockMethodCallHandler(permissions, (call) async {
      permissionCalls.add(call.method);
      if (call.method == 'openSettings') return opensSettings;
      return 'granted';
    });
  });

  WakeUpController makeController() => WakeUpController(
    PrivioApiClient(
      baseUrl: Uri.parse('https://api.test'),
      client: MockClient((request) async {
        requests.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response('{}', 200, headers: {'content-type': 'application/json'});
      }),
    )..useToken('test'),
    // Even an iOS debug build with the default Libre edition must use APNs.
    edition: PrivioEdition.parse('libre'),
  );

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    for (final channel in [unified, vendor, permissions]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });

  test('iOS never queries UnifiedPush and still registers APNs', () async {
    controller = makeController();
    addTearDown(controller.dispose);
    expect(controller.provider, 'apns');
    await controller.refresh();
    expect(await controller.useUnifiedPush(), isFalse);
    const distributor = ChannelPushDistributor();
    expect(await distributor.isAvailable(), isFalse);
    expect(await distributor.register(), isNull);
    await distributor.unregister();
    await controller.ensureRegistered();
    expect(controller.method, WakeUpMethod.apns);
    expect(requests.single, {'provider': 'apns', 'token': 'apns-token'});
    await controller.handleTokenChanged('renewed');
    expect(requests.last, {'provider': 'apns', 'token': 'renewed'});
    await controller.signOutOfPush();
    expect(vendorCalls, containsAll(['token', 'delete']));
    expect(unifiedCalls, isEmpty);
  });

  for (final locale in AppText.supportedLocales) {
    testWidgets('iOS notifications and settings button in ${locale.languageCode}', (tester) async {
      try {
      controller = makeController();
      final state = NotificationState(controller);
      addTearDown(controller.dispose);
      addTearDown(state.dispose);
      await tester.pumpWidget(PrivioScope(
        notifier: state,
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: AppText.localizationsDelegates,
          supportedLocales: AppText.supportedLocales,
          home: const NotificationsScreen(),
        ),
      ));
      await tester.pumpAndSettle();
      final text = AppText.of(tester.element(find.byType(NotificationsScreen)));
      expect(find.text('UnifiedPush'), findsNothing);
      expect(find.byType(Switch), findsNothing);
      expect(find.byIcon(Icons.bolt_outlined), findsNothing);
      expect(find.text(text.notificationsDelivery), findsNothing);
      expect(find.text(text.notificationsPushNote), findsNothing);
      expect(find.text(text.notificationsPhoneNote), findsNothing);
      expect(find.text(text.notificationsIphoneNote), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('open-iphone-settings')));
      await tester.pumpAndSettle();
      expect(permissionCalls.where((call) => call == 'openSettings'), hasLength(1));
      opensSettings = false;
      await tester.tap(find.byKey(const ValueKey('open-iphone-settings')));
      await tester.pumpAndSettle();
      expect(find.text(text.notificationsSettingsFailed), findsOneWidget);
      expect(unifiedCalls, isEmpty);
      expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  testWidgets('Android retains UnifiedPush UI and registration', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
    controller = makeController();
    final state = NotificationState(controller);
    addTearDown(controller.dispose);
    addTearDown(state.dispose);
    await tester.pumpWidget(PrivioScope(
      notifier: state,
      child: const MaterialApp(
        localizationsDelegates: AppText.localizationsDelegates,
        supportedLocales: AppText.supportedLocales,
        home: NotificationsScreen(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('UnifiedPush'), findsOneWidget);
    expect(find.byKey(const ValueKey('open-iphone-settings')), findsNothing);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(controller.method, WakeUpMethod.unifiedPush);
    expect(unifiedCalls, containsAll(['isAvailable', 'register']));
    expect(requests.single['provider'], 'unifiedpush');
    expect(vendorCalls, isEmpty);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
