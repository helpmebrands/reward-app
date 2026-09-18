import 'package:flutter/material.dart';

/// Nocturne's tokens, as the PWA's `apps/pwa/src/styles/tokens.css` records
/// them: the dark system verbatim, and the light theme the PWA derived from
/// it. Every colour a widget uses resolves to one of these, so re-theming is
/// a token swap rather than a sweep through components.
///
/// Carried as a [ThemeExtension] so a widget reads
/// `Theme.of(context).extension<NocturneTokens>()!` and never a hex.
@immutable
class NocturneTokens extends ThemeExtension<NocturneTokens> {
  const NocturneTokens({
    required this.background,
    required this.surface,
    required this.text,
    required this.textSecondary,
    required this.accent,
    required this.accent2,
    required this.controlBorder,
    required this.divider,
    required this.surfaceSunken,
    required this.surfaceRaised,
    required this.surfaceQuiet,
    required this.surfaceLine,
    required this.section,
    required this.sectionGlow,
    required this.bloom,
    required this.neutral,
    required this.accentRamp,
    required this.soon,
    required this.available,
    required this.locked,
    required this.captured,
    required this.missed,
  });

  final Color background;
  final Color surface;
  final Color text;
  final Color textSecondary;
  final Color accent;
  final Color accent2;
  final Color controlBorder;
  final Color divider;
  final Color surfaceSunken;
  final Color surfaceRaised;
  final Color surfaceQuiet;
  final Color surfaceLine;

  /// The one sanctioned saturated ground, used for the overlap cards.
  final Color section;
  final Color sectionGlow;

  /// The bloom's peak behind each screen.
  final Color bloom;

  /// Neutral ramp, steps 100 to 900.
  final Map<int, Color> neutral;

  /// Accent ramp, steps 100 to 900.
  final Map<int, Color> accentRamp;

  final Tone soon;
  final Tone available;
  final Tone locked;
  final Tone captured;
  final Tone missed;

  /// Nocturne, verbatim from the vendored copy.
  static const NocturneTokens dark = NocturneTokens(
    background: Color(0xFF161826),
    surface: Color(0xFF232532),
    text: Color(0xFFE9E9ED),
    textSecondary: Color(0xFF9397AB),
    accent: Color(0xFF9184D9),
    accent2: Color(0xFFA7A1DB),
    controlBorder: Color(0xFF75798C),
    divider: Color(0x29E9E9ED),
    surfaceSunken: Color(0xFF1C1E2C),
    surfaceRaised: Color(0xFF232532),
    surfaceQuiet: Color(0xFF20222F),
    surfaceLine: Color(0xFF2B2D3A),
    section: Color(0xFF262A60),
    sectionGlow: Color(0xFF353B80),
    bloom: Color(0xFF232136),
    neutral: {
      100: Color(0xFFF3F5FE),
      200: Color(0xFFE4E7F5),
      300: Color(0xFFCFD3E5),
      400: Color(0xFFB2B6CA),
      500: Color(0xFF9397AB),
      600: Color(0xFF75798C),
      700: Color(0xFF595D6C),
      800: Color(0xFF3F424D),
      900: Color(0xFF292B31),
    },
    accentRamp: {
      100: Color(0xFFF5F4FF),
      200: Color(0xFFE7E5FE),
      300: Color(0xFFD2CEFD),
      400: Color(0xFFB5ABFC),
      500: Color(0xFF968AE0),
      600: Color(0xFF796CBF),
      700: Color(0xFF5D5294),
      800: Color(0xFF423A6A),
      900: Color(0xFF2B2741),
    },
    soon: Tone(
      line: Color(0xFF9184D9),
      foreground: Color(0xFFD2CEFD),
      ground: Color(0xFF2B2741),
    ),
    available: Tone(
      line: Color(0xFF5D5294),
      foreground: Color(0xFFCFD3E5),
      ground: Color(0xFF232532),
    ),
    // Locked is warm ochre, so it reads as blocked rather than urgent.
    locked: Tone(
      line: Color(0xFF7A6A3F),
      foreground: Color(0xFFE2CF9A),
      ground: Color(0xFF262218),
    ),
    captured: Tone(
      line: Color(0xFF3F424D),
      foreground: Color(0xFF9397AB),
      ground: Color(0xFF1C1E2C),
    ),
    // Missed is a muted rose, a loss already taken, never an alarm.
    missed: Tone(
      line: Color(0xFF5C3044),
      foreground: Color(0xFFF0B9C8),
      ground: Color(0xFF241B22),
    ),
  );

  /// The light theme the PWA derived: a lifted ground, the accent and status
  /// tones kept, and a neutral ramp blended from the ink to the ground so
  /// secondary text still clears 4.5:1.
  static const NocturneTokens light = NocturneTokens(
    background: Color(0xFFF3F5FE),
    surface: Color(0xFFFFFFFF),
    text: Color(0xFF232532),
    textSecondary: Color(0xFF636571),
    accent: Color(0xFF5D5294),
    accent2: Color(0xFFA7A1DB),
    controlBorder: Color(0xFF81838E),
    divider: Color(0x24232532),
    surfaceSunken: Color(0xFFE9EBF7),
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceQuiet: Color(0xFFF0F2FB),
    surfaceLine: Color(0xFFD8DCEE),
    section: Color(0xFFD2CEFD),
    sectionGlow: Color(0xFFB5ABFC),
    bloom: Color(0xFFECEBFE),
    neutral: {
      100: Color(0xFF232532),
      200: Color(0xFF383A46),
      300: Color(0xFF444653),
      400: Color(0xFF51535F),
      500: Color(0xFF5B5D69),
      600: Color(0xFF636571),
      700: Color(0xFF81838E),
      800: Color(0xFFB9BBC5),
      900: Color(0xFFDEE0EA),
    },
    accentRamp: {
      100: Color(0xFF2B2741),
      200: Color(0xFF423A6A),
      300: Color(0xFF423A6A),
      400: Color(0xFF5D5294),
      500: Color(0xFF968AE0),
      600: Color(0xFF796CBF),
      700: Color(0xFF5D5294),
      800: Color(0xFFD2CEFD),
      900: Color(0xFFE7E5FE),
    },
    soon: Tone(
      line: Color(0xFF5D5294),
      foreground: Color(0xFF423A6A),
      ground: Color(0xFFE7E5FE),
    ),
    available: Tone(
      line: Color(0xFF5D5294),
      foreground: Color(0xFF444653),
      ground: Color(0xFFFFFFFF),
    ),
    locked: Tone(
      line: Color(0xFF8A7742),
      foreground: Color(0xFF5A4C22),
      ground: Color(0xFFF7F0DD),
    ),
    captured: Tone(
      line: Color(0xFFB9BBC5),
      foreground: Color(0xFF5B5D69),
      ground: Color(0xFFE9EBF7),
    ),
    missed: Tone(
      line: Color(0xFFA06280),
      foreground: Color(0xFF7A2F4D),
      ground: Color(0xFFF9E8EF),
    ),
  );

  @override
  NocturneTokens copyWith() => this;

  @override
  NocturneTokens lerp(ThemeExtension<NocturneTokens>? other, double t) {
    // The two palettes are discrete themes, not a gradient; snap at the
    // midpoint rather than blending tokens that were tuned for contrast.
    if (other is! NocturneTokens) return this;
    return t < 0.5 ? this : other;
  }
}

/// A status tone: its line, its foreground and its ground. Every status
/// appears as all three.
@immutable
class Tone {
  const Tone({
    required this.line,
    required this.foreground,
    required this.ground,
  });

  final Color line;
  final Color foreground;
  final Color ground;
}

/// Nocturne's spacing steps at 0.7x density, in logical pixels.
abstract final class Space {
  static const double s1 = 2.8;
  static const double s2 = 5.6;
  static const double s3 = 8.4;
  static const double s4 = 11.2;
  static const double s6 = 16.8;
  static const double s8 = 22.4;
  static const double s10 = 28;
  static const double s12 = 33.6;
}

/// Nocturne's radii.
abstract final class Radii {
  static const double sm = 4;
  static const double md = 8;
  static const double lg = 14;
}
