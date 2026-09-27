import 'package:domain/domain.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:reward/data/household_api.dart';
import 'package:reward/data/snapshot_store.dart';
import 'package:reward/logic/app_store.dart';
import 'package:reward/logic/ui_state.dart';
import 'package:reward/main.dart';
import 'package:reward/screens/add_card_screen.dart';
import 'package:reward/screens/cards_screen.dart';
import 'package:reward/screens/credits_screen.dart';
import 'package:reward/screens/value_screen.dart';
import 'package:reward/shell/router.dart';

import 'support/fake_api.dart';

/// Credits, Cards and Value before any active card: each says so and offers
/// the same Add button as Today's empty state.

final addButton = find.byKey(const Key('empty-add-card'));

/// Each tab with its screen and the words its empty state keeps.
final tabs = [
  (Paths.credits, CreditsScreen, 'No cards yet, so no credits to track.'),
  (Paths.cards, CardsScreen, 'Start with one card'),
  (Paths.value, ValueScreen, 'this screen shows what you captured'),
];

Future<void> pumpAt(
  WidgetTester tester,
  String location, {
  AppData? data,
  FakeApi? api,
}) async {
  final store = AppStore(
    store: MemorySnapshotStore(api == null ? (data ?? emptyAppData()) : null),
    api: api,
    clock: () => DateTime(2026, 9, 16, 10),
  );
  await store.load();
  tester.view.physicalSize = const Size(402, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    RewardApp(store: store, ui: UiState(), initialLocation: location),
  );
  await tester.pumpAndSettle();
}

Finder label(String text) =>
    find.descendant(of: addButton, matching: find.text(text));

void main() {
  // @lat: [[mobile-tests#Empty tabs#Each tab offers Add your first card]]
  testWidgets('each tab shows its empty message and one Add button', (
    tester,
  ) async {
    for (final (path, screen, words) in tabs) {
      await pumpAt(tester, path);
      expect(find.byType(screen), findsOneWidget, reason: path);
      expect(find.textContaining(words), findsOneWidget, reason: path);
      expect(label('Add your first card'), findsOneWidget, reason: path);
      expect(tester.getSize(addButton).height, greaterThanOrEqualTo(48));
    }
    // Credits says there are no cards, not that the filter matched nothing.
    await pumpAt(tester, Paths.credits);
    expect(find.text('Nothing matches that filter.'), findsNothing);
    // Cards has one Add control, not the catalogue button as well.
    await pumpAt(tester, Paths.cards);
    expect(find.byKey(const Key('add-card')), findsNothing);
  });

  // @lat: [[mobile-tests#Empty tabs#The button opens the catalogue and Back returns to the tab]]
  testWidgets('the button pushes the catalogue and Back returns', (
    tester,
  ) async {
    for (final (path, screen, _) in tabs) {
      await pumpAt(tester, path);
      await tester.tap(addButton);
      await tester.pumpAndSettle();
      expect(find.byType(AddCardScreen), findsOneWidget, reason: path);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(AddCardScreen), findsNothing, reason: path);
      expect(find.byType(screen), findsOneWidget, reason: path);
    }
  });

  // @lat: [[mobile-tests#Empty tabs#Archived cards read Add a card and readers get none]]
  testWidgets('archived-only reads Add a card; a reader sees none', (
    tester,
  ) async {
    final archived = emptyAppData().copyWith(
      cards: [card1.copyWith(archived: true)],
    );
    for (final (path, _, _) in tabs) {
      await pumpAt(tester, path, data: archived);
      expect(label('Add a card'), findsOneWidget, reason: path);

      await pumpAt(
        tester,
        path,
        api: FakeApi(data: emptyAppData(), role: MemberRole.reader),
      );
      expect(addButton, findsNothing, reason: path);
    }
  });
}
