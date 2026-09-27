import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reward/shell/router.dart';

import 'control_sizes_test.dart' as sizes;
import 'editors_test.dart' as editors;

/// Groups that offer exactly one choice are segmented buttons, Apple's
/// control for a single choice, drawn 44 and filling their column.

typedef Group = (String name, String location, List<String> options);

final groups = <Group>[
  ('Appearance', Paths.settings, ['System', 'Dark', 'Light']),
  (
    'Measured from',
    benefitPath(editors.uber),
    ['The calendar', 'Card anniversary'],
  ),
  ('Kind', cardPath(editors.jim), ['Personal', 'Business']),
  ('Months shown', Paths.value, ['6m', '9m', '12m']),
];

/// The segmented button that holds [option].
Finder segmentedHolding(String option) => find.ancestor(
  of: find.text(option),
  matching: find.byWidgetPredicate((w) => w is SegmentedButton),
);

void main() {
  // @lat: [[mobile-tests#Single choices#Each single-choice group is a segmented button]]
  testWidgets('each single-choice group is one segmented button', (
    tester,
  ) async {
    for (final (name, location, options) in groups) {
      await editors.pumpAt(tester, location);
      expect(find.byType(ChoiceChip), findsNothing, reason: name);
      final control = segmentedHolding(options.first);
      await tester.ensureVisible(control);
      await tester.pumpAndSettle();
      expect(control, findsOneWidget, reason: name);
      for (final option in options) {
        expect(
          find.descendant(of: control, matching: find.text(option)),
          findsOneWidget,
          reason: '$name: $option',
        );
      }
    }
  });

  // @lat: [[mobile-tests#Single choices#Each is drawn 44 and full width with a check on the selection]]
  testWidgets('each is drawn 44, fills its column and checks its selection', (
    tester,
  ) async {
    for (final (name, location, options) in groups) {
      await editors.pumpAt(tester, location);
      final control = segmentedHolding(options.first);
      await tester.ensureVisible(control);
      await tester.pumpAndSettle();
      expect(sizes.segmentedOutlineHeight(tester, control), 44, reason: name);
      expect(
        tester.getSize(control).height,
        greaterThanOrEqualTo(48),
        reason: name,
      );
      final column = tester.getSize(
        find.ancestor(of: control, matching: find.byType(Column)).first,
      );
      expect(tester.getSize(control).width, column.width, reason: name);
      expect(
        find.descendant(of: control, matching: find.byIcon(Icons.check)),
        findsOneWidget,
        reason: name,
      );
    }
  });
}
