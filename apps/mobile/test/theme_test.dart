import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reward/data/snapshot_store.dart';
import 'package:reward/logic/app_store.dart';
import 'package:reward/main.dart';
import 'package:reward/theme/nocturne_tokens.dart';
import 'package:reward/theme/theme.dart';

void main() {
  // @lat: [[mobile-tests#Theme#Both themes carry the Nocturne token colours]]
  testWidgets('the dark and light themes carry the token colours', (
    tester,
  ) async {
    final dark = nocturneTheme(Brightness.dark);
    expect(dark.colorScheme.primary, const Color(0xFFD16F84));
    expect(dark.colorScheme.surface, const Color(0xFF232532));
    expect(dark.colorScheme.onSurface, const Color(0xFFE9E9ED));
    expect(dark.scaffoldBackgroundColor, const Color(0xFF161826));
    expect(dark.extension<NocturneTokens>(), same(NocturneTokens.dark));

    final light = nocturneTheme(Brightness.light);
    expect(light.colorScheme.primary, const Color(0xFF8D4253));
    expect(light.colorScheme.surface, const Color(0xFFFFFFFF));
    expect(light.colorScheme.onSurface, const Color(0xFF232532));
    expect(light.scaffoldBackgroundColor, const Color(0xFFF3F5FE));
    expect(light.extension<NocturneTokens>(), same(NocturneTokens.light));
  });

  // @lat: [[mobile-tests#Theme#The app follows the platform brightness]]
  testWidgets('the app picks the theme from the platform brightness', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final store = AppStore(
      store: MemorySnapshotStore(),
      clock: () => DateTime(2026, 9, 16),
    );
    await store.load();
    await tester.pumpWidget(RewardApp(store: store));
    await tester.pumpAndSettle();
    final context = tester.element(find.text('Start with one card'));
    expect(Theme.of(context).colorScheme.primary, NocturneTokens.dark.accent);
    expect(
      Theme.of(context).extension<NocturneTokens>()!.soon.ground,
      const Color(0xFF3F2127),
    );
  });

  // @lat: [[mobile-tests#Theme#The accent takes the logo's maroon]]
  test("the accent sits within 10 degrees of the logo's maroon", () {
    final logo = oklchHue(const Color(0xFF933F53));
    for (final t in [NocturneTokens.dark, NocturneTokens.light]) {
      expect(hueGap(oklchHue(t.accent), logo), lessThan(10));
    }
  });

  // @lat: [[mobile-tests#Theme#Use soon and missed are different colours]]
  test('use soon and missed lines are at least 70 degrees apart', () {
    for (final t in [NocturneTokens.dark, NocturneTokens.light]) {
      expect(
        hueGap(oklchHue(t.soon.line), oklchHue(t.missed.line)),
        greaterThanOrEqualTo(70),
      );
    }
  });
}

/// OKLCH hue in degrees, the perceptual hue the palette is tuned in.
double oklchHue(Color c) {
  double lin(double v) =>
      v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  final r = lin(c.r), g = lin(c.g), b = lin(c.b);
  double cbrt(double v) => math.pow(v, 1 / 3).toDouble();
  final l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
  final m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
  final s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
  final a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s;
  final bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s;
  return (math.atan2(bb, a) * 180 / math.pi) % 360;
}

/// The shorter way round the hue circle between two hues.
double hueGap(double a, double b) {
  final d = (a - b).abs() % 360;
  return math.min(d, 360 - d);
}
