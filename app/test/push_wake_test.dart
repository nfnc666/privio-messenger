import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/services/push_wake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> tokens;
  late int fetches;
  late PushWakeListener listener;

  setUp(() {
    tokens = [];
    fetches = 0;
    listener = PushWakeListener()
      ..listen(
        onWake: () async => fetches += 1,
        onTokenChanged: (token) async => tokens.add(token),
      );
  });

  tearDown(() => listener.stop());

  test('a wake-up asks for a fetch and carries nothing else', () async {
    // The whole payload is the fact that it happened. If this ever needed an
    // argument, something would be travelling through a push service.
    await listener.handle(const MethodCall('wake'));
    expect(fetches, 1);
    expect(tokens, isEmpty);
  });

  test('two wake-ups for the same message cost a fetch, not a message', () async {
    // Deduplication is the fetch's job — it drops an envelope it has already
    // opened — so the listener does not try to be clever about it. What matters
    // is that a second wake-up is harmless.
    await listener.handle(const MethodCall('wake'));
    await listener.handle(const MethodCall('wake'));
    expect(fetches, 2, reason: 'both are honoured; the watermark sorts it out');
  });

  test('a reissued token is passed on so the server stops using the old one', () async {
    await listener.handle(const MethodCall('tokenChanged', 'https://ntfy.sh/UPnew'));
    expect(tokens, ['https://ntfy.sh/UPnew']);
    expect(fetches, 0);
  });

  test('an empty or absent token is not registered', () async {
    await listener.handle(const MethodCall('tokenChanged', ''));
    await listener.handle(const MethodCall('tokenChanged'));
    await listener.handle(const MethodCall('tokenChanged', 42));
    expect(tokens, isEmpty, reason: 'a blank address would unregister a working device');
  });

  test('a method this build does not know is ignored, not thrown', () async {
    // The platform half can be newer than the Dart half — a store update lands
    // as one binary, but a user can be running an older one for a while.
    await listener.handle(const MethodCall('somethingNewer'));
    expect(fetches, 0);
    expect(tokens, isEmpty);
  });

  test('after stopping, nothing reaches a signed-out app', () async {
    // Sign-out unhooks this. A wake-up that arrived a moment later must not
    // send a fetch for an account that is no longer on this device.
    listener.stop();
    await listener.handle(const MethodCall('wake'));
    await listener.handle(const MethodCall('tokenChanged', 'https://ntfy.sh/UPnew'));
    expect(fetches, 0);
    expect(tokens, isEmpty);
  });
}
