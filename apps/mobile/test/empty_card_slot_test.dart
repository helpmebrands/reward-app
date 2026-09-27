import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reward/theme/nocturne_tokens.dart';
import 'package:reward/theme/theme.dart';
import 'package:reward/widgets/empty_card_slot.dart';

import 'contrast_test.dart' show ratio;

/// Every edge the illustration draws, with each colour it is drawn on.
List<String> failures(NocturneTokens tokens) {
  final p = EmptyCardSlotPalette.of(tokens);
  final pairs = [
    ('plain card edge on the circle', p.plainEdge, p.circle),
    ('plain card edge on its fill', p.plainEdge, p.plainFill),
    ('dashed card edge on the circle', p.slotEdge, p.circle),
    ('dashed card edge on the plain card', p.slotEdge, p.plainFill),
    ('dashed card edge on its fill', p.slotEdge, p.slotFill),
    ('plus badge on the circle', p.badge, p.circle),
    ('plus badge on the dashed card', p.badge, p.slotFill),
    ('plus on the badge', p.badgeGlyph, p.badge),
  ];
  return [
    for (final (name, fg, bg) in pairs)
      if (ratio(fg, bg) < 3) '$name is ${ratio(fg, bg).toStringAsFixed(2)}:1',
  ];
}

Widget _app(Brightness brightness) => MaterialApp(
  theme: nocturneTheme(brightness),
  home: const Scaffold(body: Center(child: EmptyCardSlot(size: 160))),
);

void main() {
  // @lat: [[mobile-tests#Empty card slot#The illustration is a size by size box]]
  testWidgets('EmptyCardSlot lays out as a size × size box', (tester) async {
    await tester.pumpWidget(_app(Brightness.light));
    expect(tester.getSize(find.byType(EmptyCardSlot)), const Size(160, 160));
  });

  // @lat: [[mobile-tests#Empty card slot#The illustration is hidden from the screen reader]]
  testWidgets('the illustration adds nothing to the semantics tree', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(Brightness.dark));
    expect(
      find.descendant(
        of: find.byType(EmptyCardSlot),
        matching: find.byType(ExcludeSemantics),
      ),
      findsOneWidget,
    );
    final node = tester.getSemantics(find.byType(EmptyCardSlot));
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

  // @lat: [[mobile-tests#Empty card slot#Every edge clears 3:1 in both themes]]
  test('every edge clears 3:1 against what it is drawn on', () {
    expect(failures(NocturneTokens.dark), isEmpty, reason: 'dark');
    expect(failures(NocturneTokens.light), isEmpty, reason: 'light');
  });

  testWidgets('the widget paints with the palette of the ambient theme', (
    tester,
  ) async {
    await tester.pumpWidget(_app(Brightness.dark));
    final painter =
        tester
                .widget<CustomPaint>(
                  find.descendant(
                    of: find.byType(EmptyCardSlot),
                    matching: find.byType(CustomPaint),
                  ),
                )
                .painter
            as EmptyCardSlotPainter;
    expect(painter.palette, EmptyCardSlotPalette.of(NocturneTokens.dark));
  });
}
