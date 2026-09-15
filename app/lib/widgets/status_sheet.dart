import 'package:flutter/material.dart';

import '../core/status_controller.dart';
import '../l10n/app_localizations.dart';
import '../l10n/failure_text.dart';
import '../theme/accent.dart';
import '../theme/privio_colors.dart';

/// How long a status lasts, as the sheet offers it.
///
/// Durations rather than labels, for the same reason the disappearing-message
/// sheet keeps them that way: a map keyed by "1 hour" makes the English wording
/// part of the data, and the wording is the one thing here that differs per
/// reader.
const List<Duration?> statusDurations = <Duration?>[
  null,
  Duration(minutes: 30),
  Duration(hours: 1),
  Duration(hours: 4),
  Duration(days: 1),
  Duration(days: 7),
];

/// The wording for one of [statusDurations].
String statusDurationLabel(AppText text, Duration? duration) => switch (duration) {
      null => text.accountStatusNeverClears,
      Duration(inMinutes: 30) => text.accountStatus30Minutes,
      Duration(inMinutes: 60) => text.accountStatus1Hour,
      Duration(inMinutes: 240) => text.accountStatus4Hours,
      Duration(inHours: 24) => text.accountStatusToday,
      Duration(inDays: 7) => text.accountStatus1Week,
      _ => text.accountStatusNeverClears,
    };

/// A small, fixed set of faces, so the sheet needs no emoji keyboard.
///
/// Fixed rather than free-form because the field is eight UTF-16 units wide on
/// the server and a picker is the only way to say that without an error message
/// nobody should have to read. Somebody who wants a different one types it into
/// the text, where it belongs.
const List<String> statusEmoji = <String>[
  '😀', '😴', '🎧', '📚', '💻', '☕', '🏃', '✈️', '🏖️', '🤒', '🎉', '🤫',
];

/// Asks for a new status.
///
/// Returns nothing: the controller is the record of what happened. A sheet that
/// returned a value would tempt its caller into writing that value onto a
/// screen, and "the save returned" is not the same as "the server took it" —
/// which is exactly the distinction this feature exists to get right.
Future<void> showStatusSheet(BuildContext context, StatusController controller) {
  controller.clearFailure();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: PrivioColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: PrivioRadius.card),
    ),
    builder: (sheetContext) => Padding(
      // Lifts the sheet clear of the keyboard, which otherwise covers the field
      // it belongs to.
      padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
      child: _StatusSheet(controller: controller),
    ),
  );
}

class _StatusSheet extends StatefulWidget {
  const _StatusSheet({required this.controller});

  final StatusController controller;

  @override
  State<_StatusSheet> createState() => _StatusSheetState();
}

class _StatusSheetState extends State<_StatusSheet> {
  late final TextEditingController _text;

  /// The draft, held here and not in the controller.
  ///
  /// That is what makes Cancel free: nothing outside this widget has been told
  /// anything until Save returns, so dismissing the sheet discards the draft by
  /// simply ceasing to exist. It is also what keeps a failed save editable —
  /// the field still holds what was typed, because the failure never reached it.
  String? _emoji;
  Duration? _clearsAfter;

  @override
  void initState() {
    super.initState();
    final status = widget.controller.status;
    // Loaded for editing, not blanked. Opening the sheet on an existing status
    // and finding an empty field is how somebody deletes one by accident.
    _text = TextEditingController(text: status.isSet ? status.text ?? '' : '');
    _emoji = status.isSet ? status.emoji : null;
    _clearsAfter = null;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final controller = widget.controller;
    if (controller.saving) return;
    final typed = _text.text.trim();
    final after = _clearsAfter;
    final ok = await controller.save(
      text: typed.isEmpty ? null : typed,
      emoji: _emoji,
      expiresAt: after == null ? null : DateTime.now().add(after),
    );
    if (!mounted) return;
    // Only a success closes the sheet. A failure leaves it open with the draft
    // in the field and the reason underneath, which is the whole of "keep the
    // draft and allow another attempt".
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() {});
    }
  }

  Future<void> _remove() async {
    final controller = widget.controller;
    if (controller.saving) return;
    final ok = await controller.remove();
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final theme = Theme.of(context);
    final accents = context.accents;

    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final saving = widget.controller.saving;
        final failure = widget.controller.failure;
        final hasStatus = widget.controller.status.isSet;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(PrivioSpacing.gutter),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text.accountStatusTitle, style: theme.textTheme.titleMedium),
                const SizedBox(height: PrivioSpacing.xs),
                Text(
                  text.accountStatusExplainer,
                  style: theme.textTheme.bodySmall?.copyWith(color: PrivioColors.textTertiary),
                ),
                const SizedBox(height: PrivioSpacing.lg),
                TextField(
                  controller: _text,
                  enabled: !saving,
                  maxLength: 140,
                  maxLines: 2,
                  minLines: 1,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: text.accountStatusHint,
                    prefixIcon: _emoji == null
                        ? null
                        : Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: PrivioSpacing.md,
                              vertical: PrivioSpacing.sm,
                            ),
                            child: Text(_emoji!, style: const TextStyle(fontSize: 20)),
                          ),
                    prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                Text(text.accountStatusEmoji, style: theme.textTheme.labelSmall),
                const SizedBox(height: PrivioSpacing.sm),
                _EmojiRow(
                  selected: _emoji,
                  enabled: !saving,
                  onPick: (value) => setState(() => _emoji = _emoji == value ? null : value),
                ),
                const SizedBox(height: PrivioSpacing.lg),
                Text(text.accountStatusClearsAfter, style: theme.textTheme.labelSmall),
                const SizedBox(height: PrivioSpacing.sm),
                Wrap(
                  spacing: PrivioSpacing.sm,
                  runSpacing: PrivioSpacing.sm,
                  children: [
                    for (final duration in statusDurations)
                      ChoiceChip(
                        label: Text(statusDurationLabel(text, duration)),
                        selected: _clearsAfter == duration,
                        onSelected: saving ? null : (_) => setState(() => _clearsAfter = duration),
                        selectedColor: accents.surface,
                        side: BorderSide(
                          color: _clearsAfter == duration ? accents.accent : PrivioColors.border,
                        ),
                      ),
                  ],
                ),
                if (failure != null) ...[
                  const SizedBox(height: PrivioSpacing.md),
                  Text(
                    failure.words(text),
                    style: theme.textTheme.bodySmall?.copyWith(color: PrivioColors.danger),
                  ),
                ],
                const SizedBox(height: PrivioSpacing.lg),
                // Save is full width and alone on its line, because that is what
                // a primary button is in this app: the theme gives every
                // FilledButton `Size.fromHeight(52)`, which is an *infinite*
                // minimum width. One placed beside other buttons in a Row asks
                // for infinity and the layout fails outright — which is how this
                // arrangement was arrived at.
                FilledButton(
                  // Null while saving, which is what prevents the second
                  // request. The controller refuses re-entry as well, so a tap
                  // the framework delivers anyway changes nothing.
                  onPressed: saving ? null : _save,
                  child: saving
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: accents.onAccent,
                          ),
                        )
                      : Text(text.commonSave),
                ),
                const SizedBox(height: PrivioSpacing.xs),
                Row(
                  children: [
                    if (hasStatus)
                      TextButton(
                        onPressed: saving ? null : _remove,
                        child: Text(
                          text.commonRemove,
                          style: const TextStyle(color: PrivioColors.danger),
                        ),
                      ),
                    const Spacer(),
                    TextButton(
                      // Cancel stays live while a save is running: it dismisses
                      // the sheet, it does not cancel the request. Disabling it
                      // would trap somebody behind a slow network.
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(text.commonCancel),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EmojiRow extends StatelessWidget {
  const _EmojiRow({required this.selected, required this.enabled, required this.onPick});

  final String? selected;
  final bool enabled;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final accents = context.accents;
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: statusEmoji.length,
        separatorBuilder: (_, __) => const SizedBox(width: PrivioSpacing.sm),
        itemBuilder: (context, index) {
          final emoji = statusEmoji[index];
          final isSelected = emoji == selected;
          return Semantics(
            selected: isSelected,
            button: true,
            child: InkWell(
              onTap: enabled ? () => onPick(emoji) : null,
              borderRadius: const BorderRadius.all(PrivioRadius.pill),
              child: Container(
                width: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected ? accents.surface : PrivioColors.surfaceRaised,
                  borderRadius: const BorderRadius.all(PrivioRadius.pill),
                  border: Border.all(
                    color: isSelected ? accents.accent : PrivioColors.border,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Text(emoji, style: const TextStyle(fontSize: 20)),
              ),
            ),
          );
        },
      ),
    );
  }
}
