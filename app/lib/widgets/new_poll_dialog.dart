import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/channel.dart';
import '../theme/accent.dart';
import '../theme/privio_colors.dart';

/// Writing a poll: a question, two or more answers, and whether several may
/// be picked.
///
/// Shared by channels and chats, so a poll is written the same way wherever it
/// is asked. [note] says where the poll goes and who can read it, which is the
/// part that differs: a channel's tally is kept by the server, a chat's only on
/// the members' devices.
class NewPollDialog extends StatefulWidget {
  const NewPollDialog({
    super.key,
    required this.note,
    this.maxOptions = 12,
    this.maxOptionLength,
    this.maxQuestionLength,
  });

  final String note;

  /// Two is the fewest that is a question; twelve is what a channel allows and
  /// more than fits on a phone.
  final int maxOptions;
  final int? maxOptionLength;
  final int? maxQuestionLength;

  @override
  State<NewPollDialog> createState() => _NewPollDialogState();
}

class _NewPollDialogState extends State<NewPollDialog> {
  final TextEditingController _question = TextEditingController();
  final List<TextEditingController> _options = [
    TextEditingController(),
    TextEditingController(),
  ];
  bool _several = false;

  @override
  void dispose() {
    _question.dispose();
    for (final option in _options) {
      option.dispose();
    }
    super.dispose();
  }

  List<String> get _filled =>
      [for (final option in _options) option.text.trim()]..removeWhere((o) => o.isEmpty);

  bool get _ready => _question.text.trim().isNotEmpty && _filled.length >= 2;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      backgroundColor: PrivioColors.surfaceRaised,
      title: Text(AppText.of(context).feedAskQuestion),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _question,
              autofocus: true,
              maxLength: widget.maxQuestionLength,
              onChanged: (_) => setState(() {}),
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(hintText: AppText.of(context).feedPollQuestion),
            ),
            const SizedBox(height: PrivioSpacing.md),
            for (var index = 0; index < _options.length; index++)
              Padding(
                padding: const EdgeInsets.only(bottom: PrivioSpacing.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _options[index],
                        maxLength: widget.maxOptionLength,
                        onChanged: (_) => setState(() {}),
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: AppText.of(context).feedPollAnswerN(index + 1),
                        ),
                      ),
                    ),
                    if (_options.length > 2)
                      IconButton(
                        onPressed: () => setState(() => _options.removeAt(index).dispose()),
                        icon: const Icon(Icons.close_rounded, size: 18),
                        tooltip: AppText.of(context).commonRemove,
                      ),
                  ],
                ),
              ),
            if (_options.length < widget.maxOptions)
              TextButton.icon(
                onPressed: () =>
                    setState(() => _options.add(TextEditingController())),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(AppText.of(context).feedPollAddAnswer),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _several,
              onChanged: (value) => setState(() => _several = value),
              activeThumbColor: context.accents.accent,
              title: Text(
                AppText.of(context).feedPollSeveral,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            Text(widget.note, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(AppText.of(context).commonCancel),
        ),
        FilledButton(
          onPressed: !_ready
              ? null
              : () {
                  final options = _filled;
                  Navigator.of(context).pop(
                    ChannelPollDraft(
                      question: _question.text.trim(),
                      options: options,
                      // "Several" means up to all but one: letting somebody
                      // tick every box is not a poll, it is a list.
                      maxChoices: _several ? options.length - 1 : 1,
                    ),
                  );
                },
          child: Text(AppText.of(context).feedPollAsk),
        ),
      ],
    );
  }
}
