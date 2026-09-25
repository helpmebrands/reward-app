import 'dart:convert';
import 'dart:io';

import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reward/data/snapshot_store.dart';
import 'package:reward/logic/app_store.dart';
import 'package:reward/logic/ui_state.dart';
import 'package:reward/main.dart';
import 'package:reward/widgets/screen_title.dart';

/// The pushed routes keep Back and a title, in a bar as high as the tabs'
/// so the height does not jump between a tab and its sub-screens.

AppData sampleHousehold() => appDataFromJson(
  jsonDecode(
        File(
          '../../packages/domain/test/fixtures/sample-household.json',
        ).readAsStringSync(),
      )
      as Map<String, dynamic>,
);

/// Each pushed route and the heading its bar carries.
const routes = {
  '/settings': 'Settings',
  '/benefit/ben-0003': 'Uber Cash',
  '/cards/new': 'Add a card',
  '/cards/card-0001': 'American Express Platinum',
  '/cards/card-0001/convert': 'Change the terms',
};

Future<void> pumpAt(
  WidgetTester tester,
  String location, {
  Size size = const Size(402, 874),
}) async {
  final store = AppStore(
    store: MemorySnapshotStore(sampleHousehold()),
    clock: () => DateTime(2026, 9, 16, 8),
  );
  await store.load();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    RewardApp(store: store, ui: UiState(), initialLocation: location),
  );
  await tester.pumpAndSettle();
}

int levelOneHeadings(WidgetTester tester) {
  var count = 0;
  void visit(SemanticsNode node) {
    if (node.getSemanticsData().headingLevel == 1) count++;
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  var root = tester.getSemantics(find.byType(Scaffold).first);
  while (root.parent != null) {
    root = root.parent!;
  }
  visit(root);
  return count;
}

Finder get appBar => find.byType(AppBar);

Color barColour(WidgetTester tester) => tester
    .widget<Material>(
      find.descendant(of: appBar, matching: find.byType(Material)).first,
    )
    .color!;

void main() {
  // @lat: [[mobile-tests#Pushed route bars#Back and the title in a 64-high bar]]
  testWidgets('each pushed route has a 64-high bar with Back and its title', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    for (final MapEntry(key: location, value: title) in routes.entries) {
      await pumpAt(tester, location);
      expect(appBar, findsOneWidget, reason: location);
      expect(tester.getSize(appBar).height, 64, reason: location);
      expect(
        find.descendant(of: appBar, matching: find.byTooltip('Back')),
        findsOneWidget,
        reason: location,
      );
      final heading = find.descendant(
        of: appBar,
        matching: find.byType(ScreenTitle),
      );
      expect(heading, findsOneWidget, reason: location);
      expect(
        tester.widget<ScreenTitle>(heading).label,
        startsWith(title),
        reason: location,
      );
      expect(levelOneHeadings(tester), 1, reason: location);
    }
    handle.dispose();
  });

  // @lat: [[mobile-tests#Pushed route bars#No gear on a pushed route]]
  testWidgets('no pushed route has a Settings button', (tester) async {
    for (final location in routes.keys) {
      await pumpAt(tester, location);
      expect(find.byIcon(Icons.settings_outlined), findsNothing);
      expect(find.byTooltip('Settings'), findsNothing, reason: location);
    }
  });

  // @lat: [[mobile-tests#Pushed route bars#The same colours as the tab bar]]
  testWidgets('Settings bar is the page colour and tints when scrolled', (
    tester,
  ) async {
    // Short enough that Settings scrolls with reminders off.
    await pumpAt(tester, '/settings', size: const Size(402, 500));
    final theme = Theme.of(tester.element(appBar));
    expect(barColour(tester), theme.scaffoldBackgroundColor);

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await tester.pumpAndSettle();

    expect(barColour(tester), theme.colorScheme.surfaceContainer);
  });
}
