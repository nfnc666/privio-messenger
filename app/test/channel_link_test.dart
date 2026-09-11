import 'package:flutter_test/flutter_test.dart';
import 'package:privio/models/channel.dart';
import 'package:privio/services/channel_service.dart';

/// Reading a link back.
///
/// The two shapes are not interchangeable and the tests say why: a code is a
/// capability, a handle is a name. A parser that confused them would let a
/// guessed name stand in for an unguessable code.
void main() {
  ChannelLinkTarget? parse(String link) => ChannelService.parseLink(link);

  group('what a link names', () {
    test('a private invitation is a code', () {
      final target = parse('https://privio.channel/+aBcD1234efGh');
      expect(target, isA<ChannelLinkByCode>());
      expect((target! as ChannelLinkByCode).code, 'aBcD1234efGh');
      expect((target as ChannelLinkByCode).kind, InviteKind.channel);
    });

    test('a public channel is a handle, and carries no capability', () {
      final target = parse('https://privio.channel/houseoftrading');
      expect(target, isA<ChannelLinkByHandle>());
      expect((target! as ChannelLinkByHandle).handle, 'houseoftrading');
    });

    test('the shape every shipped build generates still works', () {
      // A link already pasted somewhere cannot be rewritten.
      final target = parse('https://privio.channel/c/oldstylecode');
      expect((target! as ChannelLinkByCode).code, 'oldstylecode');
      expect((target as ChannelLinkByCode).kind, InviteKind.channel);
    });

    test('a group link is a group', () {
      final target = parse('https://privio.group/g/groupcode');
      expect((target! as ChannelLinkByCode).kind, InviteKind.group);
    });
  });

  group('the /open path', () {
    // The web page's button uses /open, and it is the only shape the app-link
    // files claim — so it is what most real links arrive as. It names the same
    // thing as the link that was shared.
    test('names the same thing as the link that was shared', () {
      expect(
        (parse('https://privio.channel/open/+code123')! as ChannelLinkByCode).code,
        (parse('https://privio.channel/+code123')! as ChannelLinkByCode).code,
      );
      expect(
        (parse('https://privio.channel/open/houseoftrading')! as ChannelLinkByHandle).handle,
        'houseoftrading',
      );
    });

    test('and so does the app’s own scheme', () {
      expect(
        (parse('privio://open/+code123')! as ChannelLinkByCode).code,
        'code123',
      );
      expect(
        (parse('privio://houseoftrading')! as ChannelLinkByHandle).handle,
        'houseoftrading',
      );
      expect((parse('privio://c/oldstyle')! as ChannelLinkByCode).code, 'oldstyle');
    });
  });

  group('the host is not the authorisation', () {
    test('a re-hosted or shortened link still names the same channel', () {
      // The code in the path is the capability. A mail scanner that rewrote the
      // host did not change what the link names, and refusing it would break a
      // link for the person it was sent to while protecting nobody.
      expect(
        (parse('https://mail-guard.example.com/c/code123')! as ChannelLinkByCode).code,
        'code123',
      );
      expect(
        (parse('https://privio-server-1o8j.onrender.com/+code123')! as ChannelLinkByCode).code,
        'code123',
      );
    });
  });

  group('what is not a link', () {
    test('nonsense, and empty paths', () {
      expect(parse('not a url at all '), isNull);
      expect(parse('https://privio.channel/'), isNull);
      expect(parse('https://privio.channel'), isNull);
      expect(parse('https://privio.channel/+'), isNull, reason: 'a plus with no code');
    });

    test('a path that is not a handle', () {
      // Two segments is some other page on the same host, not a channel.
      expect(parse('https://privio.channel/about/privacy'), isNull);
      expect(parse('https://privio.channel/ab'), isNull, reason: 'too short for a handle');
      expect(
        parse('https://privio.channel/NotAHandle'),
        isNull,
        reason: 'handles are lower case; a guess must not resolve',
      );
    });

    test('the download page is not a channel called download', () {
      // It is a handle by shape, and that is the honest limit of this: the app
      // will look it up and be told there is no such channel. What matters is
      // that it cannot be mistaken for an invitation.
      expect(parse('https://privio.channel/download'), isA<ChannelLinkByHandle>());
    });
  });

  group('the link a channel shares', () {
    test('a public channel shares its name', () {
      const channel = ChannelInfo(
        id: 'x',
        visibility: ChannelVisibility.public,
        title: 'House of Trading',
        handle: 'houseoftrading',
        inviteCode: 'secretcapability',
      );
      final link = ChannelService.shareLinkFor(channel);
      expect(link, 'https://privio.channel/houseoftrading');
      expect(
        link,
        isNot(contains('secretcapability')),
        reason: 'a poster must not carry a capability',
      );
    });

    test('a private channel shares its code, because it has nothing else', () {
      const channel = ChannelInfo(
        id: 'x',
        visibility: ChannelVisibility.private,
        title: 'Private channel',
        inviteCode: 'thecapability',
      );
      expect(
        ChannelService.shareLinkFor(channel),
        'https://privio.channel/+thecapability',
      );
    });

    test('and a channel with no code at all has no link', () {
      const channel = ChannelInfo(
        id: 'x',
        visibility: ChannelVisibility.private,
        title: 'Private channel',
      );
      expect(ChannelService.shareLinkFor(channel), isNull);
    });

    test('every link a channel shares reads back as the channel', () {
      // The round trip is the property that matters: whatever is built here
      // has to survive being pasted somewhere and read back.
      const public = ChannelInfo(
        id: 'x',
        visibility: ChannelVisibility.public,
        title: 'T',
        handle: 'roundtrip',
        inviteCode: 'c',
      );
      const private = ChannelInfo(
        id: 'y',
        visibility: ChannelVisibility.private,
        title: 'T',
        inviteCode: 'roundtripcode',
      );

      expect(
        (parse(ChannelService.shareLinkFor(public)!)! as ChannelLinkByHandle).handle,
        'roundtrip',
      );
      expect(
        (parse(ChannelService.shareLinkFor(private)!)! as ChannelLinkByCode).code,
        'roundtripcode',
      );
    });
  });
}
