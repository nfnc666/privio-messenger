import 'package:flutter/material.dart';

import '../core/mention_suggestions.dart';
import '../theme/privio_colors.dart';
import 'avatar.dart';

/// The rows offered while an `@` is being typed.
///
/// Sits directly above the composer, is only built when there is something to
/// offer, and closes the moment the `@word` stops being one — so it never
/// covers the conversation for longer than it is useful.
///
/// Each row shows the picture, the display name and the `@username`, because
/// the display name is the one somebody recognises and the username is the one
/// that will actually be inserted. Showing only the first would make picking
/// the right person a guess when two people share a name.
class MentionSuggestionsBar extends StatelessWidget {
  const MentionSuggestionsBar({
    required this.candidates,
    required this.onPick,
    super.key,
  });

  final List<MentionCandidate> candidates;
  final void Function(MentionCandidate candidate) onPick;

  @override
  Widget build(BuildContext context) {
    if (candidates.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Container(
      constraints: const BoxConstraints(maxHeight: 240),
      decoration: const BoxDecoration(
        color: PrivioColors.surface,
        border: Border(top: BorderSide(color: PrivioColors.border)),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: candidates.length,
        itemBuilder: (context, index) {
          final candidate = candidates[index];
          return ListTile(
            dense: true,
            leading: PrivioAvatar(
              label: candidate.displayName,
              seed: candidate.avatarSeed,
              imageBytes: candidate.avatarBytes,
              size: 32,
            ),
            title: Text(
              candidate.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
            subtitle: Text(
              '@${candidate.username}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
            onTap: () => onPick(candidate),
          );
        },
      ),
    );
  }
}
