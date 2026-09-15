import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../media/sticker_image.dart';
import '../theme/accent.dart';
import '../theme/privio_colors.dart';

/// Lets somebody choose the square of a picture that becomes a sticker.
///
/// Returns PNG bytes, or null if they backed out.
///
/// The gesture is the ordinary one — drag to move, pinch to zoom — done with
/// `InteractiveViewer` rather than by hand, so it behaves the way every other
/// zoomable picture on the phone behaves. What this file adds is the part that
/// is not free: turning the view's transform back into a rectangle in the
/// *source* image, because that is what the encoder crops and the two are not
/// the same coordinate space.
Future<Uint8List?> showStickerCropSheet(BuildContext context, Uint8List picked) =>
    showModalBottomSheet<Uint8List>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _StickerCropSheet(picked: picked),
    );

class _StickerCropSheet extends StatefulWidget {
  const _StickerCropSheet({required this.picked});

  final Uint8List picked;

  @override
  State<_StickerCropSheet> createState() => _StickerCropSheetState();
}

class _StickerCropSheetState extends State<_StickerCropSheet> {
  final TransformationController _view = TransformationController();
  bool _working = false;

  @override
  void dispose() {
    _view.dispose();
    super.dispose();
  }

  /// Turns the viewer's transform into a crop in fractions of the source.
  ///
  /// `InteractiveViewer` gives a matrix that maps the child into the viewport.
  /// Inverting it says which part of the child the viewport is showing, and the
  /// child is drawn `BoxFit.contain` inside a square — so the visible rectangle
  /// in child coordinates, divided by the child's size, is the fraction the
  /// encoder needs. No knowledge of the source's pixel dimensions is required
  /// anywhere, which is why this survives the picture being any size at all.
  StickerCrop _crop(Size viewport) {
    final matrix = _view.value;
    final scale = matrix.getMaxScaleOnAxis();
    // The translation is in viewport pixels and negative as the child moves up
    // and left, so dividing by the scale puts it back in child pixels.
    final dx = -matrix.getTranslation().x / scale;
    final dy = -matrix.getTranslation().y / scale;
    final side = viewport.width / scale;

    return StickerCrop(
      left: (dx / viewport.width).clamp(0.0, 1.0),
      top: (dy / viewport.height).clamp(0.0, 1.0),
      side: (side / viewport.width).clamp(0.05, 1.0),
    );
  }

  Future<void> _use(Size viewport) async {
    setState(() => _working = true);
    final bytes = await StickerImage.prepare(widget.picked, crop: _crop(viewport));
    if (!mounted) return;
    setState(() => _working = false);
    Navigator.of(context).pop(bytes);
  }

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(PrivioSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(text.stickersCropTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: PrivioSpacing.sm),
            Text(
              text.stickersCropHint,
              style: theme.textTheme.bodySmall?.copyWith(color: PrivioColors.textTertiary),
            ),
            const SizedBox(height: PrivioSpacing.lg),
            LayoutBuilder(
              builder: (context, constraints) {
                // A square, because a sticker is one. Bounded so a tall phone
                // does not give the picture the whole screen and leave the
                // buttons off the bottom.
                final side = constraints.maxWidth.clamp(0.0, 320.0);
                final viewport = Size(side, side);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: side,
                        height: side,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          // The chequer under a transparent picture, so the
                          // person can see what is see-through before they
                          // find out in a chat.
                          color: context.accents.surface,
                          borderRadius: const BorderRadius.all(PrivioRadius.card),
                        ),
                        child: InteractiveViewer(
                          transformationController: _view,
                          minScale: 1,
                          maxScale: 6,
                          clipBehavior: Clip.none,
                          child: Image.memory(
                            widget.picked,
                            width: side,
                            height: side,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Center(
                              child: Text(text.stickersPickFailed),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: PrivioSpacing.lg),
                    FilledButton(
                      onPressed: _working ? null : () => _use(viewport),
                      child: Text(text.stickersUse),
                    ),
                    const SizedBox(height: PrivioSpacing.sm),
                    TextButton(
                      onPressed: _working ? null : () => Navigator.of(context).pop(),
                      child: Text(text.commonCancel),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
