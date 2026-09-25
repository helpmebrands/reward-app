import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reward/data/household_api.dart';
import 'package:reward/data/push_messaging.dart';
import 'package:reward/data/snapshot_store.dart';
import 'package:reward/logic/app_store.dart';
import 'package:reward/logic/push.dart';
import 'package:reward/logic/session.dart';
import 'package:reward/logic/ui_state.dart';
import 'package:reward/main.dart';
import 'package:reward/screens/card_editor_screen.dart';
import 'package:reward/shell/router.dart';

import 'sign_in_test.dart' show FakeAuth;
import 'support/fake_api.dart';
import 'support/fake_push.dart';

/// Push on the device: permission, registration with the api, refreshes,
/// sign-out, taps and the Settings summary, over fakes of FCM and the api.

PushController controller(FakeMessaging messaging, FakeApi api) =>
    PushController(
      messaging: messaging,
      api: api,
      installationId: () async => 'inst-1',
    );

typedef App = ({
  AppStore store,
  FakeApi api,
  FakeMessaging messaging,
  PushController push,
  UiState ui,
  FakeAuth auth,
});

Future<App> pump(
  WidgetTester tester, {
  PushPermission answer = PushPermission.granted,
  String location = Paths.settings,
  bool enabled = false,
  Map<String, Object?>? launchTap,
}) async {
  final api = FakeApi();
  final messaging = FakeMessaging(answer: answer)..launchTap = launchTap;
  final push = controller(messaging, api);
  final store = AppStore(
    store: MemorySnapshotStore(),
    api: api,
    clock: () => DateTime(2026, 9, 16, 10),
  );
  await store.load();
  if (enabled) {
    await store.updatePreferences((p) => p.copyWith(enabled: true));
  }
  final auth = FakeAuth(signedIn: const SignedInUser(uid: 'u-1'));
  final session = Session(auth: auth, intro: MemoryIntroStore(seen: true));
  await session.load();
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
      push: push,
      initialLocation: location,
    ),
  );
  await tester.pumpAndSettle();
  return (
    store: store,
    api: api,
    messaging: messaging,
    push: push,
    ui: ui,
    auth: auth,
  );
}

Finder key(String k) => find.byKey(Key(k));

Future<void> tapFinder(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('PushController', () {
    // @lat: [[mobile-tests#Push#A granted permission registers the device]]
    test(
      'a grant registers the token, installation, platform and zone',
      () async {
        final messaging = FakeMessaging();
        final api = FakeApi();
        final push = controller(messaging, api);

        expect(await push.enable(), isNull);
        expect(messaging.prompts, 1);
        expect(api.devices.keys, ['fcm-1']);
        final device = api.devices['fcm-1']!;
        expect(device.installationId, 'inst-1');
        expect(device.platform, 'ios');
        expect(device.timezone, 'Europe/London');
      },
    );

    // @lat: [[mobile-tests#Push#A refused permission registers nothing]]
    test('a refusal registers nothing and says why', () async {
      final messaging = FakeMessaging(answer: PushPermission.denied);
      final api = FakeApi();
      final push = controller(messaging, api);

      expect(await push.enable(), PushController.refused);
      expect(api.devices, isEmpty);
    });

    // @lat: [[mobile-tests#Push#A refreshed token registers again]]
    test('a refreshed token replaces the registration', () async {
      final messaging = FakeMessaging();
      final api = FakeApi();
      final push = controller(messaging, api);
      await push.enable();
      push.start();

      messaging.currentToken = 'fcm-2';
      messaging.refreshes.add('fcm-2');
      await pumpEventQueue();
      expect(api.devices.keys, ['fcm-2']);

      await push.unregister();
      expect(api.devices, isEmpty);
      push.dispose();
    });
  });

  // @lat: [[mobile-tests#Push#Turning reminders on asks once]]
  testWidgets('turning reminders on asks once, then registers', (tester) async {
    final app = await pump(tester);
    await tapFinder(tester, find.bySemanticsLabel('Send me reminders'));
    expect(app.messaging.prompts, 1);
    expect(app.store.preferences.enabled, isTrue);
    expect(app.api.devices.keys, ['fcm-1']);

    await tapFinder(tester, find.bySemanticsLabel('Send me reminders'));
    expect(app.store.preferences.enabled, isFalse);
    expect(app.api.devices, isEmpty);
  });

  // @lat: [[mobile-tests#Push#A refusal is reported in the snackbar]]
  testWidgets('a refusal keeps reminders off and says so', (tester) async {
    final app = await pump(tester, answer: PushPermission.denied);
    await tapFinder(tester, find.bySemanticsLabel('Send me reminders'));
    expect(app.messaging.prompts, 1);
    expect(app.store.preferences.enabled, isFalse);
    expect(
      app.ui.snackbar.current?.text,
      'Reminders stay off until notifications are allowed.',
    );
  });

  // @lat: [[mobile-tests#Push#Signing out deletes the registration]]
  testWidgets('signing out unregisters the device first', (tester) async {
    final app = await pump(tester);
    await tapFinder(tester, find.bySemanticsLabel('Send me reminders'));
    expect(app.api.devices, isNotEmpty);

    await tapFinder(tester, key('sign-out'));
    expect(app.api.devices, isEmpty);
    expect(app.auth.calls, contains('sign out'));
  });

  // @lat: [[mobile-tests#Push#Settings shows the summary and sends a delayed test]]
  testWidgets('Settings reads the summary and the test button sends', (
    tester,
  ) async {
    final app = await pump(tester);
    app.api.summary = ReminderSummary(
      count: 3,
      next: (
        fireAt: DateTime.utc(2026, 10, 31, 9),
        title: r'$10 expires tonight',
        body: 'Dining on Gold.',
      ),
    );
    await tapFinder(tester, find.bySemanticsLabel('Send me reminders'));
    expect(
      find.text(r'3 reminders scheduled. Next on Oct 31: $10 expires tonight.'),
      findsOneWidget,
    );

    app.api.testGate = Completer<void>();
    await tapFinder(tester, key('send-test'));
    expect(app.api.testDelays, [5]);
    expect(
      app.ui.snackbar.current?.text,
      'Sending in 5 seconds. Put the app in the background to see it.',
    );
    app.api.testGate!.complete();
    await tester.pumpAndSettle();
    expect(app.api.testSends, 1);
    expect(app.ui.snackbar.current?.text, 'Test notification sent.');
  });

  // @lat: [[mobile-tests#Push#A tapped notification opens its screen]]
  testWidgets('a tap opens the path its payload names', (tester) async {
    final app = await pump(tester, location: Paths.today);
    app.messaging.tapped.add({'url': '/cards/card-1'});
    await tester.pumpAndSettle();
    expect(find.byType(CardEditorScreen), findsOneWidget);
  });

  testWidgets('the tap that launched the app opens its screen', (tester) async {
    await pump(
      tester,
      location: Paths.today,
      launchTap: {'url': '/cards/card-1'},
    );
    expect(find.byType(CardEditorScreen), findsOneWidget);
  });

  // @lat: [[mobile-tests#Push#A notice in the foreground shows in the snackbar]]
  testWidgets('a push while the app is open shows in the snackbar', (
    tester,
  ) async {
    final app = await pump(tester, location: Paths.today);
    app.messaging.shown.add(
      const PushNotice(title: r'$10 expires tonight', body: 'Dining on Gold.'),
    );
    await tester.pumpAndSettle();
    expect(app.ui.snackbar.current?.text, r'$10 expires tonight');
  });
}
