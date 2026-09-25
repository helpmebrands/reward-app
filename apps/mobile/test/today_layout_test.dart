import 'dart:convert';
import 'dart:io';

import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reward/data/snapshot_store.dart';
import 'package:reward/logic/app_store.dart';
import 'package:reward/screens/today_screen.dart';
import 'package:reward/shell/width_class.dart';
import 'package:reward/theme/theme.dart';
import 'package:reward/widgets/credit_row.dart';

/// Today's re-flow at the wider width classes of `design#Responsive layout`:
/// the overlap cards pair from medium, the body splits in two from expanded,
/// and the screen reader hears the phone order at every width.

AppData sampleHousehold() => appDataFromJson(
  jsonDecode(
        File(
          '../../packages/domain/test/fixtures/sample-household.json',
        ).readAsStringSync(),
      )
      as Map<String, dynamic>,
);

/// Today bare, inside a width class scope, with a tall viewport so every
/// section is laid out.
Future<void> pumpToday(WidgetTester tester, WidthClass widthClass) async {
  final store = AppStore(
    store: MemorySnapshotStore(sampleHousehold()),
    clock: () => DateTime(2026, 9, 16),
  );
  await store.load();
  tester.view.physicalSize = Size(widthClass.column, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: nocturneTheme(Brightness.dark),
      home: Scaffold(
        body: WidthClassScope(
          widthClass: widthClass,
          child: TodayScreen(store: store),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder overlapCards() =>
    find.byWidgetPredicate((w) => w.runtimeType.toString() == '_OverlapCard');

Finder sectionTitle(String text) => find.textContaining(text);

/// Every label in the semantics tree, in traversal order: what a screen
/// reader would read, top to bottom.
List<String> spokenOrder(WidgetTester tester) {
  final root = tester.getSemantics(find.byType(ListView));
  final labels = <String>[];
  void visit(SemanticsNode node) {
    if (node.label.isNotEmpty) labels.add(node.label);
    for (final child in node.debugListChildrenInOrder(
      DebugSemanticsDumpOrder.traversalOrder,
    )) {
      visit(child);
    }
  }

  visit(root);
  return labels;
}

void main() {
  // @lat: [[mobile-tests#Today#Medium pairs the overlap cards]]
  testWidgets('medium: the overlap cards sit two across', (tester) async {
    await pumpToday(tester, WidthClass.medium);
    final cards = overlapCards();
    expect(cards, findsNWidgets(3));
    final first = tester.getRect(cards.at(0));
    final second = tester.getRect(cards.at(1));
    final third = tester.getRect(cards.at(2));
    expect(second.top, first.top);
    expect(second.left, greaterThan(first.right));
    expect(third.top, greaterThan(first.bottom));
    expect(third.left, first.left);

    await pumpToday(tester, WidthClass.compact);
    final stacked = overlapCards();
    expect(
      tester.getRect(stacked.at(1)).top,
      greaterThan(tester.getRect(stacked.at(0)).bottom),
    );
  });

  // @lat: [[mobile-tests#Today#Expanded splits the body in two under the headline]]
  testWidgets('expanded: two columns with the headline across both', (
    tester,
  ) async {
    await pumpToday(tester, WidthClass.expanded);
    const pad = 28.0;
    const inner = 720 - 2 * pad;
    final centre = pad + inner / 2;
    expect(
      tester.getSize(find.byKey(const Key('today-headline'))).width,
      inner,
    );
    final soonTitle = tester.getTopLeft(sectionTitle('Use soon'));
    final capturedTitle = tester.getTopLeft(
      sectionTitle('Captured this period'),
    );
    final lockedTitle = tester.getTopLeft(
      sectionTitle('Locked behind enrolment'),
    );
    expect(soonTitle.dx, pad);
    expect(capturedTitle.dx, pad);
    expect(lockedTitle.dx, greaterThan(centre));
    expect(lockedTitle.dy, soonTitle.dy);
    // Rows in the first column stay narrower than the column's half.
    expect(
      tester.getRect(find.byType(CreditRow).first).right,
      lessThan(centre),
    );
  });

  // @lat: [[mobile-tests#Today#The screen reader hears the phone order at every width]]
  testWidgets('semantics traversal at 1280 is the traversal at 402', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpToday(tester, WidthClass.compact);
    final compact = spokenOrder(tester);
    await pumpToday(tester, WidthClass.expanded);
    final expanded = spokenOrder(tester);
    handle.dispose();
    expect(compact, isNotEmpty);
    expect(expanded, compact);
  });
}
