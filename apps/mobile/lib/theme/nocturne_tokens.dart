import 'package:flutter/material.dart';

/// Nocturne's tokens, as the retired PWA's `tokens.css` recorded
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
    required this.chartMissed,
    required this.neutral,
    required this.accentRamp,
    required this.soon,
    required this.available,
    required this.locked,
    required this.captured,
    required this.missed,
    required this.valueEarned,
    required this.valueAvailable,
    required this.valueMissed,
    required this.valueOptOut,
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

  /// The Value chart's missed bar and its swatch: neutral-600 in dark and
  /// neutral-700 in light, so it clears 3:1 on the page in both.
  final Color chartMissed;

  /// Neutral ramp, steps 100 to 900.
  final Map<int, Color> neutral;

  /// Accent ramp, steps 100 to 900.
  final Map<int, Color> accentRamp;

  final Tone soon;
  final Tone available;
  final Tone locked;
  final Tone captured;
  final Tone missed;

  /// The value bar's segments (`ValueBar`): earned green, available in the
  /// accent, missed yellow and opt out grey. The bar's missed is yellow as
  /// designed; the missed status tone stays violet everywhere else.
  final Color valueEarned;
  final Color valueAvailable;
  final Color valueMissed;
  final Color valueOptOut;

  /// Nocturne, verbatim from the vendored copy, with the accent family moved
  /// to the logo's maroon at the same lightness (#291).
  static const NocturneTokens dark = NocturneTokens(
    background: Color(0xFF161826),
    surface: Color(0xFF232532),
    text: Color(0xFFE9E9ED),
    textSecondary: Color(0xFF9397AB),
    accent: Color(0xFFD16F84),
    accent2: Color(0xFFD793A0),
    controlBorder: Color(0xFF75798C),
    divider: Color(0x29E9E9ED),
    surfaceSunken: Color(0xFF1C1E2C),
    surfaceRaised: Color(0xFF232532),
    surfaceQuiet: Color(0xFF20222F),
    surfaceLine: Color(0xFF2B2D3A),
    section: Color(0xFF561728),
    sectionGlow: Color(0xFF742239),
    bloom: Color(0xFF341C21),
    chartMissed: Color(0xFF75798C),
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
      100: Color(0xFFFFF2F4),
      200: Color(0xFFFEDFE4),
      300: Color(0xFFFBC3CC),
      400: Color(0xFFF698AA),
      500: Color(0xFFD8758A),
      600: Color(0xFFB7576D),
      700: Color(0xFF8D4253),
      800: Color(0xFF652E3B),
      900: Color(0xFF3F2127),
    },
    soon: Tone(
      line: Color(0xFFD16F84),
      foreground: Color(0xFFFBC3CC),
      ground: Color(0xFF3F2127),
    ),
    available: Tone(
      line: Color(0xFF8D4253),
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
    // Missed is a muted violet, a loss already taken, never an alarm. It
    // keeps clear of the maroon accent so "use soon" never reads as missed.
    missed: Tone(
      line: Color(0xFF403A63),
      foreground: Color(0xFFC9C4F3),
      ground: Color(0xFF1E1D27),
    ),
    valueEarned: Color(0xFF6CC18E),
    valueAvailable: Color(0xFFD16F84),
    valueMissed: Color(0xFFE3C25B),
    valueOptOut: Color(0xFF595D6C),
  );

  /// The light theme the PWA derived: a lifted ground, the accent and status
  /// tones kept, and a neutral ramp blended from the ink to the ground so
  /// secondary text still clears 4.5:1.
  static const NocturneTokens light = NocturneTokens(
    background: Color(0xFFF3F5FE),
    surface: Color(0xFFFFFFFF),
    text: Color(0xFF232532),
    textSecondary: Color(0xFF636571),
    accent: Color(0xFF8D4253),
    accent2: Color(0xFFD793A0),
    controlBorder: Color(0xFF81838E),
    divider: Color(0x24232532),
    surfaceSunken: Color(0xFFE9EBF7),
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceQuiet: Color(0xFFF0F2FB),
    surfaceLine: Color(0xFFD8DCEE),
    section: Color(0xFFFBC3CC),
    sectionGlow: Color(0xFFF698AA),
    bloom: Color(0xFFFEE7EA),
    chartMissed: Color(0xFF81838E),
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
      100: Color(0xFF3F2127),
      200: Color(0xFF652E3B),
      300: Color(0xFF652E3B),
      400: Color(0xFF8D4253),
      500: Color(0xFFD8758A),
      600: Color(0xFFB7576D),
      700: Color(0xFF8D4253),
      800: Color(0xFFFBC3CC),
      900: Color(0xFFFEDFE4),
    },
    soon: Tone(
      line: Color(0xFF8D4253),
      foreground: Color(0xFF652E3B),
      ground: Color(0xFFFEDFE4),
    ),
    available: Tone(
      line: Color(0xFF8D4253),
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
      line: Color(0xFF776FAA),
      foreground: Color(0xFF4D4084),
      ground: Color(0xFFEDEBFB),
    ),
    valueEarned: Color(0xFF2E7D4F),
    valueAvailable: Color(0xFFB7576D),
    valueMissed: Color(0xFFA87F12),
    valueOptOut: Color(0xFFB9BBC5),
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

  /// Apple's gap between bezeled controls such as chips and buttons, which
  /// no 0.7x step lands on.
  static const double bezel = 12;
}

/// Nocturne's radii.
abstract final class Radii {
  static const double sm = 4;
  static const double md = 8;
  static const double lg = 14;
}
