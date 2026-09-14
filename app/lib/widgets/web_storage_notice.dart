import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/privio_colors.dart';
import '../l10n/app_localizations.dart';

/// What "encrypted at rest" is worth in a browser.
///
/// On iOS and Android the key to the local history lives in the Keychain or in
/// EncryptedSharedPreferences, where the operating system keeps it away from
/// everything else on the device. A browser has no such place. The web build
/// stores it with `flutter_secure_storage`, whose web implementation keeps a
/// raw AES key in `localStorage` beside the values it encrypts — so anyone who
/// can read that origin's `localStorage` (a shared or borrowed computer, an
/// extension with storage permission, a forensic copy of the profile) can
/// decrypt the history and the Signal private keys with nothing else.
///
/// That is a property of the platform rather than a bug to fix here: there is
/// no OS-held key for a page to ask for. What can be fixed is a user finding it
/// out afterwards. `tools/web-storage-recovery.mjs` demonstrates the recovery
/// in full, and this says so before anybody types anything.
class WebStorageNotice extends StatelessWidget {
  const WebStorageNotice({super.key, this.compact = false});

  /// Whether to draw the short form, for a screen that is already dense.
  final bool compact;

  /// Only the browser build is affected, so only it says anything.
  static bool get applies => kIsWeb;

  @override
  Widget build(BuildContext context) {
    if (!applies) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(PrivioSpacing.md),
      decoration: BoxDecoration(
        color: PrivioColors.surfaceRaised,
        borderRadius: const BorderRadius.all(PrivioRadius.card),
        border: Border.all(color: PrivioColors.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, size: 16, color: PrivioColors.warning),
          const SizedBox(width: PrivioSpacing.sm),
          Expanded(
            child: Text(
              compact
                  ? AppText.of(context).webStorageShort
                  : AppText.of(context).webStorageLong,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
