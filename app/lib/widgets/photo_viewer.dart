import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/privio_colors.dart';
import 'privio_back_button.dart';

/// A picture at full size, with pinch and pan.
///
/// The bytes are the ones already decrypted in memory by whatever is showing
/// the picture — opening this writes nothing to disk and asks the server for
/// nothing a second time. There is deliberately no "save to gallery" here:
/// that would copy a message out of the app's own storage and past the
/// disappearing-messages timer, into a folder every other app can read.
///
/// It lived inside the channel feed as a private widget and the chat had
/// nothing at all: an image in a message could only be looked at at bubble
/// size. One widget, used by both, rather than a second implementation of the
/// same three lines.
class PhotoViewer extends StatelessWidget {
  const PhotoViewer({required this.bytes, super.key, this.name});

  final Uint8List bytes;

  /// What to put in the bar. Null falls back to the word for a picture, which
  /// is the right answer for a photo sent from a camera: it has a file name,
  /// but the app invented it and showing `photo-1.jpg` tells nobody anything.
  final String? name;

  /// Opens the viewer over whatever is on screen.
  static Future<void> open(BuildContext context, {required Uint8List bytes, String? name}) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PhotoViewer(bytes: bytes, name: name)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PrivioColors.background,
      appBar: AppBar(
        backgroundColor: PrivioColors.background,
        leading: const PrivioBackButton(),
        title: Text(
          name ?? AppText.of(context).photoTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 6,
          child: Image.memory(bytes),
        ),
      ),
    );
  }
}
