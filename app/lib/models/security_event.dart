import 'package:flutter/foundation.dart';

/// Something that happened to this account's security, as a fact rather than a
/// sentence.
///
/// The same rule the chat's [SystemNotice] follows, and for the same reason:
/// a stored sentence is written in whatever language the app was set to at the
/// time and has no way to change its mind years later. What is stored is the
/// event; the words are built when they are drawn, in the language of whoever
/// is looking. See `l10n/security_event_text.dart`.
enum SecurityEventKind {
  /// A device was linked to this account. Carries [SecurityEvent.subject] —
  /// the device's name, which the user chose.
  deviceAdded,

  /// A device was signed out, from here or from elsewhere.
  deviceRemoved,

  /// The account password was changed.
  ///
  /// The server has the route and revokes every other session when it is used;
  /// **no screen in the app calls it yet**, so this value is never written
  /// today. It is here rather than added later so that a log written by the
  /// version that does gain the screen reads correctly on this one.
  passwordChanged,
  twoFactorEnabled,
  twoFactorDisabled,

  /// The encrypted archive was restored onto this device.
  backupRestored,

  phoneLinked,
  phoneRemoved,

  proxyEnabled,
  proxyDisabled,

  /// A contact's identity key is not the one that was pinned. **The one event
  /// here that can mean somebody is reading the conversation**, so it is the
  /// one the screen marks.
  contactKeyChanged,

  /// The user compared a safety number and said it matched.
  contactVerified,

  /// The user withdrew a verification they had made.
  contactVerificationCleared,

  /// The screen lock was set, changed or removed.
  screenLockChanged,

  /// The duress code was set or removed.
  duressCodeChanged,
}

/// One line in the security activity list.
///
/// **Deliberately thin.** There is no IP address, no city, no user agent and no
/// message content — see `docs/metadata-privacy-review.md` for why a security
/// log that records where you were is a tracking log that happens to be called
/// something else. [subject] is a name the user already knows (a device they
/// named, a contact they have a chat with) and nothing else ever goes in it.
@immutable
class SecurityEvent {
  const SecurityEvent({required this.kind, required this.at, this.subject});

  final SecurityEventKind kind;

  /// When, on this device's clock. Local time; never sent anywhere.
  final DateTime at;

  /// A device name or a contact's display name, where the sentence needs one.
  /// Never a phone number, never an account id, never a token.
  final String? subject;

  /// Whether this is the kind of event that should stand out.
  ///
  /// Only two qualify: a contact's key changing, which is what a server
  /// inserting itself looks like, and the second factor being switched off.
  /// Marking more than that would make the mark mean nothing.
  bool get isWarning =>
      kind == SecurityEventKind.contactKeyChanged ||
      kind == SecurityEventKind.twoFactorDisabled;

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'at': at.toIso8601String(),
        if (subject != null) 'subject': subject,
      };

  /// Null for a row this build does not understand — a log written by a newer
  /// version, read by an older one. Dropping it is right: a security screen
  /// must not draw a line it cannot explain.
  static SecurityEvent? fromJson(Map<String, dynamic> json) {
    final kind = SecurityEventKind.values
        .where((value) => value.name == json['kind'])
        .firstOrNull;
    final at = DateTime.tryParse(json['at'] as String? ?? '');
    if (kind == null || at == null) return null;
    return SecurityEvent(kind: kind, at: at, subject: json['subject'] as String?);
  }
}
