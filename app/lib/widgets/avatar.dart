import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/privio_colors.dart';

/// A circular avatar with the contact's initials and an optional presence dot.
///
/// Profile photos are end-to-end encrypted like everything else, so until one
/// has been fetched and decrypted this is what the list shows.
class PrivioAvatar extends StatelessWidget {
  const PrivioAvatar({
    required this.label,
    super.key,
    this.size = 44,
    this.seed = 0,
    this.presence = Presence.hidden,
    this.isGroup = false,
  });

  final String label;
  final double size;
  final int seed;
  final Presence presence;
  final bool isGroup;

  static const List<Color> _tints = [
    Color(0xFF1F2937),
    Color(0xFF14342A),
    Color(0xFF2A1F3D),
    Color(0xFF3D2A1F),
    Color(0xFF1F2E3D),
    Color(0xFF33203A),
    Color(0xFF203A2F),
    Color(0xFF3A2020),
  ];

  String get _initials {
    final parts = label.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    final first = parts.first.substring(0, 1).toUpperCase();
    if (parts.length == 1) return first;
    return first + parts.last.substring(0, 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final tint = _tints[seed % _tints.length];
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: isGroup
                ? Icon(Icons.group_rounded, size: size * 0.5, color: PrivioColors.textSecondary)
                : Text(
                    _initials,
                    style: TextStyle(
                      fontSize: size * 0.36,
                      fontWeight: FontWeight.w600,
                      color: PrivioColors.textPrimary,
                    ),
                  ),
          ),
          if (presence == Presence.online)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: size * 0.28,
                height: size * 0.28,
                decoration: BoxDecoration(
                  color: PrivioColors.accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: PrivioColors.background, width: size * 0.05),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
