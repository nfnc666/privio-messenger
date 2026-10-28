import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../models/geo_point.dart';
import '../theme/accent.dart';
import '../theme/privio_colors.dart';

/// Hands a place to a maps app. Returns whether one took it.
typedef MapsOpener = Future<bool> Function(Uri uri);

Future<bool> _launch(Uri uri) async {
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } on Object {
    return false;
  }
}

/// The address a maps app on this platform reads a place from.
///
/// `geo:` on Android, which every maps app there registers for, including the
/// ones without Google in them. iOS has no `geo:`; Apple Maps is opened by its
/// own link, which the system hands to the app rather than to a browser.
Uri mapsUri(GeoPoint point, TargetPlatform platform) {
  final place = '${point.latitude},${point.longitude}';
  return platform == TargetPlatform.iOS || platform == TargetPlatform.macOS
      ? Uri.https('maps.apple.com', '/', {'ll': place, 'q': place})
      : Uri.parse('geo:$place?q=$place');
}

/// A place inside a chat bubble: the coordinates, and two ways to use them.
///
/// **No map is drawn.** A map is pictures fetched from a map server for the
/// spot on screen, which tells that server the place before anybody chose to.
/// Opening it in a maps app is a choice, asked for first; copying the numbers
/// tells nobody anything.
class LocationCard extends StatelessWidget {
  const LocationCard({super.key, required this.point, this.opener});

  final GeoPoint point;

  /// How the place reaches a maps app. Null is the system's own.
  final MapsOpener? opener;

  Future<void> _open(BuildContext context) async {
    final text = AppText.of(context);
    final open = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PrivioColors.surface,
        title: Text(text.locationOpenTitle),
        content: Text(text.locationOpenNote),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(text.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(text.locationOpen),
          ),
        ],
      ),
    );
    if (open != true || !context.mounted) return;
    final opened = await (opener ?? _launch)(mapsUri(point, defaultTargetPlatform));
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text.locationNoMapsApp)),
      );
    }
  }

  Future<void> _copy(BuildContext context) async {
    final text = AppText.of(context);
    await Clipboard.setData(ClipboardData(text: point.coordinates));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text.commonCopied)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = AppText.of(context);
    final accuracy = point.accuracyMeters;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.place_outlined, size: 18, color: context.accents.accent),
            const SizedBox(width: PrivioSpacing.xs),
            Text(text.locationTitle, style: theme.textTheme.titleSmall),
          ],
        ),
        const SizedBox(height: PrivioSpacing.xs),
        Text(point.coordinates, style: theme.textTheme.bodyMedium),
        if (accuracy != null)
          Text(text.locationAccuracy(accuracy), style: theme.textTheme.bodySmall),
        const SizedBox(height: PrivioSpacing.xs),
        Wrap(
          spacing: PrivioSpacing.xs,
          children: [
            TextButton.icon(
              key: const Key('location-open'),
              onPressed: () => _open(context),
              icon: const Icon(Icons.map_outlined, size: 18),
              label: Text(text.locationOpenInMaps),
            ),
            TextButton.icon(
              key: const Key('location-copy'),
              onPressed: () => _copy(context),
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: Text(text.locationCopy),
            ),
          ],
        ),
      ],
    );
  }
}
