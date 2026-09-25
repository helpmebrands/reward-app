import 'package:flutter/material.dart';

import 'nocturne_tokens.dart';

/// Material [ThemeData] built from the Nocturne tokens, one per brightness.
///
/// Where Nocturne and Material disagree on looks, Nocturne wins: the accent
/// is a line and a glow, never a flood, so primary actions are an outline;
/// contrast comes from the tonal ramps, and there is no alarm red. Material
/// supplies the ergonomics: 48dp targets, sheets, motion.
ThemeData nocturneTheme(Brightness brightness) {
  final tokens = brightness == Brightness.dark
      ? NocturneTokens.dark
      : NocturneTokens.light;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: tokens.accent,
    onPrimary: brightness == Brightness.dark
        ? tokens.background
        : tokens.surface,
    secondary: tokens.accent2,
    onSecondary: tokens.background,
    error: tokens.missed.line,
    onError: tokens.missed.foreground,
    surface: tokens.surface,
    onSurface: tokens.text,
    onSurfaceVariant: tokens.textSecondary,
    outline: tokens.controlBorder,
    outlineVariant: tokens.surfaceLine,
    surfaceContainerLowest: tokens.surfaceSunken,
    surfaceContainerLow: tokens.surfaceQuiet,
    surfaceContainer: tokens.surfaceRaised,
    surfaceContainerHigh: tokens.surfaceRaised,
    surfaceContainerHighest: tokens.surfaceRaised,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: tokens.background,
    canvasColor: tokens.background,
    dividerColor: tokens.divider,
    visualDensity: VisualDensity.compact,
    extensions: [tokens],
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: tokens.text,
      displayColor: tokens.text,
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: tokens.accent,
        side: BorderSide(color: tokens.accent),
        minimumSize: const Size(48, 48),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(Radii.md)),
        ),
      ),
    ),
    cardTheme: CardThemeData(
      color: tokens.surfaceRaised,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(Radii.md)),
        side: BorderSide(color: tokens.surfaceLine),
      ),
    ),
    // Every bar, the tabs' and the pushed routes', is 64 high and the page
    // colour at rest, taking the surface-container colour once content
    // scrolls under it, so nothing jumps between a tab and its sub-screens.
    appBarTheme: AppBarTheme(
      toolbarHeight: 64,
      backgroundColor: WidgetStateColor.resolveWith(
        (states) => states.contains(WidgetState.scrolledUnder)
            ? scheme.surfaceContainer
            : tokens.background,
      ),
      foregroundColor: tokens.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
  );
}
