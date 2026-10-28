import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/models.dart';
import '../theme/accent.dart';
import '../theme/privio_colors.dart';

/// The small mark beside a name in a list: verified, or a number that changed.
///
/// Nothing at all for a person whose number was never compared, which is
/// every conversation to begin with. Read out by a screen reader in the same
/// words the chat header and the safety number screen use.
class TrustBadge extends StatelessWidget {
  const TrustBadge(this.mark, {super.key});

  final TrustMark mark;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final (label, icon, colour) = switch (mark) {
      TrustMark.none => (null, null, null),
      TrustMark.verified =>
        (text.safetyVerified, Icons.verified_user_rounded, context.accents.accent),
      TrustMark.changed =>
        (text.chatSafetyNumberChanged, Icons.error_outline_rounded, PrivioColors.warning),
    };
    if (icon == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Semantics(
        label: label,
        child: Icon(icon, size: 14, color: colour),
      ),
    );
  }
}
