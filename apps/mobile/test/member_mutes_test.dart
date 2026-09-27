import 'dart:async';

import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:reward/data/household_api.dart';
import 'package:reward/data/household_cache.dart';
import 'package:reward/data/snapshot_store.dart';
import 'package:reward/logic/app_store.dart';
import 'package:reward/logic/ui_state.dart';
import 'package:reward/main.dart';
import 'package:reward/shell/router.dart';
import 'package:reward/widgets/credit_row.dart';
import 'package:reward/widgets/switch_row.dart';

import 'support/fake_api.dart';

/// Member mutes in the service-tier mode: the switch shows the server's
/// resting state, and sits at the requested state, disabled, while the
/// request is in flight.

final now = DateTime(2026, 9, 16, 10);

AppStore remoteStore(FakeApi api) => AppStore(
  store: MemorySnapshotStore(),
  api: api,
  cache: MemoryHouseholdCache(),
  clock: () => now,
);

Future<AppStore> loaded(FakeApi api) async {
  final store = remoteStore(api);
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

SwitchRow switchRow(WidgetTester tester, String title) =>
    tester.widget<SwitchRow>(find.widgetWithText(SwitchRow, title));

Finder get bell => find.descendant(
  of: find.byType(CreditRow).first,
  matching: find.byType(IconButton),
);

void main() {
  group('store', () {
    // @lat: [[mobile-tests#Member mutes#Toggling twice mutes then unmutes]]
    test(
      'a benefit and a card mute toggle on and off against the server',
      () async {
        final api = FakeApi();
        final store = await loaded(api);

        await store.toggleBenefitMute('benefit-1');
        expect(store.isBenefitMuted('benefit-1'), isTrue);
        expect(api.mutedBenefitIds, {'benefit-1'});
        await store.toggleBenefitMute('benefit-1');
        expect(store.isBenefitMuted('benefit-1'), isFalse);
        expect(api.mutedBenefitIds, isEmpty);

        await store.toggleCardMute('card-1');
        expect(store.isCardMuted('card-1'), isTrue);
        await store.toggleCardMute('card-1');
        expect(store.isCardMuted('card-1'), isFalse);
        expect(api.mutedCardIds, isEmpty);
      },
    );

    // @lat: [[mobile-tests#Member mutes#In flight shows the requested state]]
    test(
      'while setMute is held the requested state shows as pending',
      () async {
        final api = FakeApi();
        final store = await loaded(api);
        final hold = api.holdMute = Completer<void>();

        final done = store.toggleBenefitMute('benefit-1');
        await Future<void>.delayed(Duration.zero);
        expect(store.isBenefitMuted('benefit-1'), isTrue);
        expect(store.isMutePending('benefit-1'), isTrue);
        expect(store.instanceFor('benefit-1')!.muted, isTrue);

        hold.complete();
        await done;
        expect(store.isMutePending('benefit-1'), isFalse);
        expect(store.isBenefitMuted('benefit-1'), isTrue);

        final cardHold = api.holdMute = Completer<void>();
        final cardDone = store.toggleCardMute('card-1');
        await Future<void>.delayed(Duration.zero);
        expect(store.isCardMuted('card-1'), isTrue);
        expect(store.isMutePending('card-1'), isTrue);
        cardHold.complete();
        await cardDone;
        expect(store.isMutePending('card-1'), isFalse);
      },
    );

    // @lat: [[mobile-tests#Member mutes#A refused or offline mute keeps the old state]]
    test('a refused or offline setMute leaves the old state', () async {
      final api = FakeApi()..muteAnswer = const ApiError(500, 'boom');
      final store = await loaded(api);

      await store.toggleBenefitMute('benefit-1');
      expect(store.isBenefitMuted('benefit-1'), isFalse);
      expect(store.isMutePending('benefit-1'), isFalse);
      expect(store.problem, isNotNull);

      store.clearProblem();
      api
        ..muteAnswer = null
        ..online = false;
      await store.toggleCardMute('card-1');
      expect(store.isCardMuted('card-1'), isFalse);
      expect(store.isMutePending('card-1'), isFalse);
      expect(store.problem, offlineMessage);
    });

    // @lat: [[mobile-tests#Member mutes#An accepted mute survives a failed refresh]]
    test('an accepted mute whose refresh fails still shows muted', () async {
      final api = FakeApi();
      final store = await loaded(api);
      final hold = api.holdMute = Completer<void>();

      final done = store.toggleBenefitMute('benefit-1');
      await Future<void>.delayed(Duration.zero);
      // The mute lands, then the api drops before the refresh.
      hold.complete();
      await Future<void>.delayed(Duration.zero);
      api.online = false;
      await done;
      expect(store.isBenefitMuted('benefit-1'), isTrue);
      expect(store.isMutePending('benefit-1'), isFalse);
    });

    // @lat: [[mobile-tests#Member mutes#Local mode flips at once]]
    test('local mode flips at once and is never pending', () async {
      final store = AppStore(
        store: MemorySnapshotStore(serverHousehold()),
        clock: () => now,
      );
      await store.load();
      final done = store.toggleBenefitMute('benefit-1');
      expect(store.isBenefitMuted('benefit-1'), isTrue);
      expect(store.isMutePending('benefit-1'), isFalse);
      await done;
      await store.toggleCardMute('card-1');
      expect(store.isCardMuted('card-1'), isTrue);
    });
  });

  group('controls', () {
    // @lat: [[mobile-tests#Member mutes#The sheet's switch is disabled in flight]]
    testWidgets(
      'the sheet switch sits on, disabled, until the server answers',
      (tester) async {
        final api = FakeApi();
        final store = await loaded(api);
        final ui = await pumpAt(tester, store);
        ui.openCredit('benefit-1');
        await tester.pumpAndSettle();

        final hold = api.holdMute = Completer<void>();
        final silence = find.widgetWithText(SwitchRow, 'Silence this credit');
        await tester.ensureVisible(silence);
        await tester.tap(silence);
        await tester.pump();
        expect(switchRow(tester, 'Silence this credit').value, isTrue);
        expect(switchRow(tester, 'Silence this credit').onChanged, isNull);

        hold.complete();
        await tester.pumpAndSettle();
        expect(switchRow(tester, 'Silence this credit').value, isTrue);
        expect(switchRow(tester, 'Silence this credit').onChanged, isNotNull);

        // The snackbar's Undo goes back through the same path.
        ui.snackbar.current!.action!.onAct();
        await tester.pumpAndSettle();
        expect(switchRow(tester, 'Silence this credit').value, isFalse);
        expect(api.mutedBenefitIds, isEmpty);
      },
    );

    // @lat: [[mobile-tests#Member mutes#A refused switch returns to off]]
    testWidgets('a refused mute puts the switch back off and enabled', (
      tester,
    ) async {
      final api = FakeApi()..muteAnswer = const ApiError(500, 'boom');
      final store = await loaded(api);
      final ui = await pumpAt(tester, store);
      ui.openCredit('benefit-1');
      await tester.pumpAndSettle();

      final silence = find.widgetWithText(SwitchRow, 'Silence this credit');
      await tester.ensureVisible(silence);
      await tester.tap(silence);
      await tester.pumpAndSettle();
      expect(switchRow(tester, 'Silence this credit').value, isFalse);
      expect(switchRow(tester, 'Silence this credit').onChanged, isNotNull);
    });

    // @lat: [[mobile-tests#Member mutes#Card editor and row bell are disabled in flight]]
    testWidgets('the card editor switch and the row bell wait in flight', (
      tester,
    ) async {
      final api = FakeApi();
      final store = await loaded(api);
      await pumpAt(tester, store, cardPath('card-1'));

      var hold = api.holdMute = Completer<void>();
      await tester.tap(find.widgetWithText(SwitchRow, 'Silence every credit'));
      await tester.pump();
      expect(switchRow(tester, 'Silence every credit').value, isTrue);
      expect(switchRow(tester, 'Silence every credit').onChanged, isNull);
      hold.complete();
      await tester.pumpAndSettle();
      expect(switchRow(tester, 'Silence every credit').onChanged, isNotNull);
      await store.toggleCardMute('card-1');

      // A fresh app, since the router keeps its first location.
      await tester.pumpWidget(const SizedBox());
      await pumpAt(tester, store);
      hold = api.holdMute = Completer<void>();
      await tester.tap(bell);
      await tester.pump();
      expect(tester.widget<IconButton>(bell).onPressed, isNull);
      expect(
        tester.widget<CreditRow>(find.byType(CreditRow).first).instance.muted,
        isTrue,
      );
      hold.complete();
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(bell).onPressed, isNotNull);
      expect(api.mutedBenefitIds, {'benefit-1'});
    });
  });
}
