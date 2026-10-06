import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:reward/data/household_api.dart';
import 'package:reward/data/snapshot_store.dart';
import 'package:reward/logic/app_store.dart';
import 'package:reward/logic/session.dart';
import 'package:reward/logic/ui_state.dart';
import 'package:reward/main.dart';
import 'package:reward/screens/join_screen.dart';
import 'package:reward/screens/sign_in_screen.dart';
import 'package:reward/screens/today_screen.dart';
import 'package:reward/shell/router.dart';

import 'sign_in_test.dart' show FakeAuth;
import 'support/fake_api.dart';

/// Joining by code or by link, and the errors, over the fake api.

Future<({AppStore store, FakeApi api, UiState ui})> pump(
  WidgetTester tester, {
  String location = Paths.settings,
  Session? session,
}) async {
  final api = FakeApi();
  final store = AppStore(
    store: MemorySnapshotStore(),
    api: api,
    clock: () => DateTime(2026, 9, 16, 10),
  );
  await store.load();
  final ui = UiState();
  tester.view.physicalSize = const Size(402, 1400);
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
  return (store: store, api: api, ui: ui);
}

Finder key(String k) => find.byKey(Key(k));

Future<void> tapKey(WidgetTester tester, String k) async {
  await tester.ensureVisible(key(k));
  await tester.pumpAndSettle();
  await tester.tap(key(k));
  await tester.pumpAndSettle();
}

void main() {
  // @lat: [[mobile-tests#Household sharing#Settings keeps only the invite code]]
  testWidgets('Settings has no member list or invite button', (tester) async {
    await pump(tester);
    expect(find.text('Household'), findsOneWidget);
    expect(key('have-code'), findsOneWidget);
    expect(key('invite'), findsNothing);
    expect(find.text('Owner'), findsNothing);
  });

  // @lat: [[mobile-tests#Household sharing#A code joins the household]]
  testWidgets('entering a valid code joins', (tester) async {
    final app = await pump(tester);
    await tapKey(tester, 'have-code');
    await tester.enterText(key('invite-code-field'), 'abcd2345');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.byType(JoinScreen), findsOneWidget);
    expect(find.text('ABCD2345'), findsOneWidget);

    await tapKey(tester, 'join');
    expect(app.api.accepted.single.code, 'ABCD2345');
    expect(find.byType(TodayScreen), findsOneWidget);
    expect(app.ui.snackbar.current?.text, 'You joined the household.');
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

  // @lat: [[mobile-tests#Household sharing#Used, expired and unknown codes say so]]
  testWidgets('expired, used and unknown codes show their errors', (
    tester,
  ) async {
    for (final (answer, message) in [
      (const ApiError(410, 'invite expired'), 'This invite has expired.'),
      (const ApiError(410, 'invite used'), 'This invite has been used.'),
      (const ApiError(404, 'not found'), 'No invite has that code.'),
    ]) {
      final app = await pump(tester, location: '/invite/ABCD2345');
      app.api.acceptAnswer = answer;
      await tapKey(tester, 'join');
      expect(find.byType(JoinScreen), findsOneWidget);
      expect(find.textContaining(message), findsOneWidget);
    }
  });

  // @lat: [[mobile-tests#Household sharing#Leaving cards behind asks first]]
  testWidgets('joining from a household with cards asks first', (tester) async {
    final app = await pump(tester, location: '/invite/ABCD2345');
    app.api.acceptAnswer = const ApiError(409, 'household holds cards');
    await tapKey(tester, 'join');
    expect(find.text('Leave your cards behind?'), findsOneWidget);
    await tester.tap(find.text('Leave and join'));
    await tester.pumpAndSettle();
    expect(app.api.accepted.last.confirmLeave, isTrue);
    expect(find.byType(TodayScreen), findsOneWidget);
  });
}
