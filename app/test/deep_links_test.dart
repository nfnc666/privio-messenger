import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:privio/core/deep_links.dart';
import 'package:privio/models/channel.dart';

/// A link source a test can push through.
class FakeLinks implements IncomingLinks {
  FakeLinks({this.launchedWith});

  /// What the app was started by, if anything.
  final String? launchedWith;
  final StreamController<String> _arriving = StreamController<String>.broadcast();

  void arrive(String link) => _arriving.add(link);

  @override
  Future<String?> initial() async => launchedWith;

  @override
  Stream<String> get stream => _arriving.stream;
}

void main() {
  test('a link the app was launched by is picked up', () async {
    // The cold start is the case an implementation usually drops: the link is
    // delivered before any listener exists, so a stream subscription alone
    // misses exactly the person who tapped an invitation without Privio open.
    final links = DeepLinkController(
      source: FakeLinks(launchedWith: 'https://privio.channel/+coldstart'),
    );
    await links.start();

    expect(links.pending, isA<ChannelLinkByCode>());
    expect((links.pending! as ChannelLinkByCode).code, 'coldstart');
  });

  test('and so is one that arrives while the app is running', () async {
    final source = FakeLinks();
    final links = DeepLinkController(source: source);
    await links.start();
    expect(links.pending, isNull);

    source.arrive('https://privio.channel/houseoftrading');
    await pumpEventQueue();

    expect((links.pending! as ChannelLinkByHandle).handle, 'houseoftrading');
  });

  test('it waits rather than being read once', () async {
    // The whole point: a link can arrive at the lock screen, or on a device
    // with no account at all. It has to still be there after signing up.
    final links = DeepLinkController(
      source: FakeLinks(launchedWith: 'https://privio.channel/+waiting'),
    );
    await links.start();

    // Several rebuilds later, nobody having taken it.
    expect(links.pending, isNotNull);
    expect(links.pending, isNotNull);
    expect(links.pending, isNotNull);
  });

  test('and is cleared only by whoever acted on it', () async {
    final links = DeepLinkController(
      source: FakeLinks(launchedWith: 'https://privio.channel/+acted'),
    );
    await links.start();

    var notified = 0;
    links.addListener(() => notified++);

    links.taken();
    expect(links.pending, isNull);
    expect(notified, 1);

    // Taking nothing is not a change, and must not wake every listener.
    links.taken();
    expect(notified, 1);
  });

  test('a link that names nothing is reported rather than swallowed', () async {
    final links = DeepLinkController(
      source: FakeLinks(launchedWith: 'https://example.com/something/else'),
    );
    await links.start();

    // Silence would leave somebody staring at an app that did nothing when
    // they tapped a link.
    expect(links.pending, isNull);
    expect(links.unreadable, isTrue);
    expect(links.raw, 'https://example.com/something/else');
  });

  test('the last link wins', () async {
    final source = FakeLinks();
    final links = DeepLinkController(source: source);
    await links.start();

    source.arrive('https://privio.channel/+first');
    await pumpEventQueue();
    source.arrive('https://privio.channel/+second');
    await pumpEventQueue();

    // Two taps in a row is one person changing their mind, not a queue.
    expect((links.pending! as ChannelLinkByCode).code, 'second');
  });

  test('starting twice does not listen twice', () async {
    final source = FakeLinks();
    final links = DeepLinkController(source: source);
    await links.start();
    await links.start();

    var notified = 0;
    links.addListener(() => notified++);
    source.arrive('https://privio.channel/+once');
    await pumpEventQueue();

    expect(notified, 1, reason: 'one arrival, one notification');
  });

  test('nothing arrives by default', () async {
    // The default source is what every widget test and every build that never
    // wires a platform up gets.
    final links = DeepLinkController();
    await links.start();
    expect(links.pending, isNull);
    expect(links.unreadable, isFalse);
  });
}
