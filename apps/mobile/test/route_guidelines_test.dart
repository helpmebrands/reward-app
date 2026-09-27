import 'package:reward/data/snapshot_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reward/shell/router.dart';

import 'credit_sheet_test.dart' as sheet;
import 'editors_test.dart' as editors;
import 'household_sharing_test.dart' as sharing;
import 'sign_in_test.dart' as sign_in;
import 'system_cards_test.dart' as system_cards;
import 'today_empty_state_test.dart' as empty;

/// Apple's and Android's floors on every route: tap targets of 44 pt and
/// 48 dp, a label on every tappable node, and text contrast, in both themes
/// and on both platforms, so no later change can quietly shrink a control or
/// fade a label.

final platforms = TargetPlatformVariant(const {
  TargetPlatform.iOS,
  TargetPlatform.android,
});

const guidelines = <AccessibilityGuideline>[
  iOSTapTargetGuideline,
  androidTapTargetGuideline,
  labeledTapTargetGuideline,
  textContrastGuideline,
];

/// Each screen and overlay, pumped at 402 wide over the sample household.
final routes = <String, Future<void> Function(WidgetTester)>{
  'Welcome': (t) => sign_in.launch(t),
  'Sign in': (t) => sign_in.launch(t, introSeen: true),
  'Today': (t) => editors.pumpAt(t, Paths.today),
  'Today empty': (t) => empty.pumpApp(t, data: emptyAppData()),
  'Credits': (t) => editors.pumpAt(t, Paths.credits),
  'Cards': (t) => editors.pumpAt(t, Paths.cards),
  'Value': (t) => editors.pumpAt(t, Paths.value),
  'Settings': (t) => editors.pumpAt(t, Paths.settings),
  'Benefit editor': (t) => editors.pumpAt(t, benefitPath(editors.uber)),
  'Add card': (t) => editors.pumpAt(t, Paths.newCard),
  'Card editor': (t) => editors.pumpAt(t, cardPath(editors.jim)),
  'Change the terms': (t) =>
      system_cards.pump(t, location: '/cards/{gold}/convert'),
  'Join household': (t) => sharing.pump(t, location: invitePath('ABC123')),
  'Not found': (t) => editors.pumpAt(t, '/nope'),
  'Credit sheet': (t) => sheet.openResy(t, sheet.phone),
};

/// The painted surface of the button [finder] finds, without its tap padding.
Size drawn(WidgetTester tester, Finder finder) => tester.getSize(
  find.descendant(of: finder, matching: find.byType(Material)).first,
);

void main() {
  for (final MapEntry(key: name, value: pump) in routes.entries) {
    // @lat: [[mobile-tests#Route guidelines#Every route passes the four guidelines on both platforms]]
    testWidgets('$name meets the tap-target, label and contrast guidelines', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final failures = <String>[];
      for (final brightness in Brightness.values) {
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        await tester.pumpWidget(const SizedBox());
        await pump(tester);
        for (final guideline in guidelines) {
          final result = await guideline.evaluate(tester);
          if (!result.passed) {
            failures.add('${brightness.name}: ${result.reason}');
          }
        }
      }
      handle.dispose();
      expect(failures, isEmpty);
    }, variant: platforms);
  }

  // @lat: [[mobile-tests#Route guidelines#Icon buttons are drawn 44 and respond to 48]]
  testWidgets('each icon button is drawn 44 x 44 and responds to 48 x 48', (
    tester,
  ) async {
    Finder iconButton(Finder inside) =>
        find.ancestor(of: inside, matching: find.byType(IconButton)).first;
    final buttons = <String, (Future<void> Function(WidgetTester), Finder)>{
      'gear': (
        (t) => editors.pumpAt(t, Paths.today),
        iconButton(find.byIcon(Icons.settings_outlined)),
      ),
      'back': (
        (t) => editors.pumpAt(t, cardPath(editors.jim)),
        iconButton(find.byIcon(Icons.arrow_back)),
      ),
      'delete': (
        (t) => editors.pumpAt(t, cardPath(editors.jim)),
        iconButton(find.byIcon(Icons.delete_outline)),
      ),
      'close': (
        (t) => sheet.openResy(t, sheet.phone),
        find.byKey(const Key('sheet-close')),
      ),
      'bell': (
        (t) => editors.pumpAt(t, Paths.today),
        iconButton(find.byIcon(Icons.notifications_outlined)),
      ),
      'card menu': (
        (t) => editors.pumpAt(t, Paths.cards),
        find
            .descendant(
              of: find.byKey(const ValueKey('card-menu-card-0001')),
              matching: find.byType(IconButton),
            )
            .first,
      ),
    };
    for (final MapEntry(key: name, value: (pump, control)) in buttons.entries) {
      // A fresh tree, so no route survives from the last button's app.
      await tester.pumpWidget(const SizedBox());
      await pump(tester);
      expect(drawn(tester, control), const Size(44, 44), reason: name);
      final target = tester.getSize(control);
      expect(target.width, greaterThanOrEqualTo(48), reason: name);
      expect(target.height, greaterThanOrEqualTo(48), reason: name);
    }
  });
}
