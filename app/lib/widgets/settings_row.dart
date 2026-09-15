import 'package:flutter/material.dart';

import '../theme/privio_colors.dart';

/// One row inside a [SettingsSection]: icon, label, optional value, chevron.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    required this.label,
    super.key,
    this.icon,
    this.value,
    this.onTap,
    this.trailing,
    this.destructive = false,
    this.iconTint,
    this.subtitle,
    this.enabled = true,
  });

  final String label;
  final IconData? icon;

  /// When set, the icon sits in a filled rounded tile of this colour rather
  /// than loose in the row. The channel screens use it; the rest of settings
  /// does not, so it stays opt-in.
  final Color? iconTint;

  /// A second line under the label, for a row whose meaning needs one.
  final String? subtitle;

  /// A row that is shown but cannot be used — a permission somebody lacks,
  /// rather than a row hidden so they cannot tell it exists.
  final bool enabled;
  final String? value;
  final VoidCallback? onTap;
  final Widget? trailing;

  /// Destructive rows drop the icon and colour the label, as in the mockups.
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colour = destructive
        ? PrivioColors.danger
        : enabled
            ? PrivioColors.textPrimary
            : PrivioColors.textTertiary;

    return InkWell(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: PrivioSpacing.lg,
          vertical: PrivioSpacing.md + 2,
        ),
        child: Row(
          children: [
            if (icon != null && !destructive) ...[
              if (iconTint != null)
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: iconTint,
                    borderRadius: BorderRadius.circular(PrivioSpacing.sm),
                  ),
                  child: Icon(icon, size: 18, color: Colors.white),
                )
              else
                Icon(icon, size: 20, color: PrivioColors.textSecondary),
              const SizedBox(width: PrivioSpacing.md),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(color: colour),
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: PrivioColors.textTertiary),
                      ),
                    ),
                ],
              ),
            ),
            if (value != null)
              Padding(
                padding: const EdgeInsets.only(left: PrivioSpacing.sm),
                child: Text(
                  value!,
                  style: theme.textTheme.bodySmall?.copyWith(color: PrivioColors.textSecondary),
                ),
              ),
            if (trailing != null) trailing!,
            if (trailing == null && onTap != null && !destructive && enabled)
              const Padding(
                padding: EdgeInsets.only(left: PrivioSpacing.sm),
                child: Icon(Icons.chevron_right_rounded, size: 20, color: PrivioColors.textTertiary),
              ),
          ],
        ),
      ),
    );
  }
}

/// A grouped card of [SettingsRow]s with hairline separators.
class SettingsSection extends StatelessWidget {
  const SettingsSection({required this.children, super.key, this.caption});

  final List<Widget> children;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (caption != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              PrivioSpacing.lg,
              PrivioSpacing.xl,
              PrivioSpacing.lg,
              PrivioSpacing.sm,
            ),
            child: Text(
              caption!.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 0.8),
            ),
          ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: PrivioSpacing.gutter),
          decoration: const BoxDecoration(
            color: PrivioColors.surface,
            borderRadius: BorderRadius.all(PrivioRadius.card),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const Divider(indent: PrivioSpacing.lg),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}
