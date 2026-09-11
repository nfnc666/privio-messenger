import 'package:app_links/app_links.dart';

import '../core/deep_links.dart';

/// The platform's side of an incoming link.
///
/// A thin wrapper, and thin on purpose: everything that decides what a link
/// *means* lives in `ChannelService.parseLink`, where it can be tested without
/// a device. This class only knows how to be told.
///
/// It covers both arrivals. `getInitialLink` is the one that matters most and
/// is the one an implementation usually gets wrong: on a cold start the link is
/// delivered before any listener exists, so a stream subscription alone drops
/// exactly the case where somebody tapped an invitation on a phone that did not
/// have Privio open.
class PlatformIncomingLinks implements IncomingLinks {
  PlatformIncomingLinks([AppLinks? links]) : _links = links ?? AppLinks();

  final AppLinks _links;

  @override
  Future<String?> initial() async {
    try {
      return (await _links.getInitialLink())?.toString();
    } on Object {
      // A platform that has no answer is not a reason to fail start-up.
      return null;
    }
  }

  @override
  Stream<String> get stream => _links.uriLinkStream.map((uri) => uri.toString());
}
