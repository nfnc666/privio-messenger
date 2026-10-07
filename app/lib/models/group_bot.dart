import 'package:flutter/foundation.dart';

import '../core/message_text.dart';

/// A bot that is in a group, and what it is allowed to do there.
///
/// Every member reads this list, not only admins: a device has to know which
/// bots are present before it can decide what to hand over to them, and
/// somebody writing in a group is entitled to know who ends up receiving it.
@immutable
class GroupBot {
  const GroupBot({
    required this.botId,
    required this.username,
    required this.displayName,
    this.maySend = false,
    this.mayModerate = false,
    this.mayRestrictMembers = false,
    this.mayManageInvites = false,
    this.readsAllMessages = false,
  });

  factory GroupBot.fromJson(Map<String, dynamic> json) => GroupBot(
        botId: json['botId'] as String,
        username: json['username'] as String,
        displayName: json['displayName'] as String?,
        maySend: json['maySend'] as bool? ?? false,
        mayModerate: json['mayModerate'] as bool? ?? false,
        mayRestrictMembers: json['mayRestrictMembers'] as bool? ?? false,
        mayManageInvites: json['mayManageInvites'] as bool? ?? false,
        readsAllMessages: json['readsAllMessages'] as bool? ?? false,
      );

  final String botId;
  final String username;
  final String? displayName;

  /// The four things a bot may be allowed to do, each its own decision.
  final bool maySend;
  final bool mayModerate;
  final bool mayRestrictMembers;
  final bool mayManageInvites;

  /// Whether members' devices hand this bot **every** new message rather than
  /// only the ones addressed to it.
  ///
  /// Not a key and not a decryption right: it widens what the senders choose
  /// to forward. Nothing gives a bot access to a message nobody handed over,
  /// and no setting reaches messages sent before it joined.
  final bool readsAllMessages;

  String get label => (displayName?.isNotEmpty ?? false) ? displayName! : username;
}

/// Whether a message written in a group is addressed to [bot].
///
/// This is the filter, and it runs **on the device that wrote the message**,
/// because that device is the only one holding the plaintext. The server
/// cannot do it: a group message is Signal ciphertext addressed to member
/// devices and the server holds no key that opens one.
///
/// Three ways to address a bot, and they are the three somebody would expect:
///
/// 1. a command — a message that starts with `/`;
/// 2. a mention of the bot by its exact `@username`;
/// 3. a reply to something the bot said.
///
/// [readsAllMessages] makes every message addressed to it. That is an admin's
/// explicit decision, shown in those words before it is turned on.
bool addressesBot(
  GroupBot bot,
  String text, {
  bool repliesToBot = false,
}) {
  if (bot.readsAllMessages) return true;
  if (repliesToBot) return true;

  final trimmed = text.trimLeft();
  // A command. Which bot a `/command` is for is ambiguous when a group holds
  // several, and the ambiguity is resolved the way it reads: `/help@name`
  // picks one, a bare `/help` goes to all of them. Telegram does the same, and
  // the alternative — guessing — would send somebody's command to a bot they
  // were not talking to.
  if (trimmed.startsWith('/')) {
    final firstWord = trimmed.split(RegExp(r'\s')).first;
    final at = firstWord.indexOf('@');
    if (at < 0) return true;
    return firstWord.substring(at + 1).toLowerCase() == bot.username.toLowerCase();
  }

  // A mention, found by the same tokenizer the chat draws them with, so a name
  // inside a URL or a code block is not one here either.
  return MessageText.split(text, links: false)
      .any((run) => run.kind == TextRunKind.mention && run.username == bot.username);
}
