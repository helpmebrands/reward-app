import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reward/screens/credits_screen.dart';
import 'package:reward/theme/nocturne_tokens.dart';

import 'credits_screen_test.dart' as credits;
import 'sign_in_test.dart' as sign_in;
import 'system_cards_test.dart' as system_cards;

/// Apple's spacing: about 12 between bezeled controls, and plain text
/// buttons given the full column so they read as equal choices.

/// The painted surface of [control], without its tap padding.
Rect drawn(WidgetTester tester, Finder control) => tester.getRect(
  find.descendant(of: control, matching: find.byType(Material)).first,
);

void main() {
  // @lat: [[mobile-tests#Bezel spacing#Credits filter chips sit 12 apart]]
  testWidgets('Credits filter chips are at least 12 apart both ways', (
    tester,
  ) async {
    // A large text size wraps the chips onto several rows.
    await credits.pumpCredits(tester, textScale: 1.6);
    final chips = find.descendant(
      of: find.byType(CreditsScreen),
      matching: find.byType(ChoiceChip),
    );
    final rects = [
      for (var i = 0; i < chips.evaluate().length; i++)
        drawn(tester, chips.at(i)),
    ];
    expect(rects.length, greaterThan(2));
    var rows = 1;
    for (var i = 1; i < rects.length; i++) {
      final (a, b) = (rects[i - 1], rects[i]);
      if ((b.top - a.top).abs() < 1) {
        expect(b.left - a.right, greaterThanOrEqualTo(12), reason: '$a $b');
      } else {
        rows++;
        expect(b.top - a.bottom, greaterThanOrEqualTo(12), reason: '$a $b');
      }
    }
    expect(rows, greaterThan(1), reason: 'the chips never wrapped');
  });

  // @lat: [[mobile-tests#Bezel spacing#Sign in's buttons are 44 high, 12 apart and full width]]
  testWidgets(
    "Sign in's buttons are drawn 44, 12 apart, text ones full width",
    (tester) async {
      await sign_in.launch(tester, introSeen: true);
      final google = drawn(tester, sign_in.key('sign-in-google'));
      final apple = drawn(tester, sign_in.key('sign-in-apple'));
      expect(google.height, 44);
      expect(apple.height, 44);
      expect(apple.top - google.bottom, greaterThanOrEqualTo(12));
      for (final name in ['sign-in-have-code', 'sign-in-learn-more']) {
        final button = drawn(tester, sign_in.key(name));
        expect(button.height, 44, reason: name);
        expect(button.width, google.width, reason: name);
      }
    },
  );

  // @lat: [[mobile-tests#Bezel spacing#Change the terms offers two full-width choices]]
  testWidgets('Change the terms draws both choices 44 high and full width', (
    tester,
  ) async {
    await system_cards.pump(tester, location: '/cards/{gold}/convert');
    final mine = drawn(tester, find.byKey(const Key('convert-confirm')));
    final keep = drawn(
      tester,
      find.ancestor(
        of: find.text('Keep it up to date'),
        matching: find.byType(TextButton),
      ),
    );
    expect(mine.height, 44);
    expect(keep.height, 44);
    expect(keep.width, mine.width);
    expect(keep.top - mine.bottom, greaterThanOrEqualTo(12));
  });

  // @lat: [[mobile-tests#Bezel spacing#The 12 gap is a named token]]
  test('the gap between bezeled controls is a named token of 12', () {
    expect(Space.bezel, 12);
  });
}
