import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'failure.dart';

/// What a sticker upload has to be, mirroring `STICKER_LIMITS` in
/// `server/src/services/image_header.ts`.
///
/// Held here as well as there on purpose, and the duplication is the lesser
/// evil: the server is the one that decides, because a client can be modified
/// and a pack is shared with people running some other build. This copy only
/// exists so the app can say "that picture is too big" while the person is
/// still looking at the picker, rather than after a round trip. If the two ever
/// disagree the server wins, and the person sees the refusal it sent.
class StickerLimits {
  const StickerLimits._();

  static const int maxBytes = 512 * 1024;
  static const int maxEdge = 512;
  static const int minEdge = 32;

  /// The size limit in whole kilobytes, for the sentence that says it.
  static const int maxKilobytes = maxBytes ~/ 1024;
}

/// One picture in a pack.
@immutable
class StickerItem {
  const StickerItem({
    required this.id,
    required this.mediaId,
    required this.emoji,
    required this.position,
  });

  factory StickerItem.fromJson(Map<String, dynamic> json) => StickerItem(
        id: json['id'] as String,
        mediaId: json['mediaId'] as String,
        emoji: json['emoji'] as String? ?? '⭐',
        position: json['position'] as int? ?? 0,
      );

  final String id;
  final String mediaId;

  /// The character this stands in for: what a custom emoji falls back to on a
  /// client that does not have the pack, and how a sticker is searched for.
  final String emoji;
  final int position;

  @override
  bool operator ==(Object other) =>
      other is StickerItem &&
      other.id == id &&
      other.mediaId == mediaId &&
      other.emoji == emoji &&
      other.position == position;

  @override
  int get hashCode => Object.hash(id, mediaId, emoji, position);
}

/// Whether a pack holds stickers or custom emoji.
///
/// The same storage, deliberately different places in the picker: a sticker is
/// a message, a custom emoji goes *inside* one. Keeping it as one field rather
/// than two tables is what lets the rest of this file be written once.
enum StickerPackKind { sticker, emoji }

@immutable
class StickerPack {
  const StickerPack({
    required this.id,
    required this.kind,
    required this.title,
    required this.items,
    required this.installed,
    this.shareCode,
    this.shared = false,
    this.updatedAt,
  });

  factory StickerPack.fromJson(Map<String, dynamic> json) => StickerPack(
        id: json['id'] as String,
        kind: json['kind'] == 'emoji' ? StickerPackKind.emoji : StickerPackKind.sticker,
        title: json['title'] as String? ?? '',
        items: ((json['items'] as List<dynamic>?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(StickerItem.fromJson)
            .toList(growable: false),
        installed: json['installed'] as bool? ?? false,
        // Only ever present for the owner: the server strips it for everybody
        // else, so its presence is what "this is mine" means on this side.
        shareCode: json['shareCode'] as String?,
        shared: json['shared'] as bool? ?? false,
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toLocal(),
      );

  final String id;
  final StickerPackKind kind;
  final String title;
  final List<StickerItem> items;

  /// Whether this account has added the pack. Always false for one's own.
  final bool installed;

  /// The code that goes in a share link, or null when it is not shared — and
  /// also null for a pack somebody else owns, because the server never sends
  /// somebody else's code.
  final String? shareCode;

  /// Whether a live link exists. Separate from [shareCode] so a viewer can be
  /// told a pack is shared without being handed the capability to share it.
  final bool shared;
  final DateTime? updatedAt;

  /// Whether this account owns it: the server hands the code only to the owner.
  bool get isMine => !installed;

  @override
  bool operator ==(Object other) =>
      other is StickerPack &&
      other.id == id &&
      other.kind == kind &&
      other.title == title &&
      other.installed == installed &&
      other.shareCode == shareCode &&
      other.shared == shared &&
      listEquals(other.items, items);

  @override
  int get hashCode => Object.hash(id, kind, title, installed, shareCode, shared, items.length);
}

/// A sticker this account has used, or marked.
@immutable
class StickerUse {
  const StickerUse({
    required this.itemId,
    required this.packId,
    required this.mediaId,
    required this.emoji,
    required this.favourite,
    required this.usedAt,
  });

  factory StickerUse.fromJson(Map<String, dynamic> json) => StickerUse(
        itemId: json['itemId'] as String,
        packId: json['packId'] as String,
        mediaId: json['mediaId'] as String,
        emoji: json['emoji'] as String? ?? '⭐',
        favourite: json['favourite'] as bool? ?? false,
        usedAt: DateTime.tryParse(json['usedAt'] as String? ?? '')?.toLocal() ?? DateTime(1970),
      );

  final String itemId;
  final String packId;
  final String mediaId;
  final String emoji;
  final bool favourite;
  final DateTime usedAt;
}

/// This account's sticker and emoji packs, its favourites and its recents.
///
/// The same two rules as every other controller here, and for the same reason
/// — everything below belongs to an account and this object outlives none of
/// them:
///
/// 1. **Loaded per account.** [load] records the id it loaded for. Nothing is
///    carried across a switch; [signedOut] empties it.
/// 2. **A late answer is dropped.** Every request captures the account it was
///    made for and checks on completion that the controller is still on it. A
///    pack list that arrives after somebody switched accounts finishes into
///    nothing rather than showing one person's stickers to another.
///
/// Note what this does *not* hold: any image bytes. A pack is a list of media
/// ids; the pictures are fetched through the ordinary media route, which is
/// what keeps who-may-see-them a question the server answers.
class StickerController extends ChangeNotifier {
  StickerController(this._api);

  final PrivioApiClient _api;

  String? _accountId;
  List<StickerPack> _packs = const [];
  List<StickerUse> _uses = const [];
  bool _loaded = false;
  bool _busy = false;
  Failure? _failure;

  /// Sticker pictures already fetched, by media id.
  ///
  /// In memory and nowhere else, which is what makes the brief's "kept apart
  /// between accounts" true rather than merely intended: there is no file to
  /// leave behind, and [signedOut] empties the map, so a picture fetched by one
  /// account cannot be drawn for the next one. A picker scrolling over a
  /// hundred stickers would otherwise refetch every one of them on every
  /// rebuild.
  final Map<String, Uint8List> _images = {};

  /// Fetches in flight, so a grid that builds the same cell twice in one frame
  /// makes one request rather than two.
  final Map<String, Future<Uint8List?>> _fetching = {};

  String? get accountId => _accountId;

  /// Every pack, owned and installed, in the order the server returned.
  List<StickerPack> get packs => _packs;

  List<StickerPack> get myPacks =>
      _packs.where((pack) => pack.isMine).toList(growable: false);

  List<StickerPack> get installedPacks =>
      _packs.where((pack) => pack.installed).toList(growable: false);

  /// Packs holding stickers, in picker order.
  List<StickerPack> get stickerPacks =>
      _packs.where((pack) => pack.kind == StickerPackKind.sticker).toList(growable: false);

  /// Packs holding custom emoji.
  List<StickerPack> get emojiPacks =>
      _packs.where((pack) => pack.kind == StickerPackKind.emoji).toList(growable: false);

  /// Marked favourites, newest first.
  List<StickerUse> get favourites =>
      _uses.where((use) => use.favourite).toList(growable: false);

  /// Recently used, newest first, favourites included.
  List<StickerUse> get recents => _uses;

  bool get loaded => _loaded;

  /// Whether a write is in flight. Buttons disable on this, which is what
  /// stops the same pack being created twice by an impatient second tap.
  bool get busy => _busy;

  Failure? get failure => _failure;

  /// Finds a pack by id, or null. Used by the message list to answer "which
  /// pack does this sticker come from" without a round trip.
  StickerPack? packById(String id) {
    for (final pack in _packs) {
      if (pack.id == id) return pack;
    }
    return null;
  }

  /// Finds one item across every pack, or null when the pack is gone.
  ///
  /// Null is an ordinary answer, not an error: a pack can be deleted after a
  /// sticker from it was sent, and the message still has to render. What the
  /// screen draws then is the fallback, not a broken image.
  ({StickerPack pack, StickerItem item})? itemById(String itemId) {
    for (final pack in _packs) {
      for (final item in pack.items) {
        if (item.id == itemId) return (pack: pack, item: item);
      }
    }
    return null;
  }

  /// Reads everything for an account.
  Future<void> load(String accountId) async {
    if (_accountId != accountId) {
      _accountId = accountId;
      _packs = const [];
      _uses = const [];
      _images.clear();
      _fetching.clear();
      _loaded = false;
      _failure = null;
      notifyListeners();
    }

    try {
      final packs = await _api.stickerPacks();
      if (!_stillOn(accountId)) return;
      _packs = _packsOf(packs);

      final uses = await _api.stickerUses();
      if (!_stillOn(accountId)) return;
      _uses = ((uses['uses'] as List<dynamic>?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map(StickerUse.fromJson)
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

  /// Creates a pack and returns it, or null with [failure] set.
  Future<StickerPack?> createPack({
    required String title,
    required StickerPackKind kind,
  }) =>
      _write(() async {
        final json = await _api.createStickerPack(
          title: title,
          kind: kind == StickerPackKind.emoji ? 'emoji' : 'sticker',
        );
        final pack = StickerPack.fromJson(json);
        _packs = [..._packs, pack];
        return pack;
      });

  Future<StickerPack?> rename(String packId, String title) => _write(() async {
        final pack = StickerPack.fromJson(await _api.renameStickerPack(packId, title));
        _replace(pack);
        return pack;
      });

  /// Deletes a pack of this account's own.
  ///
  /// The server keeps the row and its images rather than erasing them, and
  /// that is deliberate: stickers from this pack are already in other people's
  /// conversations, and a deleted pack must not turn those messages into empty
  /// squares. What deleting does is unshare it and take it out of the picker.
  Future<bool> deletePack(String packId) async {
    final done = await _write(() async {
      await _api.deleteStickerPack(packId);
      _packs = _packs.where((pack) => pack.id != packId).toList(growable: false);
      _uses = _uses.where((use) => use.packId != packId).toList(growable: false);
      return true;
    });
    return done ?? false;
  }

  /// Turns a pack into a link. Returns the fresh code.
  ///
  /// The code comes back from the server rather than being invented here: a
  /// share button that produced a link the server did not know about would be
  /// a link that opens nothing.
  Future<String?> share(String packId) async {
    final pack = await _write(() async {
      final shared = StickerPack.fromJson(await _api.shareStickerPack(packId));
      _replace(shared);
      return shared;
    });
    return pack?.shareCode;
  }

  /// Revokes the link. Anybody who already installed the pack keeps it —
  /// revoking stops new installs, it does not reach into other people's apps.
  Future<bool> unshare(String packId) async {
    final done = await _write(() async {
      await _api.unshareStickerPack(packId);
      final existing = packById(packId);
      if (existing != null) {
        _replace(StickerPack(
          id: existing.id,
          kind: existing.kind,
          title: existing.title,
          items: existing.items,
          installed: existing.installed,
          updatedAt: existing.updatedAt,
        ));
      }
      return true;
    });
    return done ?? false;
  }

  /// Looks a shared pack up by its code without adding it.
  ///
  /// This is the preview the brief asks for: somebody handed a link sees what
  /// is in the pack before it lands in their picker.
  Future<StickerPack?> previewByCode(String code) => _write(() async {
        return StickerPack.fromJson(await _api.stickerPackByCode(code));
      });

  Future<StickerPack?> install(String packId, {String? code}) => _write(() async {
        final pack = StickerPack.fromJson(await _api.installStickerPack(packId, code: code));
        final existing = packById(packId);
        if (existing == null) {
          _packs = [..._packs, pack];
        } else {
          _replace(pack);
        }
        return pack;
      });

  Future<bool> uninstall(String packId) async {
    final done = await _write(() async {
      await _api.uninstallStickerPack(packId);
      _packs = _packs.where((pack) => pack.id != packId).toList(growable: false);
      _uses = _uses.where((use) => use.packId != packId).toList(growable: false);
      return true;
    });
    return done ?? false;
  }

  /// Uploads a picture and adds it to a pack.
  ///
  /// The bytes go up **unsealed**, which is the one thing about stickers worth
  /// being explicit about: a pack is handed out as a link, and somebody
  /// following a link holds no key of the author's. So a sticker is a public
  /// picture by construction, the sheet where a pack is shared says so, and
  /// nothing here touches the sealed path an attachment takes.
  Future<StickerItem?> addItem(
    String packId, {
    required List<int> bytes,
    required String emoji,
  }) async {
    // Checked here as well as on the server so the person hears about it while
    // they are still looking at the picture. The server checks again, from the
    // bytes rather than from anything this app claims — see uploadMedia.
    if (bytes.length > StickerLimits.maxBytes) {
      _failure = const Failure(FailureKind.stickerTooLarge);
      notifyListeners();
      return null;
    }

    return _write(() async {
      final upload = await _api.uploadMedia(bytes, sticker: true);
      final json = await _api.addStickerItem(packId, mediaId: upload.id, emoji: emoji);
      final item = StickerItem.fromJson(json);
      final pack = packById(packId);
      if (pack != null) _replace(_withItems(pack, [...pack.items, item]));
      return item;
    }, otherwise: FailureKind.couldNotSetPicture);
  }

  Future<bool> setItemEmoji(String packId, String itemId, String emoji) async {
    final done = await _write(() async {
      final item = StickerItem.fromJson(await _api.setStickerItemEmoji(packId, itemId, emoji));
      final pack = packById(packId);
      if (pack != null) {
        _replace(_withItems(
          pack,
          pack.items.map((each) => each.id == itemId ? item : each).toList(growable: false),
        ));
      }
      return true;
    });
    return done ?? false;
  }

  Future<bool> removeItem(String packId, String itemId) async {
    final done = await _write(() async {
      await _api.removeStickerItem(packId, itemId);
      final pack = packById(packId);
      if (pack != null) {
        _replace(_withItems(
          pack,
          pack.items.where((item) => item.id != itemId).toList(growable: false),
        ));
      }
      _uses = _uses.where((use) => use.itemId != itemId).toList(growable: false);
      return true;
    });
    return done ?? false;
  }

  /// Sets the whole order of a pack.
  ///
  /// The new order is applied locally first because a drag that snaps back
  /// while the request is in flight is unusable — and put back if the server
  /// refuses, which is the part that makes the optimism honest.
  Future<bool> reorder(String packId, List<String> itemIds) async {
    final pack = packById(packId);
    if (pack == null) return false;
    final previous = pack.items;

    final byId = {for (final item in pack.items) item.id: item};
    final reordered = <StickerItem>[
      for (final id in itemIds)
        if (byId[id] != null) byId[id]!,
    ];
    if (reordered.length != previous.length) return false;
    _replace(_withItems(pack, reordered));
    notifyListeners();

    final done = await _write(() async {
      await _api.reorderStickerItems(packId, itemIds);
      return true;
    });
    if (done ?? false) return true;

    final current = packById(packId);
    if (current != null) _replace(_withItems(current, previous));
    notifyListeners();
    return false;
  }

  /// Records that stickers were sent, which is what fills the recents row.
  ///
  /// Deliberately not awaited by its callers and deliberately silent: nobody
  /// needs to be told that a recents list did not update, and a send that
  /// reported an error because of it would be a send that looked broken when
  /// the message went through.
  Future<void> noteUsed(List<String> itemIds) async {
    if (itemIds.isEmpty) return;
    final account = _accountId;
    if (account == null) return;
    try {
      await _api.noteStickersUsed(itemIds);
      if (!_stillOn(account)) return;
      await _refreshUses(account);
    } on Object {
      // Nothing to say and nobody to say it to.
    }
  }

  Future<bool> setFavourite(String itemId, bool favourite) async {
    final done = await _write(() async {
      await _api.setStickerFavourite(itemId, favourite);
      final account = _accountId;
      if (account != null) await _refreshUses(account);
      return true;
    });
    return done ?? false;
  }

  /// A sticker's picture if it is already here, without fetching.
  ///
  /// Synchronous on purpose: a grid cell asks on every build, and a build that
  /// awaits is a build that cannot happen.
  Uint8List? imageOf(String mediaId) => _images[mediaId];

  /// Fetches a sticker's picture, or returns it from the cache.
  ///
  /// Unsealed, unlike every attachment: a pack is shared by link with people
  /// who hold no key of the author's, so there is nothing to open. Who may
  /// fetch it is decided by the server, which serves a sticker only to the
  /// pack's owner and to accounts that installed it.
  Future<Uint8List?> image(String mediaId) {
    final held = _images[mediaId];
    if (held != null) return Future.value(held);
    final running = _fetching[mediaId];
    if (running != null) return running;

    final account = _accountId;
    if (account == null) return Future.value(null);

    final fetch = () async {
      try {
        final bytes = await _api.downloadMedia(mediaId);
        // Dropped rather than kept if the account changed while it was in
        // flight: caching it would put one account's picture in the next
        // account's map, which is exactly what the map is meant not to do.
        if (!_stillOn(account)) return null;
        final held = Uint8List.fromList(bytes);
        _images[mediaId] = held;
        notifyListeners();
        return held;
      } on Object {
        // A picture that will not come is not an error worth a sentence: the
        // cell draws its fallback emoji, which is what the fallback is for.
        return null;
      } finally {
        _fetching.remove(mediaId);
      }
    }();
    _fetching[mediaId] = fetch;
    return fetch;
  }

  void clearFailure() {
    if (_failure == null) return;
    _failure = null;
    notifyListeners();
  }

  /// Forgets everything, on the way out of an account.
  void signedOut({bool notify = true}) {
    _accountId = null;
    _packs = const [];
    _uses = const [];
    _images.clear();
    _fetching.clear();
    _loaded = false;
    _busy = false;
    _failure = null;
    if (notify) notifyListeners();
  }

  // --- The shape every write has --------------------------------------------

  /// Runs a write with the busy flag, the account guard and the error mapping
  /// all in one place.
  ///
  /// Written once because there are a dozen of these and the interesting part
  /// of each is two lines. A dozen hand-rolled copies is a dozen chances to
  /// forget the `_stillOn` check in the `finally`, which is the one that
  /// matters: clearing the busy flag after an account switch unblocks a write
  /// somebody else never started.
  Future<T?> _write<T>(
    Future<T> Function() body, {
    FailureKind otherwise = FailureKind.couldNotSave,
  }) async {
    if (_busy) return null;
    final account = _accountId;
    if (account == null) {
      _failure = Failure(otherwise);
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
      _failure = _refusalOf(error) ?? Failure.server(error.message);
      return null;
    } on Object {
      if (!_stillOn(account)) return null;
      _failure = Failure(otherwise);
      return null;
    } finally {
      if (_stillOn(account)) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  /// The server's refusal codes, as cases this app has its own words for.
  ///
  /// The server's sentence is English and accurate; it is not this reader's
  /// language. Anything not in this list falls through to [Failure.server],
  /// which shows what arrived — better a sentence in the wrong language than
  /// a shrug.
  static Failure? _refusalOf(ApiException error) => switch (error.code) {
        'not_an_image' => const Failure(FailureKind.stickerNotAnImage),
        'unsupported_format' => const Failure(FailureKind.stickerAnimated),
        'too_large' => const Failure(FailureKind.stickerTooLarge),
        'dimensions_too_large' => const Failure(FailureKind.stickerTooWide),
        'dimensions_too_small' => const Failure(FailureKind.stickerTooSmall),
        'pack_full' => const Failure(FailureKind.stickerPackFull),
        'too_many_packs' => const Failure(FailureKind.stickerTooManyPacks),
        'pack_not_found' => const Failure(FailureKind.stickerPackNotFound),
        _ => null,
      };

  Future<void> _refreshUses(String account) async {
    final uses = await _api.stickerUses();
    if (!_stillOn(account)) return;
    _uses = ((uses['uses'] as List<dynamic>?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(StickerUse.fromJson)
        .toList(growable: false);
  }

  List<StickerPack> _packsOf(Map<String, dynamic> json) =>
      ((json['packs'] as List<dynamic>?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map(StickerPack.fromJson)
          .toList(growable: false);

  void _replace(StickerPack pack) {
    _packs = [
      for (final each in _packs)
        if (each.id == pack.id) pack else each,
    ];
  }

  static StickerPack _withItems(StickerPack pack, List<StickerItem> items) => StickerPack(
        id: pack.id,
        kind: pack.kind,
        title: pack.title,
        items: items,
        installed: pack.installed,
        shareCode: pack.shareCode,
        shared: pack.shared,
        updatedAt: pack.updatedAt,
      );

  bool _stillOn(String account) => _accountId == account;
}
