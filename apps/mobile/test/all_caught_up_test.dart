import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reward/theme/nocturne_tokens.dart';
import 'package:reward/theme/theme.dart';
import 'package:reward/widgets/all_caught_up.dart';

import 'contrast_test.dart' show ratio;

/// Every edge the illustration draws, with each colour it is drawn on.
List<String> failures(NocturneTokens tokens) {
  final p = AllCaughtUpPalette.of(tokens);
  final pairs = [
    ('card edge on the circle', p.cardEdge, p.circle),
    ('card edge on its fill', p.cardEdge, p.cardFill),
    ('card edge on the page', p.cardEdge, tokens.background),
    ('ticks on the circle', p.ticks, p.circle),
    ('ticks on the page', p.ticks, tokens.background),
    ('check badge on the circle', p.badge, p.circle),
    ('check badge on the card', p.badge, p.cardFill),
    ('check on the badge', p.badgeGlyph, p.badge),
  ];
  return [
    for (final (name, fg, bg) in pairs)
      if (ratio(fg, bg) < 3) '$name is ${ratio(fg, bg).toStringAsFixed(2)}:1',
  ];
}

Widget _app(Brightness brightness, {bool disableAnimations = false}) =>
    MaterialApp(
      theme: nocturneTheme(brightness),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: const Scaffold(body: Center(child: AllCaughtUp(size: 132))),
      ),
    );

AllCaughtUpPainter _painter(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(
              find.descendant(
                of: find.byType(AllCaughtUp),
                matching: find.byType(CustomPaint),
              ),
            )
            .painter
        as AllCaughtUpPainter;

void main() {
  // @lat: [[mobile-tests#All caught up illustration#Every edge clears 3:1 in both themes]]
  test('every edge clears 3:1 against what it is drawn on', () {
    expect(failures(NocturneTokens.dark), isEmpty, reason: 'dark');
    expect(failures(NocturneTokens.light), isEmpty, reason: 'light');
  });

  testWidgets('the widget paints with the palette of the ambient theme', (
    tester,
  ) async {
    await tester.pumpWidget(_app(Brightness.dark));
    expect(
      _painter(tester).palette,
      AllCaughtUpPalette.of(NocturneTokens.dark),
    );
    expect(tester.getSize(find.byType(AllCaughtUp)), const Size(132, 132));
  });

  // @lat: [[mobile-tests#All caught up illustration#The illustration is hidden from the screen reader]]
  testWidgets('the illustration adds nothing to the semantics tree', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(Brightness.light));
    expect(
      find.descendant(
        of: find.byType(AllCaughtUp),
        matching: find.byType(ExcludeSemantics),
      ),
      findsOneWidget,
    );
    final node = tester.getSemantics(find.byType(AllCaughtUp));
    final labels = <String>[];
    void collect(SemanticsNode n) {
      if (n.label.isNotEmpty) labels.add(n.label);
      n.visitChildren((c) {
        collect(c);
        return true;
      });
    }

    collect(node);
    expect(labels, isEmpty);
    handle.dispose();
  });

  // @lat: [[mobile-tests#All caught up illustration#The badge pops once]]
  testWidgets('the check badge pops from 0.4 to full size once', (
    tester,
  ) async {
    await tester.pumpWidget(_app(Brightness.light));
    expect(_painter(tester).badgeScale, closeTo(0.4, 0.001));
    await tester.pumpAndSettle();
    expect(_painter(tester).badgeScale, 1);
  });

  // @lat: [[mobile-tests#All caught up illustration#Reduce motion draws the badge at full size]]
  testWidgets('with animations disabled the badge is full size at once', (
    tester,
  ) async {
    await tester.pumpWidget(_app(Brightness.light, disableAnimations: true));
    expect(_painter(tester).badgeScale, 1);
    expect(tester.hasRunningAnimations, isFalse);
  });
}
