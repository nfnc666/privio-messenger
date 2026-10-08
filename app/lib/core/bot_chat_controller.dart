import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'bot_controller.dart';
import 'failure.dart';

/// A button under a bot's message.
@immutable
class BotButton {
  const BotButton({required this.id, required this.label});

  factory BotButton.fromJson(Map<String, dynamic> json) => BotButton(
        id: json['id'] as String? ?? '',
        label: json['label'] as String? ?? '',
      );

  /// What goes back to the bot on a press. Never shown.
  final String id;

  /// What the person reads and decides on.
  final String label;
}

/// A poll a bot asked, as the person answering it sees it.
///
/// Plaintext like everything on the bot path, and **not anonymous to the
/// bot**: the bot is told who answered what. The card says so. The tally is
/// here only when the bot chose to show it and this person has answered or
/// can no longer answer — the server leaves it out otherwise rather than
/// sending zeros, so [counts] being null means "not yours to see", never
/// "nobody voted".
@immutable
class BotPoll {
  const BotPoll({
    required this.id,
    required this.question,
    required this.options,
    this.maxChoices = 1,
    this.showResults = false,
    this.closesAt,
    this.closed = false,
    this.myVotes = const {},
    this.counts,
    this.voters,
  });

  static BotPoll? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final options = ((raw['options'] as List<dynamic>?) ?? const []).whereType<String>().toList();
    // Fewer than two is not a poll the server would have stored. Drawn as the
    // message it came with rather than as a question with one answer.
    if (options.length < 2) return null;
    final counts = raw['counts'];
    return BotPoll(
      id: raw['id'] as int? ?? 0,
      question: raw['question'] as String? ?? '',
      options: options,
      maxChoices: raw['maxChoices'] as int? ?? 1,
      showResults: raw['showResults'] as bool? ?? false,
      closesAt: DateTime.tryParse(raw['closesAt'] as String? ?? '')?.toLocal(),
      closed: raw['closed'] as bool? ?? false,
      myVotes: ((raw['myVotes'] as List<dynamic>?) ?? const []).whereType<int>().toSet(),
      counts: counts is List ? counts.whereType<int>().toList(growable: false) : null,
      voters: raw['voters'] as int?,
    );
  }

  final int id;
  final String question;
  final List<String> options;
  final int maxChoices;

  /// Whether the bot lets the people answering see the tally.
  final bool showResults;
  final DateTime? closesAt;
  final bool closed;
  final Set<int> myVotes;
  final List<int>? counts;
  final int? voters;

  /// Closed by the bot, or past its time. The second is checked here too, so a
  /// card left open across the deadline stops offering a tap the server would
  /// refuse.
  bool get isClosed => closed || (closesAt != null && !closesAt!.isAfter(DateTime.now()));
  bool get takesSeveral => maxChoices > 1;
  bool get hasVoted => myVotes.isNotEmpty;
  bool get resultsVisible => counts != null;

  int countFor(int index) {
    final tally = counts;
    if (tally == null || index >= tally.length) return 0;
    return tally[index];
  }

  /// Against the busiest answer, as a channel poll draws it.
  double shareOf(int index) {
    final tally = counts;
    if (tally == null || tally.isEmpty) return 0;
    final highest = tally.fold(0, (a, b) => a > b ? a : b);
    if (highest == 0) return 0;
    return countFor(index) / highest;
  }
}

/// One message in a conversation with a bot.
@immutable
class BotMessage {
  const BotMessage({
    required this.id,
    required this.text,
    required this.mine,
    required this.sentAt,
    this.buttons = const [],
    this.pressed = const {},
    this.mediaId,
    this.mediaKind,
    this.fileName,
    this.byteSize,
    this.poll,
  });

  factory BotMessage.fromJson(Map<String, dynamic> json) => BotMessage(
        id: json['id'] as int,
        text: json['text'] as String? ?? '',
        mine: json['author'] == 'user',
        sentAt: DateTime.tryParse(json['sentAt'] as String? ?? '') ?? DateTime.now(),
        buttons: ((json['buttons'] as List<dynamic>?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(BotButton.fromJson)
            .toList(growable: false),
        pressed: ((json['pressed'] as List<dynamic>?) ?? const []).cast<String>().toSet(),
        mediaId: json['mediaId'] as String?,
        mediaKind: json['mediaKind'] as String?,
        fileName: json['fileName'] as String?,
        byteSize: json['byteSize'] as int?,
        poll: BotPoll.fromJson(json['poll']),
      );

  final int id;
  final String text;
  final bool mine;
  final DateTime sentAt;
  final List<BotButton> buttons;

  /// Which of this message's buttons this account has already pressed. Drawn as
  /// pressed and not offered again, because a second press does nothing — the
  /// server refuses it — and a button that looks live but is not is worse than
  /// one that looks spent.
  final Set<String> pressed;

  /// The attachment, when there is one.
  ///
  /// Null once the blob has expired and the server's sweeper has taken it: the
  /// message stays in the conversation as a message whose file is gone, which
  /// is the honest thing to draw rather than hiding the message.
  final String? mediaId;

  /// `image` or `file`. What to draw *before* the bytes are here — the app
  /// falls back to a file row when a declared image turns out not to decode.
  final String? mediaKind;
  final String? fileName;
  final int? byteSize;

  /// Whether this message *had* a file, which is not the same as still having
  /// one: an expired blob leaves the kind and the name behind, and that is how
  /// the screen knows to say the file is gone rather than drawing nothing.
  bool get hasMedia => mediaKind != null;
  bool get isImage => mediaKind == 'image';

  /// The poll this message carries, when it carries one.
  final BotPoll? poll;
}

/// A bot as somebody about to talk to it sees it.
@immutable
class BotProfile {
  const BotProfile({
    required this.id,
    required this.username,
    this.displayName,
    this.description,
    this.commands = const [],
    this.started = false,
    this.stopped = false,
  });

  factory BotProfile.fromJson(Map<String, dynamic> json) => BotProfile(
        id: json['id'] as String,
        username: json['username'] as String,
        displayName: json['displayName'] as String?,
        description: json['description'] as String?,
        commands: ((json['commands'] as List<dynamic>?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(BotCommand.fromJson)
            .toList(growable: false),
        started: json['started'] as bool? ?? false,
        stopped: json['stopped'] as bool? ?? false,
      );

  final String id;
  final String username;
  final String? displayName;
  final String? description;
  final List<BotCommand> commands;

  /// Whether this account has started the bot. Until it has, the bot cannot
  /// write at all, and the screen offers **Start** instead of a text field.
  final bool started;

  /// Whether this account stopped it. Different from never having started: the
  /// screen says so, because "stopped" is a thing somebody chose.
  final bool stopped;

  String get name => displayName ?? username;
}

/// One conversation with one bot.
///
/// Per account with the same late-answer guard as every other controller here:
/// an answer that arrives after a switch is dropped rather than drawn into
/// somebody else's chat. The bot is part of the identity of this controller, so
/// switching bots clears the conversation too — two bots' messages in one list
/// would be two operators' messages in one list.
class BotChatController extends ChangeNotifier {
  BotChatController(this._api);

  final PrivioApiClient _api;

  String? _accountId;
  String? _botId;
  BotProfile? _profile;
  List<BotMessage> _messages = const [];
  bool _busy = false;
  Failure? _failure;

  String? get accountId => _accountId;
  String? get botId => _botId;
  BotProfile? get profile => _profile;
  List<BotMessage> get messages => List.unmodifiable(_messages);
  bool get busy => _busy;
  Failure? get failure => _failure;

  /// Downloaded attachments, by media id.
  ///
  /// In memory only and cleared with the conversation, like everything else
  /// here: a bot's file is plaintext on the server already, and writing a copy
  /// to this device's cache would be a second place it lives for no gain.
  final Map<String, Uint8List> _media = {};

  /// The bytes of one attachment, downloaded once.
  ///
  /// Returns null when the object is gone — expired, or never downloadable —
  /// and the screen then draws the row as a file that cannot be fetched rather
  /// than retrying forever.
  Future<Uint8List?> mediaBytes(String mediaId) async {
    final cached = _media[mediaId];
    if (cached != null) return cached;
    final account = _accountId;
    if (account == null) return null;
    try {
      final bytes = Uint8List.fromList(await _api.downloadMedia(mediaId));
      if (!_stillOn(account)) return null;
      _media[mediaId] = bytes;
      return bytes;
    } on StaleSessionException {
      return null;
    } on Object {
      // No failure on the controller: one file that will not load is not a
      // reason to put a red sentence under the whole conversation.
      return null;
    }
  }

  /// Opens a bot by its **exact** username.
  ///
  /// Exact because there is no prefix search: a directory of every bot on a
  /// deployment is a directory of every operator on it. Answers null and sets a
  /// failure when there is no such bot, or when the name belongs to a person.
  Future<BotProfile?> openByUsername(String accountId, String username) async {
    return _load(accountId, () => _api.botByUsername(username.trim().toLowerCase()));
  }

  /// Opens a bot by id, for coming back to one already known.
  Future<BotProfile?> open(String accountId, String botId) async {
    return _load(accountId, () => _api.botProfile(botId));
  }

  Future<BotProfile?> _load(
    String accountId,
    Future<Map<String, dynamic>> Function() fetch,
  ) async {
    if (_accountId != accountId) {
      _accountId = accountId;
      _profile = null;
      _messages = const [];
      _media.clear();
      _failure = null;
    }
    _busy = true;
    notifyListeners();

    try {
      final profile = BotProfile.fromJson(await fetch());
      if (!_stillOn(accountId)) return null;
      if (_botId != profile.id) {
        // A different bot is a different conversation. Clearing rather than
        // appending: nothing from the last bot may appear under this one.
        _botId = profile.id;
        _messages = const [];
        _media.clear();
      }
      _profile = profile;
      _failure = null;
      await _refreshMessages(accountId, profile.id);
      return profile;
    } on StaleSessionException {
      return null;
    } on ApiException catch (error) {
      if (!_stillOn(accountId)) return null;
      _failure = error.statusCode == 404
          ? const Failure(FailureKind.botNotFound)
          : Failure.server(error.message);
      return null;
    } on Object {
      if (!_stillOn(accountId)) return null;
      _failure = const Failure(FailureKind.unreachableCheckConnection);
      return null;
    } finally {
      if (_stillOn(accountId)) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> _refreshMessages(String accountId, String botId) async {
    final json = await _api.botConversation(botId);
    if (!_stillOn(accountId) || _botId != botId) return;
    _messages = ((json['messages'] as List<dynamic>?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(BotMessage.fromJson)
        .toList(growable: false);
  }

  /// Refreshes the conversation and the profile, for a pull or a poll.
  Future<void> refresh() async {
    final account = _accountId;
    final bot = _botId;
    if (account == null || bot == null) return;
    await open(account, bot);
  }

  /// Presses **Start**. The bot may write from here on, and is sent `/start`.
  Future<bool> start() => _act((account, bot) async {
        await _api.startBot(bot);
        return true;
      });

  /// Presses **Stop**. The bot may not write, and nothing further reaches it.
  Future<bool> stop() => _act((account, bot) async {
        await _api.stopBot(bot);
        return true;
      });

  Future<bool> send(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return Future.value(false);
    return _act((account, bot) async {
      await _api.sendToBot(bot, trimmed);
      return true;
    });
  }

  /// Presses one button under one message.
  ///
  /// Recorded locally as pressed the moment the server accepts it, so the button
  /// stops inviting a tap that would do nothing.
  Future<bool> press(int messageId, String buttonId) => _act((account, bot) async {
        await _api.pressBotButton(bot, messageId, buttonId);
        return true;
      });

  /// Answers a poll, or changes or takes back an answer.
  ///
  /// The whole answer each time, as for a channel poll: [options] *is* the
  /// answer from now on, and an empty list takes it back. The reload after it
  /// is what draws the tally, when the bot lets this person see one.
  Future<bool> vote(int messageId, List<int> options) => _act((account, bot) async {
        await _api.voteBotPoll(bot, messageId, options);
        return true;
      });

  void clearFailure() {
    if (_failure == null) return;
    _failure = null;
    notifyListeners();
  }

  void signedOut({bool notify = true}) {
    _accountId = null;
    _botId = null;
    _profile = null;
    _messages = const [];
    _media.clear();
    _busy = false;
    _failure = null;
    if (notify) notifyListeners();
  }

  /// One write, then a reload.
  ///
  /// The reload is what draws the bot's answer: there is no push for the bot
  /// path, and a screen that only drew what it sent would look broken until
  /// somebody pulled to refresh. A bot that is slow means the answer arrives on
  /// the next refresh instead, which is the honest behaviour rather than a
  /// spinner that waits for something that may never come.
  Future<bool> _act(Future<bool> Function(String account, String bot) body) async {
    final account = _accountId;
    final bot = _botId;
    if (account == null || bot == null) {
      _failure = const Failure(FailureKind.couldNotSave);
      notifyListeners();
      return false;
    }
    if (_busy) return false;

    _busy = true;
    _failure = null;
    notifyListeners();

    try {
      await body(account, bot);
      if (!_stillOn(account)) return false;
      await _refreshMessages(account, bot);
      if (!_stillOn(account)) return false;
      final profile = BotProfile.fromJson(await _api.botProfile(bot));
      if (!_stillOn(account) || _botId != bot) return false;
      _profile = profile;
      _failure = null;
      return true;
    } on StaleSessionException {
      return false;
    } on ApiException catch (error) {
      if (!_stillOn(account)) return false;
      _failure = switch (error.code) {
        'not_contacted' => const Failure(FailureKind.botNotStarted),
        'bot_not_found' || 'message_not_found' => const Failure(FailureKind.botNotFound),
        'poll_closed' => const Failure(FailureKind.botPollClosed),
        _ => Failure.server(error.message),
      };
      return false;
    } on Object {
      if (!_stillOn(account)) return false;
      _failure = const Failure(FailureKind.unreachableCheckConnection);
      return false;
    } finally {
      if (_stillOn(account)) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  bool _stillOn(String account) => _accountId == account;
}
