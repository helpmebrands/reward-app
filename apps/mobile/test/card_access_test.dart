import 'package:domain/domain.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:reward/data/claim_outbox.dart';
import 'package:reward/data/household_api.dart';
import 'package:reward/data/household_cache.dart';
import 'package:reward/data/snapshot_store.dart';
import 'package:reward/logic/app_store.dart';
import 'package:reward/logic/ui_state.dart';
import 'package:reward/main.dart';
import 'package:reward/shell/router.dart';
import 'package:reward/widgets/credit_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_api.dart';

/// What a person can do with each card, and whose card it is: the access
/// and the owners' names the snapshot carries, over the fake api, beside a
/// Gold of the caller's own.

final now = DateTime(2026, 9, 16, 10);

const alex = Person(id: 'user-alex', name: 'Alex', email: 'alex@example.com');

/// Alex's Platinum, linked to the catalogue and labelled "Platinum".
const alexCard = Card(
  id: 'card-alex',
  ownerId: 'user-alex',
  templateId: 'amex-platinum',
  issuer: 'American Express',
  product: 'Platinum',
  label: 'Platinum',
  network: CardNetwork.amex,
  kind: CardKind.personal,
  annualFeeCents: 69500,
  anniversaryOn: '2024-03-14',
  archived: false,
  createdAt: stamp,
  updatedAt: stamp,
);

const alexCredit = Benefit(
  id: 'benefit-alex',
  cardId: 'card-alex',
  templateBenefitId: 'amex-platinum/uber-cash',
  name: 'Uber Cash',
  category: BenefitCategory.rideshare,
  valueCents: 1500,
  cadence: Cadence.monthly,
  anchor: CycleAnchor.calendar,
  enrollmentRequired: false,
  redemptionSteps: [],
  active: true,
  createdAt: stamp,
  updatedAt: stamp,
);

/// The caller's unlabelled Gold and Alex's Platinum.
AppData sharedData({Card platinum = alexCard}) => serverHousehold().copyWith(
  cards: [card1, platinum],
  benefits: [benefit1, alexCredit],
);

/// Alex shares the Platinum with the caller at [access].
FakeApi sharedApi(CardAccess access, {Card platinum = alexCard}) => FakeApi(
  data: sharedData(platinum: platinum),
  access: {'card-alex': access},
  people: {alex.id: alex},
);

AppStore remoteStore(FakeApi api, {HouseholdCache? cache}) => AppStore(
  store: MemorySnapshotStore(),
  api: api,
  cache: cache ?? MemoryHouseholdCache(),
  outbox: MemoryClaimOutbox(),
  clock: () => now,
);

Future<UiState> pumpAt(
  WidgetTester tester,
  AppStore store,
  String location,
) async {
  final ui = UiState();
  tester.view.physicalSize = const Size(402, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    RewardApp(store: store, ui: ui, initialLocation: location),
  );
  await tester.pumpAndSettle();
  return ui;
}

CreditRow rowNamed(WidgetTester tester, String name) => tester.widget(
  find.ancestor(of: find.text(name), matching: find.byType(CreditRow)).first,
);

void main() {
  // @lat: [[mobile-tests#Card access#A card shared to view logs nothing]]
  testWidgets('on Alex’s card at view nothing logs, and an attempt says '
      'whose card it is', (tester) async {
    final api = sharedApi(CardAccess.view);
    final store = remoteStore(api);
    await store.load();
    expect(store.accessTo('card-alex'), CardAccess.view);
    expect(store.accessTo('card-1'), CardAccess.owner);

    final ui = await pumpAt(tester, store, Paths.today);
    expect(rowNamed(tester, 'Uber Cash').onLogAll, isNull);
    expect(rowNamed(tester, 'Uber Cash').onOptOut, isNull);
    expect(rowNamed(tester, 'Uber Cash').onToggleMute, isNotNull);
    expect(rowNamed(tester, 'Dining Credit').onLogAll, isNotNull);

    await tester.tap(find.text('Uber Cash'));
    await tester.pumpAndSettle();
    expect(find.text('PLATINUM · ALEX'), findsOneWidget);
    expect(find.text('Log what you spent'), findsNothing);
    expect(find.textContaining('Mark the full'), findsNothing);
    expect(find.text('Edit this credit'), findsNothing);
    expect(find.text('Notification levels'), findsOneWidget);

    await expectLater(
      store.claim(store.instanceFor('benefit-alex')!),
      throwsStateError,
    );
    await tester.pumpAndSettle();
    expect(
      ui.snackbar.current?.text,
      'You can view Alex’s card but not '
      'change it.',
    );
    expect(api.claimPosts, 0);
  });

  // @lat: [[mobile-tests#Card access#A card shared to record logs but stays the owner's]]
  testWidgets('at record logging works, and the card itself is read-only', (
    tester,
  ) async {
    final api = sharedApi(CardAccess.record);
    final store = remoteStore(api);
    await store.load();

    await pumpAt(tester, store, Paths.today);
    expect(rowNamed(tester, 'Uber Cash').onLogAll, isNotNull);
    await tester.tap(find.text('Uber Cash'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Mark the full'));
    await tester.pumpAndSettle();
    expect(api.claimPosts, 1);
    expect(api.data.claims.single.benefitId, 'benefit-alex');

    final ui = await pumpAt(tester, store, cardPath('card-alex'));
    for (final field in ['field-label', 'field-fee', 'field-anniversary']) {
      expect(
        tester.widget<TextField>(find.byKey(Key(field))).readOnly,
        isTrue,
        reason: field,
      );
    }
    expect(find.text('Archive this card'), findsNothing);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
    expect(find.byKey(const Key('change-terms')), findsNothing);
    expect(find.text('Only Alex can change this card.'), findsOneWidget);
    expect(find.text('Silence every credit'), findsOneWidget);

    expect(
      await store.updateCard('card-alex', (c) => c.copyWith(label: 'Mine')),
      isFalse,
    );
    await tester.pumpAndSettle();
    expect(ui.snackbar.current?.text, 'Only Alex can change this card.');
    expect(api.data.cards.last.label, 'Platinum');
  });

  // @lat: [[mobile-tests#Card access#Cards names whose cards they are]]
  testWidgets('Cards lists Alex’s cards under "Alex’s cards" as "Platinum · '
      'Alex"', (tester) async {
    final store = remoteStore(sharedApi(CardAccess.view));
    await store.load();
    await pumpAt(tester, store, Paths.cards);

    expect(find.text('Alex’s cards'), findsOneWidget);
    expect(find.text('Platinum · Alex'), findsOneWidget);
    final shared = tester.getTopLeft(find.text('Alex’s cards')).dy;
    expect(
      tester.getTopLeft(find.text('Platinum · Alex')).dy,
      greaterThan(shared),
    );
    expect(
      tester.getTopLeft(find.text('American Express Gold')).dy,
      lessThan(shared),
    );
    // At view there is no way into Alex's card, but your own still adds.
    expect(find.text('Edit card and credits'), findsOneWidget);
    expect(find.byKey(const Key('add-card')), findsOneWidget);

    await pumpAt(tester, store, Paths.today);
    expect(find.textContaining('Platinum · Alex'), findsWidgets);
  });

  // @lat: [[mobile-tests#Card access#Labels count only your own cards]]
  testWidgets('a Platinum while Alex shares one gets no number; a second of '
      'your own does', (tester) async {
    final api = sharedApi(
      CardAccess.view,
      platinum: alexCard.copyWith(label: null),
    );
    final store = remoteStore(api);
    await store.load();
    Future<String> proposed() async {
      await pumpAt(tester, store, Paths.newCard);
      final platinum = find.byKey(const Key('template-amex-platinum'));
      await tester.scrollUntilVisible(platinum, 200);
      await tester.tap(platinum);
      await tester.pumpAndSettle();
      return tester
          .widget<TextField>(find.byKey(const Key('field-label')))
          .controller!
          .text;
    }

    expect(await proposed(), '');
    await store.addCardFromTemplate(findTemplate('amex-platinum')!);
    expect(await proposed(), 'American Express Platinum (1)');
  });

  // @lat: [[mobile-tests#Card access#An offline launch keeps the access and the names]]
  test('an offline launch shows the cached access and owners', () async {
    SharedPreferences.setMockInitialValues({});
    const cache = SharedPreferencesHouseholdCache();
    final api = sharedApi(CardAccess.record);
    await remoteStore(api, cache: cache).load();

    api.online = false;
    final relaunched = remoteStore(api, cache: cache);
    await relaunched.load();
    expect(relaunched.offline, isTrue);
    expect(relaunched.accessTo('card-alex'), CardAccess.record);
    expect(relaunched.accessTo('card-1'), CardAccess.owner);
    expect(relaunched.cardName(alexCard), 'Platinum · Alex');
    expect(relaunched.cardName(card1), 'American Express Gold');
  });

  // @lat: [[mobile-tests#Card access#Without an api every card is yours]]
  testWidgets('without an api every card is yours and editable', (
    tester,
  ) async {
    final store = AppStore(
      store: MemorySnapshotStore(sharedData()),
      clock: () => now,
    );
    await store.load();
    expect(store.accessTo('card-alex'), CardAccess.owner);
    expect(store.cardName(alexCard), 'Platinum');

    await pumpAt(tester, store, cardPath('card-alex'));
    expect(
      tester.widget<TextField>(find.byKey(const Key('field-label'))).readOnly,
      isFalse,
    );
    expect(find.text('Archive this card'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    expect(find.byKey(const Key('change-terms')), findsOneWidget);
  });
}
