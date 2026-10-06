import 'package:domain/domain.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:reward/data/household_api.dart';
import 'package:reward/data/share.dart';
import 'package:reward/data/snapshot_store.dart';
import 'package:reward/logic/app_store.dart';
import 'package:reward/logic/session.dart';
import 'package:reward/logic/ui_state.dart';
import 'package:reward/main.dart';
import 'package:reward/screens/join_screen.dart';
import 'package:reward/screens/sign_in_screen.dart';
import 'package:reward/screens/today_screen.dart';
import 'package:reward/shell/router.dart';
import 'package:share_plus/share_plus.dart';

import 'sign_in_test.dart' show FakeAuth;
import 'support/fake_api.dart';

/// Sharing your cards and accepting shares: the Household section of
/// Settings with shares both ways, invites through the share sheet, the
/// join screen and its errors, over the fake api.

const bob = Person(id: 'user-bob', name: 'Bob', email: 'bob@example.com');
const alex = Person(id: 'user-alex', name: 'Alex', email: 'alex@example.com');

/// A second card of the caller's own, so two can be chosen.
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

/// Alex's Gold and its Uber Cash, which a share brings.
const alexCard = Card(
  id: 'card-alex',
  ownerId: 'user-alex',
  issuer: 'American Express',
  product: 'Gold',
  network: CardNetwork.amex,
  kind: CardKind.personal,
  annualFeeCents: 32500,
  anniversaryOn: '2024-05-01',
  archived: false,
  createdAt: stamp,
  updatedAt: stamp,
);

const alexCredit = Benefit(
  id: 'benefit-alex',
  cardId: 'card-alex',
  name: 'Uber Cash',
  category: BenefitCategory.rideshare,
  valueCents: 1000,
  cadence: Cadence.monthly,
  anchor: CycleAnchor.calendar,
  enrollmentRequired: false,
  redemptionSteps: [],
  active: true,
  createdAt: stamp,
  updatedAt: stamp,
);

/// Alex's card in the household served, at view.
void seeAlex(FakeApi api) {
  api
    ..data = api.data.copyWith(
      cards: [...api.data.cards, alexCard],
      benefits: [...api.data.benefits, alexCredit],
    )
    ..access['card-alex'] = CardAccess.view
    ..people[alex.id] = alex;
}

Future<({AppStore store, FakeApi api, UiState ui})> pump(
  WidgetTester tester, {
  FakeApi? api,
  String location = Paths.settings,
  Session? session,
}) async {
  final served =
      api ??
      FakeApi(
        data: serverHousehold().copyWith(
          cards: [card1, reserve],
          benefits: [benefit1],
        ),
      );
  final store = AppStore(
    store: MemorySnapshotStore(),
    api: served,
    clock: () => DateTime(2026, 9, 16, 10),
  );
  await store.load();
  final ui = UiState();
  tester.view.physicalSize = const Size(402, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    RewardApp(
      store: store,
      ui: ui,
      session: session,
      initialLocation: location,
    ),
  );
  await tester.pumpAndSettle();
  return (store: store, api: served, ui: ui);
}

Finder key(String k) => find.byKey(Key(k));

Future<void> tapKey(WidgetTester tester, String k) async {
  await tester.ensureVisible(key(k));
  await tester.pumpAndSettle();
  await tester.tap(key(k));
  await tester.pumpAndSettle();
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

void main() {
  final shared = <ShareParams>[];
  setUp(() {
    shared.clear();
    share = (params) async => shared.add(params);
  });
  tearDown(() => share = shareWithSheet);

  /// "Share your cards" at the defaults: view, all cards.
  Future<FakeApi> shareAll(WidgetTester tester) async {
    final app = await pump(tester);
    await tapKey(tester, 'share-cards');
    await tapText(tester, 'Create and share');
    expect(app.api.invites, [(access: CardAccess.view, cardIds: null)]);
    expect(find.text('ABCD2345'), findsOneWidget);
    return app.api;
  }

  // @lat: [[mobile-tests#Household sharing#Sharing all your cards opens the share sheet on iOS]]
  testWidgets('on iOS sharing all cards to view shares the link alone', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await shareAll(tester);

    final params = shared.single;
    expect(params.uri, Uri.parse('https://api.test/invite/ABCD2345'));
    expect(params.text, isNull);
    expect(params.previewThumbnail, isNull);
    expect(params.sharePositionOrigin, isNotNull);
    debugDefaultTargetPlatformOverride = null;
  });

  // @lat: [[mobile-tests#Household sharing#Sharing your cards on Android sends the message]]
  testWidgets('on Android the share sheet gets the message and the icon', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await shareAll(tester);

    final params = shared.single;
    expect(params.uri, isNull);
    expect(
      params.text,
      'Help me stop leaving card rewards on the table. Join my household on '
      "HelpMe Reward and we'll track every credit together, so none expire "
      'unused.\n'
      'Code: ABCD2345\n'
      'https://api.test/invite/ABCD2345',
    );
    expect(params.title, 'Join my household on HelpMe Reward');
    expect(params.subject, 'Join my household on HelpMe Reward');
    final thumbnail = params.previewThumbnail!;
    expect(thumbnail.mimeType, 'image/png');
    final bytes = await tester.runAsync(thumbnail.readAsBytes);
    expect(bytes!.take(4), [0x89, 0x50, 0x4E, 0x47]);
    debugDefaultTargetPlatformOverride = null;
  });

  // @lat: [[mobile-tests#Household sharing#Chosen cards send their ids]]
  testWidgets('choosing two cards to record sends their ids', (tester) async {
    final app = await pump(tester);
    await tapKey(tester, 'share-cards');
    await tapText(tester, 'Can record usage');
    await tapText(tester, 'Chosen cards');
    await tapText(tester, 'American Express Gold');
    await tapText(tester, 'Chase Sapphire Reserve');
    await tapText(tester, 'Create and share');
    expect(app.api.invites, [
      (access: CardAccess.record, cardIds: ['card-1', 'card-2']),
    ]);
    expect(shared, hasLength(1));
  });

  // @lat: [[mobile-tests#Household sharing#The join screen says who shares what]]
  testWidgets('the join screen names the sharer, the cards and the access, '
      'and Accept lands on Today with them', (tester) async {
    final api = FakeApi()
      ..offer = const InviteOffer(
        owner: alex,
        access: CardAccess.record,
        allCards: false,
        cardCount: 2,
      )
      ..onAccept = seeAlex;
    final app = await pump(tester, api: api, location: '/invite/ABCD2345');
    expect(
      find.text('Alex wants to share 2 of their cards with you.'),
      findsOneWidget,
    );
    expect(
      find.text('You’ll be able to view them and record what you use.'),
      findsOneWidget,
    );

    await tapKey(tester, 'accept');
    expect(api.accepted, ['ABCD2345']);
    expect(find.byType(TodayScreen), findsOneWidget);
    expect(find.text('Uber Cash'), findsOneWidget);
    expect(app.ui.snackbar.current?.text, 'You can see Alex’s cards now.');
  });

  // @lat: [[mobile-tests#Household sharing#An invite to all cards to view says so]]
  testWidgets('an invite to all cards at view reads that way', (tester) async {
    await pump(tester, location: '/invite/ABCD2345');
    expect(
      find.text('Alex wants to share all their cards with you.'),
      findsOneWidget,
    );
    expect(find.text('You’ll be able to view them.'), findsOneWidget);
  });

  // @lat: [[mobile-tests#Household sharing#Used, expired, own and already-shared codes say why]]
  testWidgets('used, expired, unknown, own and already-shared codes each say '
      'why and stay', (tester) async {
    for (final (answer, message) in [
      (const ApiError(410, 'invite expired'), 'This invite has expired.'),
      (const ApiError(410, 'invite used'), 'This invite has been used.'),
      (const ApiError(404, 'not found'), 'No invite has that code.'),
    ]) {
      final api = FakeApi()..readAnswer = answer;
      await pump(tester, api: api, location: '/invite/ABCD2345');
      expect(find.byType(JoinScreen), findsOneWidget);
      expect(find.textContaining(message), findsOneWidget);
      expect(key('accept'), findsNothing);
    }
    for (final (answer, message) in [
      (const ApiError(409, 'own invite'), 'This is your own invite.'),
      (
        const ApiError(409, 'already shared'),
        'Alex already shares cards with you.',
      ),
    ]) {
      final api = FakeApi()..acceptAnswer = answer;
      await pump(tester, api: api, location: '/invite/ABCD2345');
      await tapKey(tester, 'accept');
      expect(find.byType(JoinScreen), findsOneWidget);
      expect(find.textContaining(message), findsOneWidget);
    }
  });

  // @lat: [[mobile-tests#Household sharing#Changing a share updates its line]]
  testWidgets('changing a share updates its line', (tester) async {
    final api =
        FakeApi(data: serverHousehold().copyWith(cards: [card1, reserve]))
          ..given.add(
            const CardShare(
              person: bob,
              access: CardAccess.view,
              allCards: true,
            ),
          );
    await pump(tester, api: api);
    expect(find.text('People who see your cards'), findsOneWidget);
    expect(find.text('All cards · View'), findsOneWidget);

    await tapKey(tester, 'given-user-bob');
    await tapText(tester, 'Can record usage');
    await tapText(tester, 'Save');
    expect(api.changes, [
      (memberId: 'user-bob', access: CardAccess.record, cardIds: null),
    ]);
    expect(find.text('All cards · Can record usage'), findsOneWidget);
  });

  // @lat: [[mobile-tests#Household sharing#Stopping sharing asks first]]
  testWidgets('stopping sharing asks first, then removes the person', (
    tester,
  ) async {
    final api = FakeApi()
      ..given.add(
        const CardShare(
          person: bob,
          access: CardAccess.record,
          allCards: false,
          cardIds: ['card-1'],
        ),
      );
    await pump(tester, api: api);
    expect(find.text('1 card · Can record usage'), findsOneWidget);

    await tapKey(tester, 'given-user-bob');
    await tapKey(tester, 'stop-sharing');
    expect(find.text('Stop sharing with Bob?'), findsOneWidget);
    await tapText(tester, 'Stop sharing');
    expect(api.stoppedSharing, ['user-bob']);
    expect(find.text('Bob'), findsNothing);
    expect(find.text('Nobody sees your cards yet.'), findsOneWidget);
  });

  // @lat: [[mobile-tests#Household sharing#Stopping seeing removes their cards]]
  testWidgets('"Stop seeing their cards" takes them off Today at once', (
    tester,
  ) async {
    final api = FakeApi()
      ..received.add(
        const CardShare(person: alex, access: CardAccess.view, allCards: true),
      );
    seeAlex(api);
    final app = await pump(tester, api: api);
    expect(find.text('Shared with you'), findsOneWidget);
    expect(find.text('All cards · View'), findsOneWidget);

    await tapKey(tester, 'received-user-alex');
    await tapText(tester, 'Stop seeing their cards');
    expect(api.stoppedSeeing, ['user-alex']);
    expect(
      app.store.data!.cards.map((c) => c.id),
      isNot(contains('card-alex')),
    );

    await tester.pumpWidget(
      RewardApp(store: app.store, ui: app.ui, initialLocation: Paths.today),
    );
    await tester.pumpAndSettle();
    expect(find.text('Uber Cash'), findsNothing);
  });

  // @lat: [[mobile-tests#Household sharing#A code opens the join screen]]
  testWidgets('entering a code opens the join screen for it', (tester) async {
    await pump(tester);
    await tapKey(tester, 'have-code');
    await tester.enterText(key('invite-code-field'), 'abcd2345');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.byType(JoinScreen), findsOneWidget);
    expect(find.text('ABCD2345'), findsOneWidget);
  });

  // @lat: [[mobile-tests#Household sharing#A link opens the join screen]]
  testWidgets('an invite link opens the join screen for its code', (
    tester,
  ) async {
    await pump(tester, location: '/invite/ZZZZ2222');
    expect(find.byType(JoinScreen), findsOneWidget);
    expect(find.text('ZZZZ2222'), findsOneWidget);
  });

  // @lat: [[mobile-tests#Household sharing#A signed-out link joins after sign-in]]
  testWidgets('a signed-out person who opens a link joins after signing in', (
    tester,
  ) async {
    final auth = FakeAuth();
    final session = Session(auth: auth, intro: MemoryIntroStore(seen: true));
    await session.load();
    await pump(tester, location: '/invite/ZZZZ2222', session: session);
    expect(find.byType(SignInScreen), findsOneWidget);

    await tapKey(tester, 'sign-in-google');
    expect(find.byType(JoinScreen), findsOneWidget);
    expect(find.text('ZZZZ2222'), findsOneWidget);
  });
}
