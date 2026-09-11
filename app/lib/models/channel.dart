import 'package:flutter/foundation.dart';

/// What a member is allowed to do in a channel.
@immutable
class ChannelPermissions {
  const ChannelPermissions({
    this.canPost = false,
    this.canEditChannel = false,
    this.canDeletePosts = false,
    this.canManageMembers = false,
    this.canDeleteChannel = false,
  });

  factory ChannelPermissions.fromJson(Map<String, dynamic>? json) => json == null
      ? const ChannelPermissions()
      : ChannelPermissions(
          canPost: json['canPost'] as bool? ?? false,
          canEditChannel: json['canEditChannel'] as bool? ?? false,
          canDeletePosts: json['canDeletePosts'] as bool? ?? false,
          canManageMembers: json['canManageMembers'] as bool? ?? false,
          canDeleteChannel: json['canDeleteChannel'] as bool? ?? false,
        );

  final bool canPost;
  final bool canEditChannel;
  final bool canDeletePosts;
  final bool canManageMembers;
  final bool canDeleteChannel;

  Map<String, dynamic> toJson() => {
        'canPost': canPost,
        'canEditChannel': canEditChannel,
        'canDeletePosts': canDeletePosts,
        'canManageMembers': canManageMembers,
        'canDeleteChannel': canDeleteChannel,
      };
}

/// What a channel's invite link is allowed to do.
///
/// One link per channel, with three limits on it. Revoking is rotating: a new
/// code takes effect at once and every copy of the old one stops resolving,
/// wherever it was pasted. There is no list of past codes and no grace period.
@immutable
class ChannelInviteSettings {
  const ChannelInviteSettings({
    this.expiresAt,
    this.maxUses,
    this.uses = 0,
    this.needsApproval = false,
  });

  factory ChannelInviteSettings.fromJson(Map<String, dynamic>? json) => json == null
      ? const ChannelInviteSettings()
      : ChannelInviteSettings(
          expiresAt: DateTime.tryParse(json['expiresAt'] as String? ?? '')?.toLocal(),
          maxUses: (json['maxUses'] as num?)?.toInt(),
          uses: (json['uses'] as num?)?.toInt() ?? 0,
          needsApproval: json['needsApproval'] as bool? ?? false,
        );

  /// Null means it does not expire.
  final DateTime? expiresAt;

  /// Null means no limit.
  final int? maxUses;

  /// Joins through the link, not taps on it: somebody who opened it, looked at
  /// the preview and walked away has not used it up.
  final int uses;

  /// When on, the link puts people in a queue instead of in the channel.
  final bool needsApproval;

  bool get hasExpired => expiresAt != null && !expiresAt!.isAfter(DateTime.now());
  bool get isUsedUp => maxUses != null && uses >= maxUses!;

  /// Whether the link would let anybody in right now.
  bool get isSpent => hasExpired || isUsedUp;
}

/// What a channel adds up to, for whoever runs it.
///
/// Every number here is counted from rows that exist for their own reasons.
/// **There is no view count**, and that is a decision rather than a gap:
/// counting who has read a post, deduplicated, means a row per reader per
/// post — a record of what each person read, made by people who are only
/// reading. The screen says so.
@immutable
class ChannelStats {
  const ChannelStats({
    this.members = 0,
    this.posts = 0,
    this.scheduled = 0,
    this.reactions = 0,
    this.comments = 0,
    this.pollVoters = 0,
    this.silenced = 0,
    this.waiting = 0,
  });

  factory ChannelStats.fromJson(Map<String, dynamic> json) => ChannelStats(
        members: (json['members'] as num?)?.toInt() ?? 0,
        posts: (json['posts'] as num?)?.toInt() ?? 0,
        scheduled: (json['scheduled'] as num?)?.toInt() ?? 0,
        reactions: (json['reactions'] as num?)?.toInt() ?? 0,
        comments: (json['comments'] as num?)?.toInt() ?? 0,
        pollVoters: (json['pollVoters'] as num?)?.toInt() ?? 0,
        silenced: (json['silenced'] as num?)?.toInt() ?? 0,
        waiting: (json['waiting'] as num?)?.toInt() ?? 0,
      );

  final int members;
  final int posts;
  final int scheduled;
  final int reactions;
  final int comments;
  final int pollVoters;
  final int silenced;
  final int waiting;
}

/// Why somebody reported a channel.
///
/// A fixed set, never free text: a text box is where somebody pastes the
/// content they are reporting, which would put the very thing the encryption
/// protects into a column the server can read.
enum ChannelReportReason {
  spam('spam', 'Spam'),
  abuse('abuse', 'Abuse or harassment'),
  illegal('illegal', 'Illegal content'),
  impersonation('impersonation', 'Pretending to be someone else'),
  other('other', 'Something else');

  const ChannelReportReason(this.wire, this.label);

  final String wire;
  final String label;
}

/// Somebody waiting at the door of a channel that asks first.
@immutable
class ChannelJoinRequest {
  const ChannelJoinRequest({
    required this.accountId,
    required this.username,
    required this.requestedAt,
    this.displayName,
  });

  factory ChannelJoinRequest.fromJson(Map<String, dynamic> json) => ChannelJoinRequest(
        accountId: json['accountId'] as String? ?? '',
        username: json['username'] as String? ?? 'Deleted account',
        displayName: json['displayName'] as String?,
        requestedAt:
            DateTime.tryParse(json['requestedAt'] as String? ?? '')?.toLocal() ?? DateTime.now(),
      );

  final String accountId;
  final String username;
  final String? displayName;
  final DateTime requestedAt;

  String get label => displayName?.isNotEmpty == true ? displayName! : username;
}

enum ChannelVisibility { public, private }

@immutable
class ChannelInfo {
  const ChannelInfo({
    required this.id,
    required this.visibility,
    required this.title,
    this.handle,
    this.description,
    this.category,
    this.memberCount = 0,
    this.role,
    this.permissions = const ChannelPermissions(),
    this.inviteCode,
    this.restrictSaving = false,
    this.hasKey = false,
    this.keyEpoch = 1,
    this.hasCurrentKey = true,
    this.reactionEmojis = defaultReactionEmojis,
    this.commentsEnabled = false,
    this.invite = const ChannelInviteSettings(),
    this.avatarMediaId,
    this.avatarUpdatedAt,
    this.avatarToken,
  });

  /// What a channel offers until an admin changes it. Mirrors the server's
  /// column default, so a channel from before reactions existed still draws a
  /// bar rather than nothing.
  static const List<String> defaultReactionEmojis = ['👍', '❤️', '🔥', '👏', '😂', '😮'];

  final String id;
  final ChannelVisibility visibility;

  /// Plaintext for a public channel; decrypted from sealed metadata for a
  /// private one, or a placeholder until the key arrives.
  final String title;

  final String? handle;
  final String? description;
  final String? category;
  final int memberCount;

  /// Null when this account is not a member.
  final String? role;
  final ChannelPermissions permissions;

  /// Only returned to someone who may invite.
  final String? inviteCode;

  final bool restrictSaving;

  /// The emojis this channel offers under a post. Set by an admin; the server
  /// refuses a reaction that is not one of them.
  final List<String> reactionEmojis;

  /// What the invite link is allowed to do. Not the code itself — that is
  /// [inviteCode], handed to members only.
  final ChannelInviteSettings invite;

  /// Whether posts have threads under them.
  ///
  /// Off unless the owner turned it on. A channel is a broadcast; threads
  /// change what the thing is, so it is a decision rather than a default.
  final bool commentsEnabled;

  /// The channel's picture, as a media object id, or null for none.
  ///
  /// What the bytes behind it are depends on the channel, and the two are not
  /// interchangeable. A **public** channel's picture is stored unsealed,
  /// because it is drawn on the invite page and inside whatever messenger the
  /// link was pasted into, where nobody holds a key — its title, description
  /// and handle are already plaintext for exactly that reason. A **private**
  /// channel's is sealed with the channel key like its name, and needs both
  /// [avatarToken] and the key before it is a picture.
  final String? avatarMediaId;

  /// When it last changed, which is what a cache keys off. Without it,
  /// replacing a picture leaves every device showing the old one.
  final DateTime? avatarUpdatedAt;

  /// The download capability for a picture uploaded by an *older* build.
  ///
  /// Channel pictures are no longer sealed, so nothing sets this any more. It
  /// is still read out of `encryptedMetadata`, where those builds put it, so a
  /// channel that already has a sealed picture keeps showing it instead of
  /// losing it on upgrade. Setting a new picture clears it.
  final String? avatarToken;

  /// Whether this channel has a picture to fetch.
  ///
  /// No longer asks whether a key is in hand: channel pictures are not sealed.
  /// A private one is withheld by the server from anyone who is not a member,
  /// which is an authorisation rule rather than an encryption one.
  bool get hasAvatar => avatarMediaId != null;

  /// Whether this device holds any version of the key.
  final bool hasKey;

  /// Which version of the key this channel is on.
  ///
  /// It goes up when somebody is removed or leaves. Posts are answerable to the
  /// version that sealed them, so a member who was here before a removal reads
  /// both the old and the new; somebody who was removed reads neither, because
  /// they are no longer sent the feed at all.
  final int keyEpoch;

  /// Whether this device can read — and post — what is being published now.
  ///
  /// False while a rotation is in flight: the channel has moved on and this
  /// device is still waiting for the new key. The screen says so rather than
  /// falling back to the old one, which would publish to somebody who was
  /// just removed.
  final bool hasCurrentKey;

  /// True when this device is behind the channel and has to wait.
  bool get isAwaitingKey => isMember && !hasCurrentKey;

  /// "1 member", not "1 members".
  String get memberLabel => '$memberCount member${memberCount == 1 ? '' : 's'}';

  bool get isMember => role != null;
  bool get isPublic => visibility == ChannelVisibility.public;

  ChannelInfo copyWith({
    String? title,
    bool? hasKey,
    String? role,
    ChannelPermissions? permissions,
    int? memberCount,
    int? keyEpoch,
    bool? hasCurrentKey,
    String? avatarMediaId,
    DateTime? avatarUpdatedAt,
    String? avatarToken,
  }) =>
      ChannelInfo(
        id: id,
        visibility: visibility,
        keyEpoch: keyEpoch ?? this.keyEpoch,
        hasCurrentKey: hasCurrentKey ?? this.hasCurrentKey,
        title: title ?? this.title,
        handle: handle,
        description: description,
        category: category,
        memberCount: memberCount ?? this.memberCount,
        role: role ?? this.role,
        permissions: permissions ?? this.permissions,
        inviteCode: inviteCode,
        restrictSaving: restrictSaving,
        reactionEmojis: reactionEmojis,
        commentsEnabled: commentsEnabled,
        invite: invite,
        hasKey: hasKey ?? this.hasKey,
        avatarMediaId: avatarMediaId ?? this.avatarMediaId,
        avatarUpdatedAt: avatarUpdatedAt ?? this.avatarUpdatedAt,
        avatarToken: avatarToken ?? this.avatarToken,
      );

  /// The same channel with no picture.
  ///
  /// Its own method because [copyWith] cannot express it: every parameter
  /// there falls back to the current value when it is null, which is what makes
  /// a partial update readable and also what makes "set this to null"
  /// unsayable.
  ChannelInfo withoutAvatar() => ChannelInfo(
        id: id,
        visibility: visibility,
        keyEpoch: keyEpoch,
        hasCurrentKey: hasCurrentKey,
        title: title,
        handle: handle,
        description: description,
        category: category,
        memberCount: memberCount,
        role: role,
        permissions: permissions,
        inviteCode: inviteCode,
        restrictSaving: restrictSaving,
        reactionEmojis: reactionEmojis,
        commentsEnabled: commentsEnabled,
        invite: invite,
        hasKey: hasKey,
        avatarUpdatedAt: DateTime.now(),
      );
}

/// One post in a channel, after it has been opened.
@immutable
/// A file on its way into a channel, before anything has been sealed.
///
/// Separate from [ChannelAttachment] because they are different things: this is
/// what came off the picker and still has plaintext bytes, that is a pointer to
/// something already sealed and uploaded.
@immutable
class ChannelUpload {
  const ChannelUpload({required this.bytes, this.mimeType, this.name});

  final Uint8List bytes;

  /// A hint only. The real type is sniffed from the bytes when the file is
  /// sealed, because a file's name is what somebody typed and its first bytes
  /// are what it is.
  final String? mimeType;
  final String? name;
}

/// A file hanging off a channel post.
///
/// The bytes are sealed with the channel key of the post's epoch, so the server
/// holds ciphertext, and [token] is the capability that lets it be downloaded
/// at all. The token travels *inside* the sealed post: a member who can open
/// the post has it, and nobody else does — which is how a channel's attachment
/// is authorised without the server ever learning who is reading what.
///
/// A leaked token is not a leaked picture. It buys the ciphertext, and opening
/// that still needs the channel key.
@immutable
class ChannelAttachment {
  const ChannelAttachment({
    required this.mediaId,
    required this.token,
    required this.mimeType,
    required this.bytes,
    this.name,
  });

  static ChannelAttachment? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final mediaId = raw['id'];
    final token = raw['token'];
    if (mediaId is! String || token is! String) return null;
    return ChannelAttachment(
      mediaId: mediaId,
      token: token,
      mimeType: raw['type'] as String? ?? 'application/octet-stream',
      bytes: raw['bytes'] as int? ?? 0,
      name: raw['name'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': mediaId,
        'token': token,
        'type': mimeType,
        'bytes': bytes,
        if (name != null) 'name': name,
      };

  final String mediaId;
  final String token;
  final String mimeType;

  /// Size of the original file, for showing before anything is downloaded.
  final int bytes;
  final String? name;

  bool get isImage => mimeType.startsWith('image/');
}

class ChannelPost {
  const ChannelPost({
    required this.id,
    required this.body,
    required this.createdAt,
    this.authorUsername,
    this.pinned = false,
    this.opened = true,
    this.keyEpoch = 1,
    this.attachment,
    this.reactions = const {},
    this.myReactions = const {},
    this.editedAt,
    this.publishAt,
    this.commentCount = 0,
    this.poll,
  });

  final int id;

  /// The decrypted text, or an empty string when [opened] is false.
  final String body;

  final DateTime createdAt;
  final String? authorUsername;
  final bool pinned;

  /// False when this device has no key for the channel, or the post would not
  /// decrypt. Shown as a locked placeholder rather than hidden, so the reader
  /// knows something is there.
  final bool opened;

  /// The file on this post, once the post has been opened. Null when there is
  /// none, and also when the post could not be opened — a locked post shows a
  /// padlock, not a download button for something nobody can read.
  final ChannelAttachment? attachment;

  /// When the author last changed it, or null if they never did.
  ///
  /// Only set for a post people could already read. One still waiting for its
  /// time carries no mark, because nobody saw the earlier version.
  final DateTime? editedAt;

  /// When it becomes visible, for one that is not yet. Null for everything in
  /// an ordinary feed.
  final DateTime? publishAt;

  /// How many comments hang under it, so the feed can say so without
  /// fetching a thread for every post it scrolls past.
  final int commentCount;

  /// The poll on this post, or null for an ordinary one.
  final ChannelPoll? poll;

  bool get isEdited => editedAt != null;
  bool get isScheduled => publishAt != null;

  /// How many of each emoji are on this post.
  ///
  /// A total, and only a total: the server is never asked who reacted and
  /// never answers it. What it does hold is in migration 017, stated there
  /// rather than implied here.
  final Map<String, int> reactions;

  /// Which of them this device's account put there, so they can be taken back.
  final Set<String> myReactions;

  /// The same post with one reaction added or removed, for the answer the
  /// server gives a tap. Nothing else about the post changes.
  ChannelPost withReactions(Map<String, int> counts, Set<String> mine) => ChannelPost(
        id: id,
        body: body,
        createdAt: createdAt,
        authorUsername: authorUsername,
        pinned: pinned,
        opened: opened,
        keyEpoch: keyEpoch,
        attachment: attachment,
        reactions: counts,
        myReactions: mine,
        editedAt: editedAt,
        publishAt: publishAt,
        commentCount: commentCount,
        poll: poll,
      );

  /// The same post with a poll's tallies replaced, for the answer a vote gets.
  ChannelPost withPoll(ChannelPoll updated) => ChannelPost(
        id: id,
        body: body,
        createdAt: createdAt,
        authorUsername: authorUsername,
        pinned: pinned,
        opened: opened,
        keyEpoch: keyEpoch,
        attachment: attachment,
        reactions: reactions,
        myReactions: myReactions,
        editedAt: editedAt,
        publishAt: publishAt,
        commentCount: commentCount,
        poll: updated,
      );

  /// Which version of the channel key sealed this post.
  ///
  /// Carried so a padlock can say *why*. A post from an epoch this device never
  /// held — published before it joined — is a different thing from one it is
  /// simply still waiting for, and telling somebody to keep waiting for a key
  /// that is never coming is worse than saying so.
  final int keyEpoch;
}

/// The part of a poll the server never sees.
///
/// The question and the answers travel inside the post's sealed payload, with
/// its text. What the server holds is the shape — how many options, how many
/// may be picked, when it closes — because it is the thing enforcing a vote is
/// in range, and it does that without knowing what any option says.
@immutable
class ChannelPollContent {
  const ChannelPollContent({required this.question, required this.options});

  static ChannelPollContent? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final question = raw['q'];
    final options = raw['o'];
    if (question is! String || options is! List) return null;
    final labels = options.whereType<String>().toList();
    if (labels.length < 2) return null;
    return ChannelPollContent(question: question, options: labels);
  }

  Map<String, dynamic> toJson() => {'q': question, 'o': options};

  final String question;
  final List<String> options;
}

/// A poll as it is shown: the question from the sealed payload, the tallies
/// from the server.
@immutable
class ChannelPoll {
  const ChannelPoll({
    required this.content,
    required this.optionCount,
    this.maxChoices = 1,
    this.closesAt,
    this.counts = const {},
    this.voters = 0,
    this.myVotes = const {},
  });

  /// Null when this device has no key for the post: the shape is known, the
  /// question is not, and a poll nobody can read is not one to offer.
  final ChannelPollContent? content;

  final int optionCount;
  final int maxChoices;
  final DateTime? closesAt;

  /// Votes per option index. Options nobody picked are simply absent.
  final Map<int, int> counts;

  /// How many people took part — not the sum of [counts], because a poll that
  /// takes several answers counts one person several times.
  final int voters;

  /// Which options this account picked.
  final Set<int> myVotes;

  bool get isClosed => closesAt != null && !closesAt!.isAfter(DateTime.now());
  bool get takesSeveral => maxChoices > 1;
  bool get hasVoted => myVotes.isNotEmpty;

  int countFor(int index) => counts[index] ?? 0;

  /// The share of the vote an option has, between 0 and 1.
  ///
  /// Against the busiest option rather than the total: in a poll that takes
  /// several answers the totals add up to more than the people, and a bar
  /// running past its own track is worse than one that is only relative.
  double shareOf(int index) {
    final highest = counts.values.fold(0, (a, b) => a > b ? a : b);
    if (highest == 0) return 0;
    return countFor(index) / highest;
  }

  ChannelPoll withTally(Map<int, int> tally, int people, Set<int> mine) => ChannelPoll(
        content: content,
        optionCount: optionCount,
        maxChoices: maxChoices,
        closesAt: closesAt,
        counts: tally,
        voters: people,
        myVotes: mine,
      );
}

/// What a poll looks like before it is published.
@immutable
class ChannelPollDraft {
  const ChannelPollDraft({
    required this.question,
    required this.options,
    this.maxChoices = 1,
    this.closesAt,
  });

  final String question;
  final List<String> options;
  final int maxChoices;
  final DateTime? closesAt;
}

/// One comment under a post, after it has been opened.
///
/// Sealed with the same channel key as the post it hangs under, so a device
/// that cannot read the post cannot read the thread either — and a padlock in a
/// thread means the same thing it means in the feed.
@immutable
class ChannelComment {
  const ChannelComment({
    required this.id,
    required this.body,
    required this.createdAt,
    this.authorUsername,
    this.authorAccountId,
    this.opened = true,
  });

  final int id;
  final String body;
  final DateTime createdAt;
  final String? authorUsername;

  /// Needed to silence somebody from the thread they are speaking in, which is
  /// where an admin actually notices they should be.
  final String? authorAccountId;

  /// False when this device has no key for it. Shown as a padlock rather than
  /// hidden, so a gap in a conversation looks like a gap.
  final bool opened;
}

/// Someone an admin has stopped speaking in a channel.
@immutable
class ChannelBan {
  const ChannelBan({required this.accountId, required this.username, required this.since});

  factory ChannelBan.fromJson(Map<String, dynamic> json) => ChannelBan(
        accountId: json['accountId'] as String? ?? '',
        username: json['username'] as String? ?? 'Deleted account',
        since: DateTime.tryParse(json['since'] as String? ?? '')?.toLocal() ?? DateTime.now(),
      );

  final String accountId;
  final String username;
  final DateTime since;
}

/// Someone in a channel, with what they may do in it.
@immutable
class ChannelMember {
  const ChannelMember({
    required this.id,
    required this.username,
    this.displayName,
    this.role = 'subscriber',
    this.permissions = const ChannelPermissions(),
  });

  factory ChannelMember.fromJson(Map<String, dynamic> json) => ChannelMember(
        id: json['id'] as String,
        username: json['username'] as String? ?? '',
        displayName: json['displayName'] as String?,
        role: json['role'] as String? ?? 'subscriber',
        permissions: ChannelPermissions.fromJson(
          json['permissions'] as Map<String, dynamic>?,
        ),
      );

  final String id;
  final String username;
  final String? displayName;
  final String role;
  final ChannelPermissions permissions;

  bool get isOwner => role == 'owner';
  bool get isAdmin => role == 'admin' || isOwner;

  String get label => displayName?.isNotEmpty == true ? displayName! : username;

  ChannelMember copyWith({String? role, ChannelPermissions? permissions}) => ChannelMember(
        id: id,
        username: username,
        displayName: displayName,
        role: role ?? this.role,
        permissions: permissions ?? this.permissions,
      );
}

/// What a Privio join link points at.
enum InviteKind { channel, group }

/// An invite link taken apart.
///
/// It holds only the code, because that is all the link holds: the key that
/// opens the channel's posts is delivered separately, device to device.
@immutable
class ChannelInvite {
  const ChannelInvite({required this.code, required this.kind});

  final String code;
  final InviteKind kind;
}

/// What an incoming link resolves to before anything has been fetched.
///
/// Two shapes, because a link names a channel in two different ways and the
/// difference matters. A **code** is a capability: holding it is what lets
/// somebody into a private channel. A **handle** is a name: it is how a public
/// channel is searched for, and a link that carries one grants nothing at all.
///
/// That is why a public channel's link is its handle. The old form put an
/// invite code into every public link, which meant a link printed on a poster
/// was a capability anybody could read off it.
sealed class ChannelLinkTarget {
  const ChannelLinkTarget();
}

/// A private invitation, or an older link of any kind.
class ChannelLinkByCode extends ChannelLinkTarget {
  const ChannelLinkByCode({required this.code, required this.kind});

  final String code;
  final InviteKind kind;
}

/// A public channel, named.
class ChannelLinkByHandle extends ChannelLinkTarget {
  const ChannelLinkByHandle(this.handle);

  final String handle;
}
