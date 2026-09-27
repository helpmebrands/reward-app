import 'package:flutter/material.dart';

import 'nocturne_tokens.dart';

/// Material [ThemeData] built from the Nocturne tokens, one per brightness.
///
/// Where Nocturne and Material disagree on looks, Nocturne wins: the accent
/// is a line and a glow, never a flood, so primary actions are an outline;
/// contrast comes from the tonal ramps, and there is no alarm red. Material
/// supplies the ergonomics: sheets, motion, and tap targets padded to 48dp.
///
/// Every control is drawn 44 high, Apple's minimum and never more, and
/// Material pads its touch area to 48 so Android's rule holds too. Chips are
/// drawn 40.
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
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    extensions: [tokens],
  );
  // A selected chip or segment is filled from the accent's tonal range with
  // the ink on it and a check mark; an unselected chip is outlined in the
  // control border.
  final chipFill = brightness == Brightness.dark
      ? tokens.accentRamp[800]!
      : tokens.accentRamp[900]!;
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: tokens.text,
      displayColor: tokens.text,
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: tokens.accent,
        side: BorderSide(color: tokens.accent),
        minimumSize: const Size(48, _drawn),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(Radii.md)),
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size(64, _drawn)),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(64, _drawn)),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(_drawn, _drawn),
        iconSize: 24,
      ),
    ),
    // A segmented button sizes itself from its density rather than its
    // minimum size: one step up draws the outline 44 and pads touch to 52.
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        visualDensity: const VisualDensity(vertical: 1),
        foregroundColor: tokens.text,
        selectedForegroundColor: tokens.text,
        selectedBackgroundColor: chipFill,
      ),
    ),
    chipTheme: ChipThemeData(
      // 32 of content plus 6 of label padding and the 1-wide outline top
      // and bottom: 40 drawn, whatever the font's line height.
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      labelPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      color: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? chipFill : null,
      ),
      labelStyle: TextStyle(color: tokens.text),
      checkmarkColor: tokens.text,
      showCheckmark: true,
      side: WidgetStateBorderSide.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? BorderSide(color: chipFill)
            : BorderSide(color: tokens.controlBorder),
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

/// The drawn height of every control: Apple's 44pt minimum.
const double _drawn = 44;
