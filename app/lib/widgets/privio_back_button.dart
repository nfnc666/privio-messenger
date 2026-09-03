import 'package:flutter/material.dart';

/// The back arrow, without the label Flutter hangs off it.
///
/// Every pushed screen used the framework's [BackButton], which carries a
/// tooltip reading "Back". On a phone that only surfaces under a long press,
/// but on the web it follows the pointer around as a floating slab, and it is
/// the one piece of chrome that appears on every screen in the app. An arrow
/// pointing left already says what it does.
///
/// The word is not lost, only unpainted: it moves to the icon's semantic
/// label, which is where a screen reader looks and where nothing draws it.
class PrivioBackButton extends StatelessWidget {
  const PrivioBackButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back_rounded, semanticLabel: 'Back'),
        onPressed: () => Navigator.maybePop(context),
      );
}
