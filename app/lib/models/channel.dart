import 'dart:typed_data';

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
  });

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
        hasKey: hasKey ?? this.hasKey,
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

  /// Which version of the channel key sealed this post.
  ///
  /// Carried so a padlock can say *why*. A post from an epoch this device never
  /// held — published before it joined — is a different thing from one it is
  /// simply still waiting for, and telling somebody to keep waiting for a key
  /// that is never coming is worse than saying so.
  final int keyEpoch;
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
