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

/// Sharing the household: the Household section of Settings, invites
/// through the share sheet, joining by code or by link, and the errors.

Future<({AppStore store, FakeApi api, UiState ui})> pump(
  WidgetTester tester, {
  MemberRole role = MemberRole.owner,
  String location = Paths.settings,
  Session? session,
}) async {
  final api = FakeApi(role: role);
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
  final shared = <ShareParams>[];
  setUp(() {
    shared.clear();
    share = (params) async => shared.add(params);
  });
  tearDown(() => share = shareWithSheet);

  Future<void> createEditInvite(WidgetTester tester) async {
    final app = await pump(tester);
    expect(find.text('ann@example.com'), findsOneWidget);
    expect(find.text('Owner'), findsWidgets);

    await tapKey(tester, 'invite');
    await tester.tap(find.text('Can edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create and share'));
    await tester.pumpAndSettle();

    expect(app.api.invites, ['edit']);
    expect(find.text('ABCD2345'), findsOneWidget);
  }

  // @lat: [[mobile-tests#Household sharing#An owner shares an invite on iOS]]
  testWidgets('on iOS an owner shares the invite link alone', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await createEditInvite(tester);

    final params = shared.single;
    expect(params.uri, Uri.parse('https://api.test/invite/ABCD2345'));
    expect(params.text, isNull);
    expect(params.previewThumbnail, isNull);
    expect(params.sharePositionOrigin, isNotNull);
    debugDefaultTargetPlatformOverride = null;
  });

  // @lat: [[mobile-tests#Household sharing#An owner shares an invite on Android]]
  testWidgets('on Android an owner shares the reward message with the icon', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await createEditInvite(tester);

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

  // @lat: [[mobile-tests#Household sharing#Only an owner invites and removes]]
  testWidgets('an editor sees members but no invite or remove', (tester) async {
    await pump(tester, role: MemberRole.editor);
    expect(find.text('ann@example.com'), findsOneWidget);
    expect(key('invite'), findsNothing);
    expect(find.byTooltip('Remove ann@example.com'), findsNothing);
  });

  // @lat: [[mobile-tests#Household sharing#A code joins the household]]
  testWidgets('entering a valid code joins with the invite’s role', (
    tester,
  ) async {
    final app = await pump(tester, role: MemberRole.owner);
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
    expect(app.store.canWrite, isTrue);
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

  // @lat: [[mobile-tests#Household sharing#An owner removes a member]]
  testWidgets('an owner removes a member after confirming', (tester) async {
    final api = FakeApi(role: MemberRole.owner)
      ..members.add(
        const HouseholdMember(
          userId: 'user-bob',
          email: 'bob@example.com',
          role: MemberRole.editor,
        ),
      );
    final store = AppStore(store: MemorySnapshotStore(), api: api);
    await store.load();
    tester.view.physicalSize = const Size(402, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RewardApp(store: store, ui: UiState(), initialLocation: Paths.settings),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Remove bob@example.com'));
    await tester.tap(find.byTooltip('Remove bob@example.com'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(api.removed, ['user-bob']);
    expect(find.text('bob@example.com'), findsNothing);
  });
}
