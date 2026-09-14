import 'package:flutter/material.dart';

import 'accent.dart';
import 'privio_colors.dart';

/// The single source of truth for Privio's look, built from the tokens in
/// `docs/design-system.md`. Screens reach for `Theme.of(context)` rather than
/// hard-coding colours, which is what lets the Appearance screen swap the
/// accent without a restart: the theme is rebuilt from one seed and every
/// screen under it redraws.
///
/// What does *not* come from [accent]: the black background and the grey
/// cards, which are the app's shape rather than its colour; [PrivioColors
/// .danger] and [PrivioColors.warning], which mean something; and the brand
/// mark, which is the brand.
abstract final class PrivioTheme {
  static ThemeData dark({AppAccent accent = AppAccent.green}) {
    final accents = PrivioAccents.of(accent);
    final scheme = ColorScheme.dark(
      primary: accents.accent,
      onPrimary: accents.onAccent,
      secondary: accents.bright,
      onSecondary: accents.onAccent,
      surface: PrivioColors.surface,
      onSurface: PrivioColors.textPrimary,
      // Semantic, and deliberately not derived from the accent: an error is
      // red whatever colour the buttons are, and an account that chose red
      // still needs "delete" to look different from "send".
      error: PrivioColors.danger,
      onError: PrivioColors.textPrimary,
      outline: PrivioColors.border,
    );

    final textTheme = _textTheme();

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: PrivioColors.background,
      canvasColor: PrivioColors.background,
      splashColor: accents.accent.withValues(alpha: 0.08),
      highlightColor: accents.accent.withValues(alpha: 0.06),
      fontFamily: _fontFamily,
      textTheme: textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: PrivioColors.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: PrivioColors.textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: _fontFamily,
          fontSize: 22,
          height: 28 / 22,
          fontWeight: FontWeight.w600,
          color: PrivioColors.textPrimary,
        ),
      ),
      // The app's own tooltips — "More", "Voice call", "Attach a file" — in
      // the app's own colours. The default is a pale grey slab that belongs to
      // no part of this design. (The back arrow has none at all; see
      // widgets/privio_back_button.dart.)
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: PrivioColors.surfaceHigh,
          borderRadius: const BorderRadius.all(PrivioRadius.card),
          border: Border.all(color: PrivioColors.border),
        ),
        textStyle: const TextStyle(
          fontFamily: _fontFamily,
          fontSize: 12,
          height: 16 / 12,
          color: PrivioColors.textSecondary,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: PrivioSpacing.md,
          vertical: PrivioSpacing.sm,
        ),
        // Long enough that moving a pointer across an app bar does not leave a
        // trail of labels behind it.
        waitDuration: const Duration(milliseconds: 600),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: PrivioColors.background,
        selectedItemColor: accents.accent,
        unselectedItemColor: PrivioColors.textTertiary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        showUnselectedLabels: true,
        selectedLabelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
        unselectedLabelStyle: const TextStyle(fontSize: 11),
      ),
      dividerTheme: const DividerThemeData(
        color: PrivioColors.border,
        thickness: 1,
        space: 1,
      ),
      cardTheme: const CardThemeData(
        color: PrivioColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(PrivioRadius.card),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: PrivioColors.textSecondary,
        textColor: PrivioColors.textPrimary,
        tileColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: PrivioColors.surfaceRaised,
        hintStyle: textTheme.bodyMedium?.copyWith(color: PrivioColors.textTertiary),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: PrivioSpacing.lg,
          vertical: PrivioSpacing.md,
        ),
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(PrivioRadius.card),
          borderSide: BorderSide.none,
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(PrivioRadius.card),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(PrivioRadius.card),
          borderSide: BorderSide(color: accents.accent, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accents.accent,
          foregroundColor: accents.onAccent,
          disabledBackgroundColor: accents.dim,
          disabledForegroundColor: PrivioColors.textTertiary,
          minimumSize: const Size.fromHeight(52),
          textStyle: const TextStyle(
            fontFamily: _fontFamily,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(PrivioRadius.button),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: accents.accent),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(PrivioColors.textPrimary),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? accents.accent
              : PrivioColors.surfaceHigh,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accents.accent,
        linearTrackColor: PrivioColors.surfaceHigh,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: PrivioColors.surfaceHigh,
        contentTextStyle: TextStyle(color: PrivioColors.textPrimary),
        behavior: SnackBarBehavior.floating,
      ),
      // Everything derived from the seed, carried on the theme so a widget can
      // ask for the shade it needs rather than recomputing one.
      extensions: [accents],
    );
  }

  /// The face the app ships with, declared under a project name so the asset
  /// in `assets/fonts/` is what actually renders. Naming a font the bundle does
  /// not contain leaves the choice to the platform, and on the web it leaves it
  /// to a font fetched from Google's CDN.
  static const String _fontFamily = 'Privio';

  static TextTheme _textTheme() => const TextTheme(
        displaySmall: TextStyle(
          fontSize: 32,
          height: 38 / 32,
          fontWeight: FontWeight.w600,
          color: PrivioColors.textPrimary,
        ),
        titleLarge: TextStyle(
          fontSize: 22,
          height: 28 / 22,
          fontWeight: FontWeight.w600,
          color: PrivioColors.textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 17,
          height: 22 / 17,
          fontWeight: FontWeight.w600,
          color: PrivioColors.textPrimary,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          height: 22 / 16,
          color: PrivioColors.textPrimary,
        ),
        bodyMedium: TextStyle(
          fontSize: 15,
          height: 20 / 15,
          color: PrivioColors.textPrimary,
        ),
        bodySmall: TextStyle(
          fontSize: 13,
          height: 18 / 13,
          color: PrivioColors.textSecondary,
        ),
        labelMedium: TextStyle(
          fontSize: 13,
          height: 16 / 13,
          fontWeight: FontWeight.w500,
          color: PrivioColors.textSecondary,
        ),
        labelSmall: TextStyle(
          fontSize: 11,
          height: 14 / 11,
          color: PrivioColors.textTertiary,
        ),
      );
}
