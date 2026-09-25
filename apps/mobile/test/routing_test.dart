import 'dart:convert';
import 'dart:io';

import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:reward/data/snapshot_store.dart';
import 'package:reward/logic/app_store.dart';
import 'package:reward/logic/ui_state.dart';
import 'package:reward/main.dart';
import 'package:reward/screens/benefit_editor_screen.dart';
import 'package:reward/screens/not_found_screen.dart';
import 'package:reward/screens/today_screen.dart';
import 'package:reward/shell/router.dart';
import 'package:reward/widgets/screen_title.dart';

/// Routing polish the PWA's shell owns: a not-found screen, one heading and
/// title per screen, focus on navigation, and a notification payload that
/// opens its screen.

/// The PWA's sample household, its two Platinums labelled with the names
/// the PWA shows for them, so the PWA's fixtures still apply.
AppData sampleHousehold() {
  final data = appDataFromJson(
    jsonDecode(File('../pwa/samples/sample-household.json').readAsStringSync())
        as Map<String, dynamic>,
  );
  const labels = {
    'card-0001': 'American Express Platinum — Jim',
    'card-0002': 'American Express Platinum — Kathy',
  };
  return data.copyWith(
    cards: [for (final c in data.cards) c.copyWith(label: labels[c.id])],
  );
}

final DateTime now = DateTime(2026, 9, 16, 8);

Future<UiState> pumpAt(WidgetTester tester, String location) async {
  final store = AppStore(
    store: MemorySnapshotStore(sampleHousehold()),
    clock: () => now,
  );
  await store.load();
  final ui = UiState();
  tester.view.physicalSize = const Size(402, 874);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    RewardApp(store: store, ui: ui, initialLocation: location),
  );
  await tester.pumpAndSettle();
  return ui;
}

GoRouter router(WidgetTester tester) =>
    GoRouter.of(tester.element(find.byType(Scaffold).first));

/// The nodes marked as level-one headings, in traversal order.
List<SemanticsNode> headings(WidgetTester tester) {
  final out = <SemanticsNode>[];
  void visit(SemanticsNode node) {
    if (node.getSemanticsData().headingLevel == 1) out.add(node);
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
  return out;
}

String windowTitle(WidgetTester tester) =>
    tester.widgetList<Title>(find.byType(Title)).last.title;

void main() {
  // @lat: [[mobile-tests#Routing#An unknown path shows the not-found screen with a way back]]
  testWidgets('/nowhere shows the not-found screen and its button leads home', (
    tester,
  ) async {
    await pumpAt(tester, '/nowhere');
    expect(find.byType(NotFoundScreen), findsOneWidget);
    expect(find.text('That screen does not exist.'), findsOneWidget);
    expect(windowTitle(tester), 'Not found · HelpMe Reward');

    await tester.tap(find.text('Back to Today'));
    await tester.pumpAndSettle();
    expect(find.byType(TodayScreen), findsOneWidget);
    expect(find.byType(NotFoundScreen), findsNothing);
  });

  // @lat: [[mobile-tests#Routing#Every route has exactly one heading and its title]]
  testWidgets('each of the nine routes has one level-one heading and a title', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    const routes = {
      '/': 'Today',
      '/credits': 'All credits',
      '/cards': 'Cards',
      '/value': 'Value',
      '/cards/new': 'Add a card',
      '/cards/card-0001': 'American Express Platinum — Jim',
      '/benefit/ben-0003': 'Uber Cash',
      '/settings': 'Settings',
      '/nowhere': 'That screen does not exist.',
    };
    for (final MapEntry(key: location, value: title) in routes.entries) {
      await pumpAt(tester, location);
      final found = headings(tester);
      expect(found, hasLength(1), reason: location);
      expect(found.single.label, title, reason: location);
      expect(
        windowTitle(tester),
        location == '/nowhere'
            ? 'Not found · HelpMe Reward'
            : '$title · HelpMe Reward',
        reason: location,
      );
    }
    handle.dispose();
  });

  // @lat: [[mobile-tests#Routing#Navigation moves focus to the heading, a tab press keeps it]]
  testWidgets('go moves focus to the new heading; a tab press does not', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final ui = await pumpAt(tester, '/');

    router(tester).go(Paths.credits);
    await tester.pumpAndSettle();
    final creditsTitle = find.byWidgetPredicate(
      (w) => w is ScreenTitle && w.label == 'All credits',
    );
    expect(creditsTitle, findsOneWidget);
    expect(
      tester.state<ScreenTitleState>(creditsTitle).focusNode.hasPrimaryFocus,
      isTrue,
    );

    // A press on the bar: the new heading does not take focus. The Credits
    // heading cannot keep it either, since its branch is hidden, so what is
    // asserted is that no heading holds it.
    await tester.tap(find.text('Cards'));
    await tester.pumpAndSettle();
    final cardsTitle = find.byWidgetPredicate(
      (w) => w is ScreenTitle && w.label == 'Cards',
    );
    expect(
      tester.state<ScreenTitleState>(cardsTitle).focusNode.hasPrimaryFocus,
      isFalse,
    );
    expect(ui.headings.values.any((node) => node.hasPrimaryFocus), isFalse);
    handle.dispose();
  });

  // @lat: [[mobile-tests#Routing#A notification payload opens its screen]]
  testWidgets('the notification handler opens the editor above the shell', (
    tester,
  ) async {
    await pumpAt(tester, '/');

    handleNotificationTap(router(tester), {'url': '/benefit/ben-0003'});
    await tester.pumpAndSettle();
    expect(find.byType(BenefitEditorScreen), findsOneWidget);
    expect(find.text('Uber Cash'), findsWidgets);

    // The editor is above the shell: back leaves it.
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.byType(BenefitEditorScreen), findsNothing);

    // Anything but a path is ignored.
    handleNotificationTap(router(tester), {'url': 'https://elsewhere'});
    handleNotificationTap(router(tester), null);
    await tester.pumpAndSettle();
    expect(find.byType(BenefitEditorScreen), findsNothing);
  });
}
