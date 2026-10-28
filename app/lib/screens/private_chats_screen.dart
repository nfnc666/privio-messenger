import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/conversation_controller.dart';
import '../l10n/app_localizations.dart';
import '../theme/privio_colors.dart';
import '../widgets/privio_back_button.dart';

/// The code that shows private chats: setting it, changing it, taking it
/// away, and what to do when it is forgotten.
///
/// The note at the top says what a private chat is and what it is not, in the
/// same breath, because the second half is the one people would otherwise get
/// wrong.
class PrivateChatsScreen extends StatefulWidget {
  const PrivateChatsScreen({super.key});

  @override
  State<PrivateChatsScreen> createState() => _PrivateChatsScreenState();
}

enum _CodeError { tooShort, mismatch, sameAsUnlock, wrongCode }

class _PrivateChatsScreenState extends State<PrivateChatsScreen> {
  final _current = TextEditingController();
  final _code = TextEditingController();
  final _confirm = TextEditingController();
  _CodeError? _error;

  @override
  void dispose() {
    _current.dispose();
    _code.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String _errorText(AppText text, _CodeError error) => switch (error) {
        _CodeError.tooShort =>
          text.privateChatsTooShort(ConversationController.privateCodeMinLength),
        _CodeError.mismatch => text.privateChatsMismatch,
        _CodeError.sameAsUnlock => text.privateChatsSameAsUnlock,
        _CodeError.wrongCode => text.privateChatsWrongCode,
      };

  void _done(String message) {
    _current.clear();
    _code.clear();
    _confirm.clear();
    setState(() => _error = null);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save(ConversationController conversations) async {
    final text = AppText.of(context);
    if (_code.text != _confirm.text) {
      setState(() => _error = _CodeError.mismatch);
      return;
    }
    final outcome = await conversations.setPrivateChatsCode(
      _code.text,
      current: conversations.hasPrivateChatsCode ? _current.text : null,
    );
    if (!mounted) return;
    switch (outcome) {
      case PrivateCodeOutcome.saved:
        _done(text.privateChatsSaved);
      case PrivateCodeOutcome.tooShort:
        setState(() => _error = _CodeError.tooShort);
      case PrivateCodeOutcome.sameAsUnlock:
        setState(() => _error = _CodeError.sameAsUnlock);
      case PrivateCodeOutcome.wrongCode:
        setState(() => _error = _CodeError.wrongCode);
    }
  }

  Future<void> _remove(ConversationController conversations) async {
    final text = AppText.of(context);
    final removed = await conversations.removePrivateChatsCode(_current.text);
    if (!mounted) return;
    if (removed) {
      _done(text.privateChatsRemoved);
    } else {
      setState(() => _error = _CodeError.wrongCode);
    }
  }

  Future<void> _forgot(ConversationController conversations) async {
    final text = AppText.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PrivioColors.surface,
        title: Text(text.privateChatsForgotTitle),
        content: Text(text.privateChatsForgotBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(text.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: PrivioColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(text.privateChatsForgotConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await conversations.deletePrivateChats();
    if (!mounted) return;
    _done(text.privateChatsDeleted);
  }

  Widget _field(TextEditingController controller, String label, Key key) => Padding(
        padding: const EdgeInsets.only(bottom: PrivioSpacing.md),
        child: TextField(
          key: key,
          controller: controller,
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          decoration: InputDecoration(labelText: label),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
        ),
      );

  @override
  Widget build(BuildContext context) {
    final state = PrivioScope.of(context);
    final theme = Theme.of(context);
    final text = AppText.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: const PrivioBackButton(),
        title: Text(text.privacyPrivateChats),
      ),
      body: ListenableBuilder(
        listenable: state.conversations,
        builder: (context, _) {
          final conversations = state.conversations;
          final hasCode = conversations.hasPrivateChatsCode;
          final error = _error;
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              PrivioSpacing.xxl,
              PrivioSpacing.xl,
              PrivioSpacing.xxl,
              PrivioSpacing.xxxl,
            ),
            children: [
              Text(
                text.privateChatsNote,
                style: theme.textTheme.bodyMedium?.copyWith(color: PrivioColors.textSecondary),
              ),
              const SizedBox(height: PrivioSpacing.xl),
              if (hasCode)
                _field(_current, text.privateChatsCurrentCode, const Key('private-current')),
              _field(
                _code,
                hasCode ? text.privateChatsNewCode : text.privateChatsCode,
                const Key('private-new'),
              ),
              _field(_confirm, text.privateChatsRepeat, const Key('private-repeat')),
              if (error != null) ...[
                Text(
                  _errorText(text, error),
                  style: theme.textTheme.bodySmall?.copyWith(color: PrivioColors.danger),
                ),
                const SizedBox(height: PrivioSpacing.md),
              ],
              FilledButton(
                key: const Key('private-save'),
                onPressed: () => _save(conversations),
                child: Text(hasCode ? text.privateChatsChange : text.privateChatsSave),
              ),
              if (hasCode) ...[
                const SizedBox(height: PrivioSpacing.xl),
                OutlinedButton(
                  key: const Key('private-remove'),
                  onPressed: () => _remove(conversations),
                  child: Text(text.privateChatsRemove),
                ),
                const SizedBox(height: PrivioSpacing.sm),
                Text(text.privateChatsRemoveNote, style: theme.textTheme.bodySmall),
                const SizedBox(height: PrivioSpacing.xl),
                TextButton(
                  key: const Key('private-forgot'),
                  onPressed: () => _forgot(conversations),
                  child: Text(text.privateChatsForgot),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
