import 'dart:async';

import 'package:domain/domain.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:reward/data/household_api.dart';
import 'package:reward/data/household_cache.dart';
import 'package:reward/data/snapshot_store.dart';
import 'package:reward/logic/app_store.dart';
import 'package:reward/logic/ui_state.dart';
import 'package:reward/main.dart';
import 'package:reward/shell/router.dart';
import 'package:reward/widgets/switch_row.dart';

import 'support/fake_api.dart';

/// Notification levels: one per-member control, Periodically, Last chance
/// or Silence, on the credit sheet and the credit editor, over the api's
/// level route with the in-flight rule from #352.

final now = DateTime(2026, 9, 16, 10);
const id = 'benefit-1';

Future<AppStore> loaded(FakeApi api) async {
  final store = AppStore(
    store: MemorySnapshotStore(),
    api: api,
    cache: MemoryHouseholdCache(),
    clock: () => now,
  );
  await store.load();
  return store;
}

Future<UiState> pumpAt(
  WidgetTester tester,
  AppStore store, [
  String location = Paths.today,
]) async {
  final ui = UiState();
  tester.view.physicalSize = const Size(402, 874);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RewardApp(store: store, ui: ui, initialLocation: location),
  );
  await tester.pumpAndSettle();
  return ui;
}

Future<UiState> openSheet(WidgetTester tester, AppStore store) async {
  final ui = await pumpAt(tester, store);
  ui.openCredit(id);
  await tester.pumpAndSettle();
  return ui;
}

final control = find.byType(SegmentedButton<NotificationLevel>);

SegmentedButton<NotificationLevel> levels(WidgetTester tester) =>
    tester.widget<SegmentedButton<NotificationLevel>>(control);

Future<void> choose(WidgetTester tester, String label) async {
  await tester.ensureVisible(control);
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(of: control, matching: find.text(label)));
}

void main() {
  group('store', () {
    // @lat: [[mobile-tests#Notification levels#Each level goes to the api]]
    test('each level is sent to the api and read back from it', () async {
      final api = FakeApi();
      final store = await loaded(api);
      expect(store.notificationLevel(id), NotificationLevel.periodically);

      await store.setNotificationLevel(id, NotificationLevel.lastChance);
      expect(store.notificationLevel(id), NotificationLevel.lastChance);
      expect(api.lastCallBenefitIds, {id});
      expect(api.mutedBenefitIds, isEmpty);

      await store.setNotificationLevel(id, NotificationLevel.silenced);
      expect(store.notificationLevel(id), NotificationLevel.silenced);
      expect(api.mutedBenefitIds, {id});
      expect(api.lastCallBenefitIds, {id});

      await store.setNotificationLevel(id, NotificationLevel.periodically);
      expect(store.notificationLevel(id), NotificationLevel.periodically);
      expect(api.mutedBenefitIds, isEmpty);
      expect(api.lastCallBenefitIds, isEmpty);
    });

    // @lat: [[mobile-tests#Notification levels#A level in flight shows the request]]
    test('while held the requested level shows and is pending', () async {
      final api = FakeApi();
      final store = await loaded(api);
      final hold = api.holdMute = Completer<void>();

      final done = store.setNotificationLevel(id, NotificationLevel.lastChance);
      await Future<void>.delayed(Duration.zero);
      expect(store.notificationLevel(id), NotificationLevel.lastChance);
      expect(store.isMutePending(id), isTrue);

      hold.complete();
      await done;
      expect(store.isMutePending(id), isFalse);
      expect(store.notificationLevel(id), NotificationLevel.lastChance);
    });

    // @lat: [[mobile-tests#Notification levels#A refused level returns to the old one]]
    test('a refused or offline level keeps the old one', () async {
      final api = FakeApi()..muteAnswer = const ApiError(500, 'boom');
      final store = await loaded(api);
      await store.setNotificationLevel(id, NotificationLevel.silenced);
      expect(store.notificationLevel(id), NotificationLevel.periodically);
      expect(store.isMutePending(id), isFalse);
      expect(store.problem, isNotNull);

      store.clearProblem();
      api
        ..muteAnswer = null
        ..online = false;
      await store.setNotificationLevel(id, NotificationLevel.lastChance);
      expect(store.notificationLevel(id), NotificationLevel.periodically);
      expect(store.problem, offlineMessage);
    });

    // @lat: [[mobile-tests#Notification levels#Unsilencing returns to Last chance]]
    test('the row bell silences and unsilences back to Last chance', () async {
      final api = FakeApi();
      final store = await loaded(api);
      await store.setNotificationLevel(id, NotificationLevel.lastChance);
      await store.toggleBenefitMute(id);
      expect(store.notificationLevel(id), NotificationLevel.silenced);
      await store.toggleBenefitMute(id);
      expect(store.notificationLevel(id), NotificationLevel.lastChance);
    });

    // @lat: [[mobile-tests#Notification levels#A local level is written at once]]
    test('without an api the level is written at once', () async {
      final store = AppStore(
        store: MemorySnapshotStore(serverHousehold()),
        clock: () => now,
      );
      await store.load();
      final done = store.setNotificationLevel(id, NotificationLevel.lastChance);
      expect(store.notificationLevel(id), NotificationLevel.lastChance);
      expect(store.isMutePending(id), isFalse);
      await done;
      expect(store.preferences.lastCallBenefitIds, {id});
    });
  });

  group('credit sheet', () {
    // @lat: [[mobile-tests#Notification levels#The sheet has the control and no ladder]]
    testWidgets('shows Notification levels, no ladder and no switches', (
      tester,
    ) async {
      await openSheet(tester, await loaded(FakeApi()));
      expect(find.text('Notification levels'), findsOneWidget);
      expect(levels(tester).selected, {NotificationLevel.periodically});
      for (final label in ['Periodically', 'Last chance', 'Silence']) {
        expect(
          find.descendant(of: control, matching: find.text(label)),
          findsOneWidget,
        );
      }
      expect(
        find.text('23 days, 7 days and the last day before it shuts'),
        findsOneWidget,
      );
      expect(find.text('Reminder ladder'), findsNothing);
      expect(find.widgetWithText(SwitchRow, 'Last call only'), findsNothing);
      expect(
        find.widgetWithText(SwitchRow, 'Silence this credit'),
        findsNothing,
      );
    });

    // @lat: [[mobile-tests#Notification levels#The sheet's control waits for the server]]
    testWidgets('the requested level sits disabled until the server answers', (
      tester,
    ) async {
      final api = FakeApi();
      final store = await loaded(api);
      final ui = await openSheet(tester, store);

      final hold = api.holdMute = Completer<void>();
      await choose(tester, 'Last chance');
      await tester.pump();
      expect(levels(tester).selected, {NotificationLevel.lastChance});
      expect(levels(tester).onSelectionChanged, isNull);

      hold.complete();
      await tester.pumpAndSettle();
      expect(levels(tester).selected, {NotificationLevel.lastChance});
      expect(levels(tester).onSelectionChanged, isNotNull);
      expect(find.text('Only on the last day'), findsOneWidget);
      expect(api.lastCallBenefitIds, {id});

      // The snackbar's Undo restores the level before.
      ui.snackbar.current!.action!.onAct();
      await tester.pumpAndSettle();
      expect(levels(tester).selected, {NotificationLevel.periodically});
      expect(api.lastCallBenefitIds, isEmpty);
    });

    // @lat: [[mobile-tests#Notification levels#A refused level on the sheet is enabled again]]
    testWidgets('a refusal puts the old level back, enabled', (tester) async {
      final api = FakeApi()..muteAnswer = const ApiError(500, 'boom');
      await openSheet(tester, await loaded(api));
      await choose(tester, 'Silence');
      await tester.pumpAndSettle();
      expect(levels(tester).selected, {NotificationLevel.periodically});
      expect(levels(tester).onSelectionChanged, isNotNull);
    });

    // @lat: [[mobile-tests#Notification levels#A silenced card shows Silence, disabled]]
    testWidgets('with the card muted the control shows Silence, disabled', (
      tester,
    ) async {
      final api = FakeApi()..mutedCardIds.add('card-1');
      await openSheet(tester, await loaded(api));
      expect(levels(tester).selected, {NotificationLevel.silenced});
      expect(levels(tester).onSelectionChanged, isNull);
      expect(
        find.text(
          'The whole card is silenced. Unsilence it on the card to choose.',
        ),
        findsOneWidget,
      );
    });

    // @lat: [[mobile-tests#Notification levels#A reader sets their own level]]
    testWidgets('a reader can change the level', (tester) async {
      final api = FakeApi(role: MemberRole.reader);
      await openSheet(tester, await loaded(api));
      await choose(tester, 'Last chance');
      await tester.pumpAndSettle();
      expect(levels(tester).selected, {NotificationLevel.lastChance});
      expect(api.lastCallBenefitIds, {id});
    });
  });

  // @lat: [[mobile-tests#Notification levels#The credit editor offers the same levels]]
  testWidgets('the credit editor offers the three levels', (tester) async {
    final api = FakeApi();
    await pumpAt(tester, await loaded(api), benefitPath(id));
    expect(find.text('Notification levels'), findsOneWidget);
    expect(find.widgetWithText(SwitchRow, 'Last call only'), findsNothing);
    expect(find.widgetWithText(SwitchRow, 'Silence this credit'), findsNothing);
    await choose(tester, 'Silence');
    await tester.pumpAndSettle();
    expect(levels(tester).selected, {NotificationLevel.silenced});
    expect(api.mutedBenefitIds, {id});
    await choose(tester, 'Periodically');
    await tester.pumpAndSettle();
    expect(api.mutedBenefitIds, isEmpty);
  });
}
