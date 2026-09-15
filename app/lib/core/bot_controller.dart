import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'failure.dart';

/// One command a bot publishes.
@immutable
class BotCommand {
  const BotCommand({required this.command, required this.description});

  factory BotCommand.fromJson(Map<String, dynamic> json) => BotCommand(
        command: json['command'] as String? ?? '',
        description: json['description'] as String? ?? '',
      );

  final String command;
  final String description;

  Map<String, String> toJson() => {'command': command, 'description': description};
}

/// A bot this account owns.
///
/// Note what is **not** here: the token. It is returned once, by the route that
/// issues it, and held only long enough to be shown in the sheet that shows it.
/// A field on this object would be a token in memory for the life of a screen.
@immutable
class Bot {
  const Bot({
    required this.id,
    required this.username,
    this.displayName,
    this.description,
    this.commands = const [],
    this.disabled = false,
  });

  factory Bot.fromJson(Map<String, dynamic> json) => Bot(
        id: json['id'] as String,
        username: json['username'] as String,
        displayName: json['displayName'] as String?,
        description: json['description'] as String?,
        commands: ((json['commands'] as List<dynamic>?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(BotCommand.fromJson)
            .toList(growable: false),
        disabled: json['disabled'] as bool? ?? false,
      );

  final String id;
  final String username;
  final String? displayName;
  final String? description;
  final List<BotCommand> commands;
  final bool disabled;

  String get name => displayName ?? username;
}

/// One reply from @botcreator, and what it asks the app to do.
@immutable
class AssistantReply {
  const AssistantReply({required this.text, this.showTokenForBotId, this.openBots = false});

  factory AssistantReply.fromJson(Map<String, dynamic> json) {
    final action = json['action'] as Map<String, dynamic>?;
    return AssistantReply(
      text: json['text'] as String? ?? '',
      // A token never travels in the message text. The assistant asks the app
      // to open its protected sheet instead, and the sheet fetches the token
      // itself — so nothing that is rendered as chat history ever held one.
      showTokenForBotId:
          action?['kind'] == 'showToken' ? (action?['botId'] as String?) : null,
      openBots: action?['kind'] == 'openBots',
    );
  }

  final String text;
  final String? showTokenForBotId;
  final bool openBots;
}

/// One line in the guided conversation, as the screen draws it.
@immutable
class AssistantLine {
  const AssistantLine({required this.text, required this.mine, this.showTokenForBotId});

  final String text;
  final bool mine;
  final String? showTokenForBotId;
}

/// This account's bots, and the conversation with @botcreator.
///
/// Per account with a late-answer guard, like every other controller here: a
/// bot belongs to an owner, and an answer that arrives after a switch is
/// dropped rather than applied.
class BotController extends ChangeNotifier {
  BotController(this._api);

  final PrivioApiClient _api;

  String? _accountId;
  List<Bot> _bots = const [];
  final List<AssistantLine> _conversation = [];
  bool _loaded = false;
  bool _busy = false;
  Failure? _failure;

  String? get accountId => _accountId;
  List<Bot> get bots => _bots;
  List<AssistantLine> get conversation => List.unmodifiable(_conversation);
  bool get loaded => _loaded;
  bool get busy => _busy;
  Failure? get failure => _failure;

  Bot? byId(String id) {
    for (final bot in _bots) {
      if (bot.id == id) return bot;
    }
    return null;
  }

  Future<void> load(String accountId) async {
    if (_accountId != accountId) {
      _accountId = accountId;
      _bots = const [];
      _conversation.clear();
      _loaded = false;
      _failure = null;
      notifyListeners();
    }

    try {
      final json = await _api.bots();
      if (!_stillOn(accountId)) return;
      _bots = ((json['bots'] as List<dynamic>?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map(Bot.fromJson)
          .toList(growable: false);
      _loaded = true;
      _failure = null;
    } on StaleSessionException {
      return;
    } on Object catch (error) {
      if (!_stillOn(accountId)) return;
      _failure = Failure.of(error, FailureKind.unreachable);
    }
    notifyListeners();
  }

  Future<Bot?> create({required String name, required String username}) =>
      _write(() async {
        final bot = Bot.fromJson(await _api.createBot(name: name, username: username));
        _bots = [..._bots, bot];
        return bot;
      });

  Future<bool> update(
    String id, {
    String? name,
    String? description,
    List<BotCommand>? commands,
    bool? disabled,
  }) async {
    final done = await _write(() async {
      final bot = Bot.fromJson(
        await _api.updateBot(
          id,
          name: name,
          description: description,
          commands: commands?.map((each) => each.toJson()).toList(growable: false),
          disabled: disabled,
        ),
      );
      _bots = [
        for (final each in _bots)
          if (each.id == bot.id) bot else each,
      ];
      return true;
    });
    return done ?? false;
  }

  Future<bool> delete(String id) async {
    final done = await _write(() async {
      await _api.deleteBot(id);
      _bots = _bots.where((bot) => bot.id != id).toList(growable: false);
      return true;
    });
    return done ?? false;
  }

  /// Issues a token and hands it straight back to the caller.
  ///
  /// **Not stored on this object.** The sheet that shows it holds it for as
  /// long as it is on screen and then lets it go. A field here would be a
  /// credential kept alive for the life of a screen that has moved on.
  Future<String?> issueToken(String id) async {
    final token = await _write(() async {
      final json = await _api.issueBotToken(id);
      final value = json['token'] as String?;
      if (value == null) throw const FormatException('no token in the answer');
      return value;
    });
    return token;
  }

  Future<bool> revokeTokens(String id) async {
    final done = await _write(() async {
      await _api.revokeBotTokens(id);
      return true;
    });
    return done ?? false;
  }

  /// Sends one line to @botcreator and records both halves.
  ///
  /// The conversation is held here rather than in the screen so it survives the
  /// screen being closed and reopened — somebody halfway through `/newbot` who
  /// checks a message should not come back to an empty transcript. It is
  /// cleared on an account switch like everything else.
  Future<AssistantReply?> say(String text) => _write(() async {
        _conversation.add(AssistantLine(text: text, mine: true));
        notifyListeners();

        final reply = AssistantReply.fromJson(await _api.askBotCreator(text));
        _conversation.add(
          AssistantLine(
            text: reply.text,
            mine: false,
            showTokenForBotId: reply.showTokenForBotId,
          ),
        );
        // Creating or deleting a bot inside the conversation changes the list,
        // and the screen behind it should not be stale when it is reopened.
        await load(_accountId!);
        return reply;
      });

  void clearFailure() {
    if (_failure == null) return;
    _failure = null;
    notifyListeners();
  }

  void signedOut({bool notify = true}) {
    _accountId = null;
    _bots = const [];
    _conversation.clear();
    _loaded = false;
    _busy = false;
    _failure = null;
    if (notify) notifyListeners();
  }

  Future<T?> _write<T>(Future<T> Function() body) async {
    if (_busy) return null;
    final account = _accountId;
    if (account == null) {
      _failure = const Failure(FailureKind.couldNotSave);
      notifyListeners();
      return null;
    }

    _busy = true;
    _failure = null;
    notifyListeners();

    try {
      final result = await body();
      if (!_stillOn(account)) return null;
      _failure = null;
      return result;
    } on StaleSessionException {
      return null;
    } on ApiException catch (error) {
      if (!_stillOn(account)) return null;
      _failure = error.code == 'username_taken'
          ? const Failure(FailureKind.usernameTaken)
          : Failure.server(error.message);
      return null;
    } on Object {
      if (!_stillOn(account)) return null;
      _failure = const Failure(FailureKind.unreachable);
      return null;
    } finally {
      if (_stillOn(account)) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  bool _stillOn(String account) => _accountId == account;
}
