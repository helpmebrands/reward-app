import 'package:domain/domain.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:reward/data/household_api.dart';
import 'package:reward/data/snapshot_store.dart';
import 'package:reward/logic/app_store.dart';
import 'package:reward/logic/ui_state.dart';
import 'package:reward/main.dart';
import 'package:reward/shell/router.dart';

import 'support/fake_api.dart';

/// Handing a card to someone it is shared with, from the card editor, over
/// the fake api.

const bob = Person(id: 'user-bob', name: 'Bob', email: 'bob@example.com');
const cat = Person(id: 'user-cat', name: 'Cat', email: 'cat@example.com');

/// A second card of the caller's own, which Cat sees and Bob does too.
const reserve = Card(
  id: 'card-2',
  issuer: 'Chase',
  product: 'Sapphire Reserve',
  network: CardNetwork.visa,
  kind: CardKind.personal,
  annualFeeCents: 79500,
  anniversaryOn: '2023-02-01',
  archived: false,
  createdAt: stamp,
  updatedAt: stamp,
);

Future<AppStore> pumpEditor(WidgetTester tester, FakeApi api) async {
  final store = AppStore(
    store: MemorySnapshotStore(),
    api: api,
    clock: () => DateTime(2026, 9, 16, 10),
  );
  await store.load();
  tester.view.physicalSize = const Size(402, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RewardApp(store: store, ui: UiState(), initialLocation: cardPath('card-1')),
  );
  await tester.pumpAndSettle();
  return store;
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

void main() {
  // @lat: [[mobile-tests#Card transfer#The owner gives a card to someone it is shared with]]
  testWidgets('the owner gives the card to someone it is shared with, after '
      'a confirmation', (tester) async {
    final api =
        FakeApi(data: serverHousehold().copyWith(cards: [card1, reserve]))
          ..given.addAll([
            const CardShare(
              person: bob,
              access: CardAccess.record,
              allCards: true,
            ),
            const CardShare(
              person: cat,
              access: CardAccess.view,
              allCards: false,
              cardIds: ['card-2'],
            ),
          ]);
    await pumpEditor(tester, api);

    await tapText(tester, 'Give this card to…');
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Cat'), findsNothing);
    await tapText(tester, 'Bob');
    expect(
      find.text('Bob will own this card. You’ll still see it.'),
      findsOneWidget,
    );
    await tapText(tester, 'Give it to Bob');

    expect(api.transfers, [(cardId: 'card-1', userId: 'user-bob')]);
    expect(find.text('Give this card to…'), findsNothing);
    expect(find.text('Only Bob can change this card.'), findsOneWidget);
  });

  // @lat: [[mobile-tests#Card transfer#A card that is not yours offers no transfer]]
  testWidgets('a card shared with you, or yours with nobody, offers none', (
    tester,
  ) async {
    await pumpEditor(
      tester,
      FakeApi(access: {'card-1': CardAccess.record}, people: {bob.id: bob}),
    );
    expect(find.text('Give this card to…'), findsNothing);

    await pumpEditor(tester, FakeApi());
    expect(find.text('Give this card to…'), findsNothing);
  });
}
