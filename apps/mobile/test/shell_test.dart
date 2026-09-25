import 'dart:convert';
import 'dart:io';

import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reward/data/snapshot_store.dart';
import 'package:reward/logic/app_store.dart';
import 'package:reward/main.dart';

/// The shell at the three width classes of `design#Responsive layout`.

AppData sampleHousehold() => appDataFromJson(
  jsonDecode(
        File(
          '../../packages/domain/test/fixtures/sample-household.json',
        ).readAsStringSync(),
      )
      as Map<String, dynamic>,
);

const order = ['Today', 'Credits', 'Cards', 'Value'];

Future<void> pumpShell(WidgetTester tester, Size size) async {
  final store = AppStore(
    store: MemorySnapshotStore(sampleHousehold()),
    clock: () => DateTime(2026, 9, 16),
  );
  await store.load();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(RewardApp(store: store));
  await tester.pumpAndSettle();
}

List<String> destinationLabels(WidgetTester tester) {
  final bar = find.byType(NavigationBar);
  if (bar.evaluate().isNotEmpty) {
    return tester
        .widget<NavigationBar>(bar)
        .destinations
        .map((d) => (d as NavigationDestination).label)
        .toList();
  }
  return tester
      .widget<NavigationRail>(find.byType(NavigationRail))
      .destinations
      .map((d) => (d.label as Text).data!)
      .toList();
}

Finder get column => find.byKey(const Key('content-column'));

double columnWidth(WidgetTester tester) => tester.getSize(column).width;

double columnCentre(WidgetTester tester) => tester.getCenter(column).dx;

EdgeInsets todayPadding(WidgetTester tester) =>
    tester.widget<ListView>(find.byType(ListView)).padding! as EdgeInsets;

void main() {
  // @lat: [[mobile-tests#Shell#Compact keeps the phone layout]]
  testWidgets('compact: a bottom bar and the full-width column', (
    tester,
  ) async {
    await pumpShell(tester, const Size(402, 874));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(destinationLabels(tester), order);
    expect(columnWidth(tester), 402);
    expect(todayPadding(tester), const EdgeInsets.all(20));
  });

  // @lat: [[mobile-tests#Shell#Medium shows the rail beside a 560 column]]
  testWidgets('medium: an 80-wide rail and a centred 560 column', (
    tester,
  ) async {
    await pumpShell(tester, const Size(768, 1024));
    expect(find.byType(NavigationBar), findsNothing);
    final rail = find.byType(NavigationRail);
    expect(rail, findsOneWidget);
    expect(tester.widget<NavigationRail>(rail).extended, isFalse);
    expect(
      tester.widget<NavigationRail>(rail).labelType,
      NavigationRailLabelType.all,
    );
    expect(tester.getTopLeft(rail).dx, 0);
    expect(tester.getSize(rail).width, 80);
    expect(tester.getSize(rail).height, 1024);
    expect(destinationLabels(tester), order);
    expect(columnWidth(tester), 560);
    expect(columnCentre(tester), 80 + (768 - 80) / 2);
    expect(todayPadding(tester), const EdgeInsets.all(24));
  });

  // @lat: [[mobile-tests#Shell#Expanded extends the rail beside a 720 column]]
  testWidgets('expanded: a 200-wide extended rail and a centred 720 column', (
    tester,
  ) async {
    await pumpShell(tester, const Size(1280, 800));
    expect(find.byType(NavigationBar), findsNothing);
    final rail = find.byType(NavigationRail);
    expect(tester.widget<NavigationRail>(rail).extended, isTrue);
    expect(tester.getTopLeft(rail).dx, 0);
    expect(tester.getSize(rail).width, 200);
    expect(destinationLabels(tester), order);
    expect(columnWidth(tester), 720);
    expect(columnCentre(tester), 200 + (1280 - 200) / 2);
    expect(todayPadding(tester), const EdgeInsets.all(28));
  });

  // @lat: [[mobile-tests#Shell#A destination opens its branch]]
  testWidgets('choosing Cards from the bar or the rail opens its branch', (
    tester,
  ) async {
    await pumpShell(tester, const Size(402, 874));
    final addCard = find.byKey(const Key('add-card'), skipOffstage: false);
    expect(addCard, findsNothing);
    await tester.tap(find.text('Cards'));
    await tester.pumpAndSettle();
    expect(addCard, findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      2,
    );

    await pumpShell(tester, const Size(768, 1024));
    await tester.tap(find.text('Value'));
    await tester.pumpAndSettle();
    expect(find.text('Cards against their own fee'), findsOneWidget);
    expect(
      tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex,
      3,
    );
  });
}
