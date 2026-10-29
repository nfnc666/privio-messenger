import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/screen_shield_controller.dart';
import '../l10n/app_localizations.dart';
import '../theme/privio_colors.dart';
import 'privio_back_button.dart';

/// A photo meant to be viewed once, while it is being viewed.
///
/// The bytes are the only copy left: the key was dropped and written down
/// dropped before this opened, so closing it is the end of the picture on this
/// device. Nothing here saves, shares or caches it.
///
/// The screen is protected for as long as this is open, whatever the account
/// chose for the rest of the app, and the line at the bottom says what that
/// protection is worth on this phone. On Android a screenshot is refused; on
/// iPhone it cannot be, and a recording only covers the picture while it runs;
/// nowhere does it stop a second camera.
class ViewOnceViewer extends StatefulWidget {
  const ViewOnceViewer({required this.bytes, super.key, this.shield});

  final Uint8List bytes;
  final ScreenShieldController? shield;

  static Future<void> open(BuildContext context, {required Uint8List bytes}) {
    final shield = PrivioScope.maybeOf(context)?.screenShield;
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ViewOnceViewer(bytes: bytes, shield: shield),
      ),
    );
  }

  @override
  State<ViewOnceViewer> createState() => _ViewOnceViewerState();
}

class _ViewOnceViewerState extends State<ViewOnceViewer> {
  @override
  void initState() {
    super.initState();
    widget.shield?.hold();
  }

  @override
  void dispose() {
    widget.shield?.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final shield = widget.shield;
    return Scaffold(
      backgroundColor: PrivioColors.background,
      appBar: AppBar(
        backgroundColor: PrivioColors.background,
        leading: const PrivioBackButton(),
        title: Text(text.photoViewOnce, style: Theme.of(context).textTheme.titleSmall),
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 6,
                child: Image.memory(widget.bytes, gaplessPlayback: true),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(PrivioSpacing.md),
              // Rebuilt as the platform answers: what the protection is worth
              // is not known until it has said what it can do.
              child: ListenableBuilder(
                listenable: shield ?? const AlwaysStoppedAnimation<void>(null),
                builder: (context, _) {
                  final capability = shield?.capability;
                  final protection = capability == null
                      ? text.viewOnceNoteNone
                      : capability.blocksCapture
                          ? text.viewOnceNoteBlocked
                          : capability.detectsCapture
                              ? text.viewOnceNoteDetects
                              : text.viewOnceNoteNone;
                  return Text(
                    '$protection ${text.viewOnceGone}',
                    key: const Key('view-once-note'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: PrivioColors.textTertiary),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
