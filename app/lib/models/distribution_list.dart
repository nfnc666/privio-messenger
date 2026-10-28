import 'package:flutter/foundation.dart';

/// A distribution list: one message, sent to several people as separate
/// one-to-one messages.
///
/// **It exists only on this device.** It is a name and some account ids in the
/// encrypted archive. Nothing about it is sent: each person gets an ordinary
/// message in their chat with this account, and cannot tell that anybody else
/// got the same one. The server sees one envelope to each of them at the same
/// moment, which is what sending them one by one quickly would look like too.
@immutable
class DistributionList {
  const DistributionList({required this.id, required this.name, required this.memberIds});

  final String id;
  final String name;
  final List<String> memberIds;

  static const int maxNameLength = 64;

  /// Every member costs a sealed envelope per send. Large enough for a team,
  /// small enough that a slip of the thumb is not a mass mailing.
  static const int maxMembers = 256;

  /// A name, and between one and [maxMembers] different people.
  static bool isValid(String name, List<String> memberIds) {
    final trimmed = name.trim();
    return trimmed.isNotEmpty &&
        trimmed.length <= maxNameLength &&
        memberIds.isNotEmpty &&
        memberIds.length <= maxMembers &&
        memberIds.toSet().length == memberIds.length;
  }

  DistributionList copyWith({String? name, List<String>? memberIds}) => DistributionList(
        id: id,
        name: name ?? this.name,
        memberIds: memberIds ?? this.memberIds,
      );

  Map<String, Object> toJson() => {'id': id, 'n': name, 'm': memberIds};

  /// Null for anything that is not a list this app would have made.
  static DistributionList? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['n'];
    final members = json['m'];
    if (id is! String || name is! String || members is! List) return null;
    final memberIds = members.whereType<String>().toList(growable: false);
    if (!isValid(name, memberIds)) return null;
    return DistributionList(id: id, name: name, memberIds: memberIds);
  }
}
