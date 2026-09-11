import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/privio_colors.dart';

/// Text with the links in it made tappable.
///
/// The detection is deliberately narrow — `http://`, `https://` and a bare
/// `www.` — because every wider rule guesses a scheme somewhere, and a link
/// that opens something other than what it says is worse than one that has to
/// be copied by hand.
///
/// **Nothing opens without being confirmed first.** A channel post is a
/// stranger's text arriving on a stranger's terms; the characters of a URL are
/// not the address they resolve to, and a tap that leaves the app silently is
/// how somebody ends up on a page they never chose. The sheet names the host on
/// its own line, because the host is the part that decides where you actually
/// went.
class LinkedText extends StatefulWidget {
  const LinkedText(this.text, {this.style, this.linkStyle, super.key});

  final String text;
  final TextStyle? style;
  final TextStyle? linkStyle;

  @override
  State<LinkedText> createState() => _LinkedTextState();
}

class _LinkedTextState extends State<LinkedText> {
  /// Everything that looks like a link, and nothing that merely contains a dot.
  static final RegExp _pattern = RegExp(
    r'(?:https?://|www\.)[^\s<>"]+',
    caseSensitive: false,
  );

  /// One recognizer per link, held so they can be disposed.
  ///
  /// A `TapGestureRecognizer` built inside `build` is never disposed and keeps
  /// its entry in the gesture arena, so a feed that rebuilds on every arriving
  /// post leaks one per link per rebuild. They are therefore built once, when
  /// the text changes, and reused by every paint after that — which also means
  /// no recognizer is ever disposed in the middle of the tap it is handling.
  final Map<int, TapGestureRecognizer> _recognizers = {};

  /// The text taken apart into plain runs and link runs.
  late List<_Span> _spans;

  @override
  void initState() {
    super.initState();
    _rebuildSpans();
  }

  @override
  void didUpdateWidget(LinkedText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) _rebuildSpans();
  }

  void _rebuildSpans() {
    _disposeRecognizers();
    _spans = _split(widget.text);
    for (var index = 0; index < _spans.length; index++) {
      final span = _spans[index];
      if (!span.isLink) continue;
      _recognizers[index] = TapGestureRecognizer()
        ..onTap = () => _confirmAndOpen(span.text);
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers.values) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  /// Splits [text] into plain runs and link runs.
  static List<_Span> _split(String text) {
    final spans = <_Span>[];
    var cursor = 0;
    for (final match in _pattern.allMatches(text)) {
      // A URL at the end of a sentence takes the full stop with it unless the
      // trailing punctuation is handed back to the sentence it belongs to.
      final raw = _trimTrailingPunctuation(match.group(0)!);
      final start = match.start;
      final end = start + raw.length;
      if (start > cursor) spans.add(_Span(text.substring(cursor, start)));
      spans.add(_Span(raw, isLink: true));
      cursor = end;
    }
    if (cursor < text.length) spans.add(_Span(text.substring(cursor)));
    return spans;
  }

  static String _trimTrailingPunctuation(String url) {
    var end = url.length;
    while (end > 0) {
      final character = url[end - 1];
      if ('.,;:!?"\''.contains(character)) {
        end--;
      } else if (character == ')' && !url.substring(0, end).contains('(')) {
        // Only an unmatched one. `…/Foo_(bar)` is a real address.
        end--;
      } else {
        break;
      }
    }
    return url.substring(0, end);
  }

  /// The address a link run actually points at.
  static Uri? _target(String raw) {
    final withScheme = raw.toLowerCase().startsWith('www.') ? 'https://$raw' : raw;
    final uri = Uri.tryParse(withScheme);
    if (uri == null || uri.host.isEmpty) return null;
    // Anything that is not the web is not something a post gets to open. `tel:`,
    // `mailto:` and the app schemes other apps register are all reachable from
    // a crafted string, and none of them is what a reader expects from a link.
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    return uri;
  }

  Future<void> _confirmAndOpen(String raw) async {
    final uri = _target(raw);
    if (uri == null) {
      _say('That link is not a web address.');
      return;
    }
    final open = await showDialog<bool>(
      context: context,
      builder: (_) => _OpenLinkDialog(uri: uri),
    );
    if (open != true || !mounted) return;
    var launched = false;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object {
      launched = false;
    }
    if (!launched && mounted) _say('Nothing on this device could open that link.');
  }

  void _say(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final base = widget.style ?? Theme.of(context).textTheme.bodyMedium;
    final link = widget.linkStyle ??
        base?.copyWith(
          color: PrivioColors.accentBright,
          decoration: TextDecoration.underline,
          decorationColor: PrivioColors.accentDim,
        );

    // No link, no spans, no recognizers: the overwhelmingly common case stays a
    // plain `Text`.
    if (_spans.length == 1 && !_spans.first.isLink) {
      return Text(widget.text, style: base);
    }

    return Text.rich(
      TextSpan(
        style: base,
        children: [
          for (var index = 0; index < _spans.length; index++)
            TextSpan(
              text: _spans[index].text,
              style: _spans[index].isLink ? link : null,
              recognizer: _recognizers[index],
            ),
        ],
      ),
    );
  }
}

class _Span {
  const _Span(this.text, {this.isLink = false});

  final String text;
  final bool isLink;
}

/// Asks before leaving the app, and says where to.
class _OpenLinkDialog extends StatelessWidget {
  const _OpenLinkDialog({required this.uri});

  final Uri uri;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      backgroundColor: PrivioColors.surfaceRaised,
      title: const Text('Open this link?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The host first and on its own, because it is the part that decides
          // where the tap actually goes.
          Text(uri.host, style: theme.textTheme.titleSmall),
          const SizedBox(height: PrivioSpacing.xs),
          Text(
            uri.toString(),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: PrivioSpacing.md),
          Text(
            'This opens in your browser, outside Privio. The site sees your '
            'connection the way any site you visit does.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Open'),
        ),
      ],
    );
  }
}
