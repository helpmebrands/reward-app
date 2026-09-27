import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// Loads the SDK's Roboto, the family the Android text theme names, so a
/// label measures as it does on a device rather than in the test font,
/// whose glyphs are each a full em wide.
Future<void> loadRoboto() async {
  final fonts =
      '${Platform.environment['FLUTTER_ROOT']}'
      '/bin/cache/artifacts/material_fonts';
  final loader = FontLoader('Roboto');
  for (final face in ['Regular', 'Medium']) {
    final bytes = File('$fonts/Roboto-$face.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

/// Scrolls the page's lazy list until [finder] is built and on screen.
Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find
        .byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        )
        .first,
  );
  await tester.pumpAndSettle();
}

void main() {
  // @lat: [[mobile-tests#Single choices#Each single-choice group is a segmented button]]
  testWidgets('each single-choice group is one segmented button', (
    tester,
  ) async {
    for (final (name, location, options) in groups) {
      await editors.pumpAt(tester, location);
      expect(find.byType(ChoiceChip), findsNothing, reason: name);
      await reveal(tester, find.text(options.first));
      final control = segmentedHolding(options.first);
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
    await loadRoboto();
    for (final (name, location, options) in groups) {
      await editors.pumpAt(tester, location);
      await reveal(tester, find.text(options.first));
      final control = segmentedHolding(options.first);
      expect(sizes.segmentedOutlineHeight(tester, control), 44, reason: name);
      expect(
        tester.getSize(control).height,
        greaterThanOrEqualTo(48),
        reason: name,
      );
      // Full width: as wide as the column lets it be.
      final box = tester.renderObject<RenderBox>(control);
      expect(box.size.width, box.constraints.maxWidth, reason: name);
      expect(
        find.descendant(of: control, matching: find.byIcon(Icons.check)),
        findsOneWidget,
        reason: name,
      );
    }
  });
}
