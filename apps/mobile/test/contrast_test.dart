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
/// computed over the theme extension the way the retired PWA computed it over
/// its `tokens.css`, so a changed token cannot slip below the ratios.

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
  chipContrast();

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
                    '../../packages/domain/test/fixtures/sample-household.json',
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

/// A theme's chip colours for [states], resolved as the chip resolves them.
(Color label, Color? fill, Color? outline) chipColours(
  ThemeData theme,
  Set<WidgetState> states,
) {
  final chip = theme.chipTheme;
  return (
    WidgetStateProperty.resolveAs<Color>(chip.labelStyle!.color!, states),
    chip.color?.resolve(states),
    WidgetStateProperty.resolveAs<BorderSide?>(chip.side, states)?.color,
  );
}

void chipContrast() {
  // @lat: [[mobile-tests#Token contrast#A selected chip's label holds on its fill]]
  test("a selected chip's label reaches 4.5:1 on its accent fill", () {
    final low = <String>[];
    for (final MapEntry(key: name, value: tokens) in themes.entries) {
      final theme = nocturneTheme(
        tokens == NocturneTokens.dark ? Brightness.dark : Brightness.light,
      );
      final (label, fill, _) = chipColours(theme, {WidgetState.selected});
      expect(fill, isNotNull, reason: name);
      expect(tokens.accentRamp.values, contains(fill), reason: name);
      final r = ratio(label, fill!);
      if (r < 4.5) low.add('$name: ${r.toStringAsFixed(2)}:1');
      expect(theme.chipTheme.checkmarkColor, label, reason: name);
    }
    expect(low, isEmpty);
  });

  // @lat: [[mobile-tests#Token contrast#An unselected chip's outline reaches 3:1]]
  test("an unselected chip's outline reaches 3:1 on every ground", () {
    final low = <String>[];
    for (final MapEntry(key: name, value: tokens) in themes.entries) {
      final theme = nocturneTheme(
        tokens == NocturneTokens.dark ? Brightness.dark : Brightness.light,
      );
      final (label, _, outline) = chipColours(theme, {});
      expect(outline, isNotNull, reason: name);
      for (final MapEntry(key: g, value: ground) in grounds.entries) {
        final r = ratio(outline!, ground(tokens));
        if (r < 3) low.add('$name: outline on $g is ${r.toStringAsFixed(2)}:1');
        final t = ratio(label, ground(tokens));
        if (t < 4.5) low.add('$name: label on $g is ${t.toStringAsFixed(2)}:1');
      }
    }
    expect(low, isEmpty);
  });
}
