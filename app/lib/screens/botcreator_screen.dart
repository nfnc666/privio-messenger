import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../l10n/app_localizations.dart';
import '../l10n/failure_text.dart';
import '../theme/accent.dart';
import '../theme/privio_colors.dart';
import '../widgets/privio_back_button.dart';
import 'bots_screen.dart';

/// The guided conversation with @botcreator.
///
/// A chat screen rather than a form, because that is what it is: the assistant
/// is a state machine on the server and this sends it one line at a time. It
/// supports whatever the server supports — `/newbot`, `/mybots`, `/setname`,
/// `/setdescription`, `/setcommands`, `/setuserpic`, `/token`, `/revoke`,
/// `/deletebot` — and this screen knows none of those words. It sends what was
/// typed and draws what comes back.
///
/// **The one thing it does know about is a token.** The assistant never puts one
/// in message text; it answers with an instruction to open the protected sheet,
/// and this screen honours it. So nothing that is rendered as chat history has
/// ever held a credential.
class BotCreatorScreen extends StatefulWidget {
  const BotCreatorScreen({super.key});

  @override
  State<BotCreatorScreen> createState() => _BotCreatorScreenState();
}

class _BotCreatorScreenState extends State<BotCreatorScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _warned = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final state = PrivioScope.of(context);
      final account = state.accountId;
      if (account != null) await state.bots.load(account);
      if (!mounted) return;
      // Said before the first message, not in a settings screen somewhere: a
      // bot chat is not end-to-end encrypted, and the moment that becomes true
      // for somebody is the moment they are about to write to one.
      await _warnOnce();
      if (mounted && state.bots.conversation.isEmpty) await _send('/start');
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _warnOnce() async {
    if (_warned) return;
    _warned = true;
    final text = AppText.of(context);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Text(text.botcreatorTitle),
            const BotBadge(),
          ],
        ),
        content: Text(text.botsNotEncrypted),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(text.botsUnderstood),
          ),
        ],
      ),
    );
  }

  Future<void> _send(String line) async {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return;
    _input.clear();

    final controller = PrivioScope.of(context).bots;
    final reply = await controller.say(trimmed);
    if (!mounted) return;

    _scrollToEnd();
    final botId = reply?.showTokenForBotId;
    if (botId != null) {
      final token = await controller.issueToken(botId);
      if (token != null && mounted) await showBotTokenSheet(context, token);
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final controller = PrivioScope.of(context).bots;

    return Scaffold(
      appBar: AppBar(
        leading: const PrivioBackButton(),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text.botcreatorTitle),
            const BotBadge(),
          ],
        ),
      ),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(PrivioSpacing.gutter),
                itemCount: controller.conversation.length,
                itemBuilder: (context, index) {
                  final line = controller.conversation[index];
                  return Align(
                    alignment: line.mine ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: PrivioSpacing.sm),
                      padding: const EdgeInsets.symmetric(
                        horizontal: PrivioSpacing.md,
                        vertical: PrivioSpacing.sm,
                      ),
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.78,
                      ),
                      decoration: BoxDecoration(
                        color: line.mine
                            ? context.accents.surface
                            : PrivioColors.surfaceRaised,
                        borderRadius: const BorderRadius.all(PrivioRadius.bubble),
                      ),
                      child: Text(line.text),
                    ),
                  );
                },
              ),
            ),
            if (controller.failure != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.gutter),
                child: Text(
                  controller.failure!.words(text),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: PrivioColors.danger),
                ),
              ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(PrivioSpacing.md),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        onSubmitted: (line) => unawaited(_send(line)),
                        decoration: InputDecoration(
                          hintText: text.botcreatorHint,
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: PrivioSpacing.sm),
                    IconButton(
                      onPressed: controller.busy
                          ? null
                          : () => unawaited(_send(_input.text)),
                      icon: const Icon(Icons.send_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
