import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:domain/domain.dart' hide Tone;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reward/data/snapshot_store.dart';
import 'package:reward/logic/app_store.dart';
import 'package:reward/screens/today_screen.dart';
import 'package:reward/theme/nocturne_tokens.dart';
import 'package:reward/theme/theme.dart';

/// Token contrast, WCAG 1.4.3 (text, 4.5:1) and 1.4.11 (controls, 3:1),
/// computed over the theme extension the way `apps/pwa/tests/contrast.test.ts`
/// computes it over `tokens.css`, so a copied token cannot drift.

double _channel(double c) =>
    c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4).toDouble();

double luminance(Color c) =>
    0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b);

double ratio(Color a, Color b) {
  final l1 = luminance(a);
  final l2 = luminance(b);
  return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05);
}

const themes = {'dark': NocturneTokens.dark, 'light': NocturneTokens.light};

typedef Pair = (
  String name,
  Color Function(NocturneTokens) fg,
  Color Function(NocturneTokens) bg,
);

/// The grounds a control or secondary text sits on: the page, the raised,
/// sunken and quiet surfaces, and the captured row.
const grounds = <String, Color Function(NocturneTokens)>{
  'background': _background,
  'surfaceRaised': _surfaceRaised,
  'surfaceSunken': _surfaceSunken,
  'surfaceQuiet': _surfaceQuiet,
  'captured.ground': _capturedGround,
};

Color _background(NocturneTokens t) => t.background;
Color _surfaceRaised(NocturneTokens t) => t.surfaceRaised;
Color _surfaceSunken(NocturneTokens t) => t.surfaceSunken;
Color _surfaceQuiet(NocturneTokens t) => t.surfaceQuiet;
Color _capturedGround(NocturneTokens t) => t.captured.ground;

Map<String, Tone> tones(NocturneTokens t) => {
  'soon': t.soon,
  'available': t.available,
  'locked': t.locked,
  'captured': t.captured,
  'missed': t.missed,
};

/// One line per failing pair, so a red run names every offender at once.
List<String> failures(
  Iterable<(String, Color, Color)> Function(NocturneTokens) pairs,
  double minimum,
) {
  final out = <String>[];
  for (final MapEntry(key: theme, value: tokens) in themes.entries) {
    for (final (name, fg, bg) in pairs(tokens)) {
      final r = ratio(fg, bg);
      if (r < minimum) out.add('$theme: $name is ${r.toStringAsFixed(2)}:1');
    }
  }
  return out;
}

void main() {
  // @lat: [[mobile-tests#Token contrast#Secondary text reaches 4.5:1 on every ground]]
  test('secondary text reaches 4.5:1 on every ground it sits on', () {
    expect(
      failures(
        (t) => [
          for (final MapEntry(key: name, value: ground) in grounds.entries)
            ('textSecondary on $name', t.textSecondary, ground(t)),
        ],
        4.5,
      ),
      isEmpty,
    );
  });

  // @lat: [[mobile-tests#Token contrast#Control boundaries reach 3:1]]
  test('control borders reach 3:1 on every ground', () {
    expect(
      failures(
        (t) => [
          for (final MapEntry(key: name, value: ground) in grounds.entries)
            ('controlBorder on $name', t.controlBorder, ground(t)),
        ],
        3,
      ),
      isEmpty,
    );
  });

  // @lat: [[mobile-tests#Token contrast#The missed bar reaches 3:1 on the page]]
  test('the chart\'s missed bar reaches 3:1 on the page ground', () {
    expect(
      failures(
        (t) => [('chartMissed on background', t.chartMissed, t.background)],
        3,
      ),
      isEmpty,
    );
  });

  // @lat: [[mobile-tests#Token contrast#The overlap card's text holds on the section ground]]
  testWidgets("every text the overlap card draws reaches 4.5:1 on its ground", (
    tester,
  ) async {
    for (final MapEntry(key: theme, value: tokens) in themes.entries) {
      final store = AppStore(
        store: MemorySnapshotStore(
          appDataFromJson(
            jsonDecode(
                  File(
                    '../pwa/samples/sample-household.json',
                  ).readAsStringSync(),
                )
                as Map<String, dynamic>,
          ),
        ),
        clock: () => DateTime(2026, 9, 16),
      );
      await store.load();
      tester.view.physicalSize = const Size(402, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: nocturneTheme(
            theme == 'dark' ? Brightness.dark : Brightness.light,
          ),
          home: Scaffold(body: TodayScreen(store: store)),
        ),
      );
      await tester.pumpAndSettle();
      final cardTexts = find.descendant(
        of: find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_OverlapCard',
        ),
        matching: find.byType(Text),
      );
      expect(cardTexts, findsAtLeast(3));
      final low = <String>[];
      for (final element in cardTexts.evaluate()) {
        final widget = element.widget as Text;
        final colour =
            widget.style?.color ?? DefaultTextStyle.of(element).style.color!;
        final r = ratio(colour, tokens.section);
        if (r < 4.5) {
          low.add('$theme: "${widget.data}" is ${r.toStringAsFixed(2)}:1');
        }
      }
      expect(low, isEmpty);
    }
  });

  // @lat: [[mobile-tests#Token contrast#Each tone's text holds on its own ground]]
  test("each tone's foreground reaches 4.5:1 on its ground", () {
    expect(
      failures(
        (t) => [
          for (final MapEntry(key: name, value: tone) in tones(t).entries)
            ('$name foreground on its ground', tone.foreground, tone.ground),
        ],
        4.5,
      ),
      isEmpty,
    );
  });
}
