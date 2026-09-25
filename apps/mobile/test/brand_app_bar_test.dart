import 'dart:convert';
import 'dart:io';

import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reward/data/snapshot_store.dart';
import 'package:reward/logic/app_store.dart';
import 'package:reward/logic/ui_state.dart';
import 'package:reward/main.dart';
import 'package:reward/screens/settings_screen.dart';
import 'package:reward/widgets/brand_lockup.dart';

/// The one brand app bar the four tabs share: the lockup on the left, the
/// Settings gear on the right, 64 high, over the content column only.

AppData sampleHousehold() => appDataFromJson(
  jsonDecode(
        File(
          '../../packages/domain/test/fixtures/sample-household.json',
        ).readAsStringSync(),
      )
      as Map<String, dynamic>,
);

const tabs = ['Today', 'Credits', 'Cards', 'Value'];

Future<void> pumpApp(WidgetTester tester, Size size) async {
  final store = AppStore(
    store: MemorySnapshotStore(sampleHousehold()),
    clock: () => DateTime(2026, 9, 16, 8),
  );
  await store.load();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(RewardApp(store: store, ui: UiState()));
  await tester.pumpAndSettle();
}

Future<void> openTab(WidgetTester tester, String label) async {
  final bar = find.byType(NavigationBar);
  final nav = bar.evaluate().isNotEmpty ? bar : find.byType(NavigationRail);
  await tester.tap(find.descendant(of: nav, matching: find.text(label)));
  await tester.pumpAndSettle();
}

Finder get appBar => find.byType(AppBar);

Finder get barContent => find.byKey(const Key('brand-app-bar'));

Finder get column => find.byKey(const Key('content-column'));

Finder get settingsButton => find.bySemanticsLabel('Settings');

Color barColour(WidgetTester tester) => tester
    .widget<Material>(
      find.descendant(of: appBar, matching: find.byType(Material)).first,
    )
    .color!;

void main() {
  // @lat: [[mobile-tests#Brand app bar#Every tab has the one bar and its gear]]
  testWidgets('each tab has one Settings button, in a 64-high bar', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpApp(tester, const Size(402, 874));
    for (final tab in tabs) {
      await openTab(tester, tab);
      expect(appBar, findsOneWidget, reason: tab);
      expect(tester.getSize(appBar).height, 64, reason: tab);
      expect(settingsButton, findsOneWidget, reason: tab);
      expect(
        find.descendant(of: appBar, matching: find.byType(IconButton)),
        findsOneWidget,
        reason: tab,
      );
      expect(
        find.descendant(of: appBar, matching: find.byType(BrandLockup)),
        findsOneWidget,
        reason: tab,
      );
    }
    handle.dispose();
  });

  // @lat: [[mobile-tests#Brand app bar#Today's heading draws the eyebrow]]
  testWidgets('Today draws the date and eyebrow as its heading', (
    tester,
  ) async {
    await pumpApp(tester, const Size(402, 874));
    expect(find.text('WED 16 SEP · UNCLAIMED, OPEN PERIODS'), findsOneWidget);
    expect(find.text('HelpMe Reward'), findsNothing);
  });

  // @lat: [[mobile-tests#Brand app bar#The gear opens Settings and back returns to the tab]]
  testWidgets('the gear opens Settings and back returns to that tab', (
    tester,
  ) async {
    await pumpApp(tester, const Size(402, 874));
    for (final tab in ['Credits', 'Cards', 'Value']) {
      await openTab(tester, tab);
      final screen = find.byType(NavigationBar);
      final selected = tester.widget<NavigationBar>(screen).selectedIndex;
      await tester.tap(settingsButton);
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget, reason: tab);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsNothing, reason: tab);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        selected,
        reason: tab,
      );
    }
  });

  // @lat: [[mobile-tests#Brand app bar#From medium the bar sits over the column, not the rail]]
  testWidgets('at 768 and 1280 the bar starts at the column, past the rail', (
    tester,
  ) async {
    for (final size in const [Size(768, 1024), Size(1280, 800)]) {
      await pumpApp(tester, size);
      final rail = tester.getRect(find.byType(NavigationRail));
      expect(
        tester.getTopLeft(barContent).dx,
        tester.getTopLeft(column).dx,
        reason: '$size',
      );
      expect(
        tester.getTopRight(barContent).dx,
        tester.getTopRight(column).dx,
        reason: '$size',
      );
      expect(tester.getTopLeft(appBar).dx, greaterThanOrEqualTo(rail.right));
      expect(tester.getSize(appBar).height, 64);
    }
  });

  // @lat: [[mobile-tests#Brand app bar#The bar tints once content scrolls under it]]
  testWidgets('the bar is the page colour at rest and tints when scrolled', (
    tester,
  ) async {
    await pumpApp(tester, const Size(402, 874));
    await openTab(tester, 'Credits');
    final theme = Theme.of(tester.element(appBar));
    expect(barColour(tester), theme.scaffoldBackgroundColor);

    await tester.drag(find.byType(ListView).last, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(barColour(tester), theme.colorScheme.surfaceContainer);
    expect(
      theme.colorScheme.surfaceContainer,
      isNot(theme.scaffoldBackgroundColor),
    );
  });

  // @lat: [[mobile-tests#Brand app bar#On a phone the lockup sits on the 20 margin]]
  testWidgets('at 402 the lockup starts 20 from the edge', (tester) async {
    await pumpApp(tester, const Size(402, 874));
    expect(tester.getTopLeft(find.byType(BrandLockup)).dx, 20);
    final gear = tester.getRect(
      find.descendant(of: appBar, matching: find.byType(Icon)),
    );
    expect(gear.right, 402 - 20);
    expect(gear.width, 24);
  });
}
