import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../media/photo.dart';
import '../theme/accent.dart';
import '../theme/privio_colors.dart';


/// What the person decided in the preview.
///
/// Three outcomes and only one of them sends anything. The brief's own words
/// for the reason: a photo must never go out because a shutter button was
/// pressed. The shutter produces a picture; this screen decides whether it
/// becomes a message.
sealed class PhotoPreviewResult {
  const PhotoPreviewResult();
}

/// Send these, with this caption. Never empty: removing the last picture
/// closes the screen as a cancel.
final class PhotoPreviewSend extends PhotoPreviewResult {
  const PhotoPreviewSend({required this.photos, required this.caption});

  final List<PreparedPhoto> photos;
  final String caption;
}

/// Throw this one away and open the camera again.
final class PhotoPreviewRetake extends PhotoPreviewResult {
  const PhotoPreviewRetake();
}

/// The pictures before they are anything.
///
/// A full screen rather than a bottom sheet: a photo judged in a 200-pixel
/// strip is a photo nobody has actually looked at, and this is the last point
/// at which it can be stopped.
///
/// [onRetake] is offered only for a capture. There is nothing to retake about
/// a picture chosen from the library — that button would mean "choose again",
/// which is what cancelling and tapping the same menu entry already does.
class PhotoPreviewSheet extends StatefulWidget {
  const PhotoPreviewSheet({required this.photos, super.key, this.allowRetake = false});

  final List<PreparedPhoto> photos;
  final bool allowRetake;

  /// Opens the preview. Null means cancelled — and cancelled means nothing was
  /// sent, uploaded, or written anywhere.
  static Future<PhotoPreviewResult?> open(
    BuildContext context, {
    required List<PreparedPhoto> photos,
    bool allowRetake = false,
  }) {
    return Navigator.of(context).push<PhotoPreviewResult>(
      MaterialPageRoute<PhotoPreviewResult>(
        fullscreenDialog: true,
        builder: (_) => PhotoPreviewSheet(photos: photos, allowRetake: allowRetake),
      ),
    );
  }

  @override
  State<PhotoPreviewSheet> createState() => _PhotoPreviewSheetState();
}

class _PhotoPreviewSheetState extends State<PhotoPreviewSheet> {
  late final List<PreparedPhoto> _photos = List.of(widget.photos);
  final TextEditingController _caption = TextEditingController();
  int _showing = 0;

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  void _remove(int index) {
    // The last picture gone is the same decision as cancelling, so it has the
    // same outcome rather than leaving an empty screen with a Send button on
    // it — and it closes *without* a setState first. Rebuilding on an empty
    // list draws `_photos[_showing]` with nothing in it, which is a range
    // error in the frame before the pop lands. A test holds this.
    if (_photos.length <= 1) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _photos.removeAt(index);
      if (_showing >= _photos.length) _showing = _photos.length - 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: PrivioColors.background,
      appBar: AppBar(
        backgroundColor: PrivioColors.background,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: text.commonCancel,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          _photos.length == 1 ? text.photoPreviewOne : text.photoPreviewMany(_photos.length),
          style: theme.textTheme.titleSmall,
        ),
        actions: [
          if (widget.allowRetake)
            TextButton(
              onPressed: () => Navigator.of(context).pop(const PhotoPreviewRetake()),
              child: Text(text.photoRetake),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Image.memory(
                    _photos[_showing].bytes,
                    fit: BoxFit.contain,
                    // Keyed on the picture, so removing one redraws rather than
                    // leaving the previous image under the new index.
                    key: ValueKey(_photos[_showing].fileName),
                  ),
                ),
                Positioned(
                  top: PrivioSpacing.sm,
                  right: PrivioSpacing.sm,
                  child: IconButton.filledTonal(
                    icon: const Icon(Icons.delete_outline_rounded),
                    tooltip: text.commonRemove,
                    onPressed: () => _remove(_showing),
                  ),
                ),
              ],
            ),
          ),
          if (_photos.length > 1) _Strip(
            photos: _photos,
            showing: _showing,
            onShow: (index) => setState(() => _showing = index),
            onRemove: _remove,
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(PrivioSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _caption,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: text.photoCaptionHint,
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: PrivioSpacing.sm),
                  IconButton.filled(
                    icon: const Icon(Icons.send_rounded),
                    tooltip: text.chatSend,
                    style: IconButton.styleFrom(backgroundColor: context.accents.bright),
                    onPressed: () => Navigator.of(context).pop(
                      PhotoPreviewSend(photos: _photos, caption: _caption.text.trim()),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The row of thumbnails under a multiple selection.
///
/// It draws them in the order they were chosen, which is the order they will
/// be sent in; a set of photos that arrives shuffled is a set somebody has to
/// explain.
class _Strip extends StatelessWidget {
  const _Strip({
    required this.photos,
    required this.showing,
    required this.onShow,
    required this.onRemove,
  });

  final List<PreparedPhoto> photos;
  final int showing;
  final void Function(int index) onShow;
  final void Function(int index) onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.md),
        itemCount: photos.length,
        separatorBuilder: (_, __) => const SizedBox(width: PrivioSpacing.sm),
        itemBuilder: (context, index) {
          final selected = index == showing;
          return GestureDetector(
            onTap: () => onShow(index),
            child: Stack(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  margin: const EdgeInsets.only(top: 8, right: 8),
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.all(PrivioRadius.card),
                    border: Border.all(
                      color: selected ? context.accents.bright : PrivioColors.border,
                      width: selected ? 2 : 1,
                    ),
                    image: DecorationImage(
                      image: MemoryImage(photos[index].bytes),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: () => onRemove(index),
                    child: Container(
                      decoration: const BoxDecoration(
                        color: PrivioColors.surface,
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(2),
                      child: const Icon(Icons.close_rounded, size: 14),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
