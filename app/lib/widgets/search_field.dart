import 'package:flutter/material.dart';

import '../theme/privio_colors.dart';

/// The rounded search field used on the Chats and Contacts screens.
///
/// Search runs entirely on-device against the decrypted local database — no
/// query ever reaches the server.
class PrivioSearchField extends StatelessWidget {
  const PrivioSearchField({
    required this.hintText,
    super.key,
    this.onChanged,
    this.controller,
  });

  final String hintText;
  final ValueChanged<String>? onChanged;
  final TextEditingController? controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: PrivioSpacing.gutter,
        vertical: PrivioSpacing.sm,
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        style: Theme.of(context).textTheme.bodyMedium,
        decoration: InputDecoration(
          hintText: hintText,
          prefixIcon: const Icon(Icons.search_rounded, size: 20, color: PrivioColors.textTertiary),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: PrivioSpacing.md),
        ),
      ),
    );
  }
}

/// The pill filter row ("All · Unread · Groups") above the chat list.
class FilterChips extends StatelessWidget {
  const FilterChips({
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.gutter),
        itemCount: labels.length,
        separatorBuilder: (_, __) => const SizedBox(width: PrivioSpacing.sm),
        itemBuilder: (context, index) {
          final selected = index == selectedIndex;
          return GestureDetector(
            onTap: () => onSelected(index),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.lg),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? PrivioColors.accent : PrivioColors.surfaceRaised,
                borderRadius: const BorderRadius.all(PrivioRadius.pill),
              ),
              child: Text(
                labels[index],
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: selected ? PrivioColors.background : PrivioColors.textSecondary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
