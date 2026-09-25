import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../core/bot_controller.dart';
import '../l10n/app_localizations.dart';
import '../l10n/failure_text.dart';
import '../theme/accent.dart';
import '../theme/privio_colors.dart';
import '../widgets/privio_back_button.dart';
import '../widgets/settings_row.dart';
import 'bot_chat_screen.dart';
import 'botcreator_screen.dart';

/// Settings → Bots: the bots this account owns.
class BotsScreen extends StatefulWidget {
  const BotsScreen({super.key});

  @override
  State<BotsScreen> createState() => _BotsScreenState();
}

class _BotsScreenState extends State<BotsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = PrivioScope.of(context);
      final account = state.accountId;
      if (account != null) unawaited(state.bots.load(account));
    });
  }

  /// Asks for a bot's exact `@username` and opens its chat.
  Future<void> _openByUsername(BuildContext context) async {
    final field = TextEditingController();
    final text = AppText.of(context);
    final username = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(text.botChatOpenTitle),
        content: TextField(
          controller: field,
          autofocus: true,
          decoration: InputDecoration(hintText: text.botChatOpenHint, prefixText: '@'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(text.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(field.text),
            child: Text(text.botChatOpen),
          ),
        ],
      ),
    );
    field.dispose();
    final name = username?.trim().replaceFirst('@', '') ?? '';
    if (name.isEmpty || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        // Opened by name; the screen resolves it and says so if there is no
        // such bot, rather than this dialog guessing.
        builder: (_) => BotChatScreen(botId: '', username: name),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final controller = PrivioScope.of(context).bots;

    return Scaffold(
      appBar: AppBar(
        leading: const PrivioBackButton(),
        title: Text(text.botsTitle),
      ),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.only(bottom: PrivioSpacing.xxxl),
          children: [
            const SizedBox(height: PrivioSpacing.sm),
            if (controller.bots.isEmpty && controller.loaded) _Empty(text: text),
            if (controller.bots.isNotEmpty)
              SettingsSection(
                children: [
                  for (final bot in controller.bots)
                    SettingsRow(
                      icon: Icons.smart_toy_outlined,
                      label: bot.name,
                      subtitle: '@${bot.username}',
                      value: bot.disabled ? text.botsDisabled : null,
                      trailing: const BotBadge(),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => BotScreen(botId: bot.id)),
                      ),
                    ),
                ],
              ),
            SettingsSection(
              children: [
                SettingsRow(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: text.botChatOpenTitle,
                  // By exact name. There is no directory to browse, and that is
                  // deliberate: a list of every bot on a deployment is a list of
                  // every operator on it.
                  onTap: () => unawaited(_openByUsername(context)),
                ),
              ],
            ),
            SettingsSection(
              children: [
                SettingsRow(
                  icon: Icons.add_rounded,
                  label: text.botsCreate,
                  // Creating goes through the assistant rather than a form:
                  // the same guided walk somebody gets from any other
                  // messenger, and the one place a token is ever handed over.
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const BotCreatorScreen()),
                  ),
                ),
              ],
            ),
            _Note(text: text.botsNotEncrypted),
            if (controller.failure != null)
              _Note(text: controller.failure!.words(text), danger: true),
          ],
        ),
      ),
    );
  }
}

/// The mark that says an account is a program.
///
/// Everywhere a bot's name appears. Not decorative: somebody talking to a bot
/// is talking to whoever runs it, and that is a different thing from talking to
/// a person.
class BotBadge extends StatelessWidget {
  const BotBadge({super.key});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(left: PrivioSpacing.sm),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: context.accents.surface,
          borderRadius: const BorderRadius.all(PrivioRadius.pill),
        ),
        child: Text(
          AppText.of(context).botsBadge,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: context.accents.bright,
          ),
        ),
      );
}

/// One bot: what it is called, what it says it does, and its token.
class BotScreen extends StatelessWidget {
  const BotScreen({required this.botId, super.key});

  final String botId;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final controller = PrivioScope.of(context).bots;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final bot = controller.byId(botId);
        if (bot == null) {
          return Scaffold(
            appBar: AppBar(leading: const PrivioBackButton()),
            body: Center(child: Text(text.botsEmptyTitle)),
          );
        }

        return Scaffold(
          appBar: AppBar(
            leading: const PrivioBackButton(),
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: Text(bot.name, overflow: TextOverflow.ellipsis)),
                const BotBadge(),
              ],
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: PrivioSpacing.xxxl),
            children: [
              const SizedBox(height: PrivioSpacing.sm),
              SettingsSection(
                children: [
                  SettingsRow(label: text.botsUsernameLabel, value: '@${bot.username}'),
                  SettingsRow(
                    label: text.botsDescriptionLabel,
                    subtitle: bot.description,
                  ),
                  SettingsRow(
                    label: text.botsCommandsLabel,
                    value: '${bot.commands.length}',
                  ),
                ],
              ),
              SettingsSection(
                caption: text.botsToken,
                children: [
                  SettingsRow(
                    icon: Icons.vpn_key_outlined,
                    label: text.botsTokenNew,
                    enabled: !controller.busy,
                    onTap: () => unawaited(_issue(context, controller, bot.id)),
                  ),
                  SettingsRow(
                    label: text.botsTokenRevoke,
                    destructive: true,
                    enabled: !controller.busy,
                    onTap: () => unawaited(controller.revokeTokens(bot.id)),
                  ),
                ],
              ),
              _Note(text: text.botsTokenOnce),
              SettingsSection(
                children: [
                  SettingsRow(
                    label: text.botsDisable,
                    enabled: !controller.busy,
                    trailing: Switch.adaptive(
                      value: bot.disabled,
                      onChanged: controller.busy
                          ? null
                          : (off) => unawaited(controller.update(bot.id, disabled: off)),
                    ),
                  ),
                  SettingsRow(
                    label: text.botsDelete,
                    destructive: true,
                    enabled: !controller.busy,
                    onTap: () => unawaited(_delete(context, controller, bot)),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _issue(BuildContext context, BotController controller, String id) async {
    final token = await controller.issueToken(id);
    if (!context.mounted) return;
    if (token == null) {
      final text = AppText.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(controller.failure?.words(text) ?? text.failureUnexpected)),
      );
      return;
    }
    await showBotTokenSheet(context, token);
  }

  Future<void> _delete(BuildContext context, BotController controller, Bot bot) async {
    final text = AppText.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(text.botsDeleteConfirm(bot.username)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(text.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(text.botsDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    if (await controller.delete(bot.id) && context.mounted) Navigator.of(context).pop();
  }
}

/// Shows a token once, in a sheet that says so.
///
/// The token is passed in and held by this widget while it is on screen, and
/// nowhere else — not on the controller, not in the conversation with the
/// assistant, not in a log. Closing the sheet is the last time it exists on
/// this device unless somebody copied it.
Future<void> showBotTokenSheet(BuildContext context, String token) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: PrivioColors.surface,
      // Not dismissible by tapping away: the whole point is that it cannot be
      // reopened, so it should not be closable by accident.
      isDismissible: false,
      enableDrag: false,
      builder: (context) => _BotTokenSheet(token: token),
    );

class _BotTokenSheet extends StatelessWidget {
  const _BotTokenSheet({required this.token});

  final String token;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(PrivioSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(text.botsToken, style: theme.textTheme.titleMedium),
          const SizedBox(height: PrivioSpacing.md),
          Container(
            padding: const EdgeInsets.all(PrivioSpacing.md),
            decoration: const BoxDecoration(
              color: PrivioColors.surfaceRaised,
              borderRadius: BorderRadius.all(PrivioRadius.card),
            ),
            child: SelectableText(
              token,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ),
          const SizedBox(height: PrivioSpacing.md),
          Text(
            text.botsTokenOnce,
            style: theme.textTheme.bodySmall?.copyWith(color: PrivioColors.warning),
          ),
          const SizedBox(height: PrivioSpacing.lg),
          FilledButton.tonal(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: token));
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(text.botsTokenCopied)));
              }
            },
            child: Text(text.botsTokenCopy),
          ),
          const SizedBox(height: PrivioSpacing.sm),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(text.botsTokenDone),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});

  final AppText text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: PrivioSpacing.xxl,
        vertical: PrivioSpacing.xxxl,
      ),
      child: Column(
        children: [
          Icon(Icons.smart_toy_outlined, size: 48, color: context.accents.bright),
          const SizedBox(height: PrivioSpacing.lg),
          Text(text.botsEmptyTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: PrivioSpacing.sm),
          Text(
            text.botsEmptyBody,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: PrivioColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text, this.danger = false});

  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(
          PrivioSpacing.xl,
          PrivioSpacing.sm,
          PrivioSpacing.xl,
          PrivioSpacing.lg,
        ),
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: danger ? PrivioColors.danger : PrivioColors.textTertiary,
              ),
        ),
      );
}
