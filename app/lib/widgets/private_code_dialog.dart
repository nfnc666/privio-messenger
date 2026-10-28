import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../l10n/app_localizations.dart';
import '../theme/privio_colors.dart';

/// Asks for the private-chats code and shows the private chats if it is the
/// right one. Returns whether they are on show afterwards.
///
/// A wrong code says so and nothing else: not whether there are any private
/// chats, and not how many.
Future<bool> showPrivateChatsWithCode(BuildContext context) async {
  final state = PrivioScope.of(context);
  final text = AppText.of(context);
  final code = await showDialog<String>(
    context: context,
    builder: (_) => const _PrivateCodeDialog(),
  );
  if (code == null || code.isEmpty || !context.mounted) return false;
  final shown = await state.conversations.showPrivateChats(code);
  if (!shown && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text.privateChatsWrongCode)),
    );
  }
  return shown;
}

/// Stateful so the field's controller lives exactly as long as the dialog.
/// Disposed when the call returned, it was still being drawn by the closing
/// animation.
class _PrivateCodeDialog extends StatefulWidget {
  const _PrivateCodeDialog();

  @override
  State<_PrivateCodeDialog> createState() => _PrivateCodeDialogState();
}

class _PrivateCodeDialogState extends State<_PrivateCodeDialog> {
  final _field = TextEditingController();

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    return AlertDialog(
      backgroundColor: PrivioColors.surface,
      title: Text(text.privateChatsEnterCode),
      content: TextField(
        key: const Key('private-code-field'),
        controller: _field,
        obscureText: true,
        autofocus: true,
        enableSuggestions: false,
        autocorrect: false,
        decoration: InputDecoration(hintText: text.privateChatsCode),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(text.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_field.text),
          child: Text(text.privateChatsShow),
        ),
      ],
    );
  }
}
