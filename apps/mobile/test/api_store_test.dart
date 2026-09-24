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

import 'support/fake_api.dart';

/// The api-backed store: the household from the service tier, a versioned
/// cache for offline viewing, claims through a persisted outbox, and no
/// edits for a reader or while offline.

final now = DateTime(2026, 9, 16, 10);

AppStore remoteStore(
  FakeApi api, {
  HouseholdCache? cache,
  ClaimOutbox? outbox,
}) => AppStore(
  store: MemorySnapshotStore(),
  api: api,
  cache: cache ?? MemoryHouseholdCache(),
  outbox: outbox ?? MemoryClaimOutbox(),
  clock: () => now,
);

void main() {
  // @lat: [[mobile-tests#Api store#Offline, the app starts from the cache]]
  test('with the api unreachable the store starts from the cache', () async {
    final cache = MemoryHouseholdCache()
      ..saved = CachedHousehold(
        version: householdCacheVersion,
        data: household(label: 'Cached'),
        role: MemberRole.editor,
      );
    final api = FakeApi()..online = false;
    final store = remoteStore(api, cache: cache);
    await store.load();
    expect(store.data!.cards.single.label, 'Cached');
    expect(store.offline, isTrue);

    api.online = true;
    await store.refresh();
    expect(store.data!.cards.single.label, 'Server');
    expect(cache.saved!.data.cards.single.label, 'Server');
    expect(store.offline, isFalse);
  });

  // @lat: [[mobile-tests#Api store#An offline claim is pending, kept and sent once]]
  test(
    'an offline claim is pending, survives a restart, is sent once',
    () async {
      final cache = MemoryHouseholdCache();
      final outbox = MemoryClaimOutbox();
      final api = FakeApi();
      final first = remoteStore(api, cache: cache, outbox: outbox);
      await first.load();
      api.online = false;

      final instance = first.instanceFor('benefit-1')!;
      final claim = await first.claim(instance, amountCents: 400);
      expect(first.data!.claims.map((c) => c.id), [claim.id]);
      expect(first.isPending(claim.id), isTrue);
      expect(api.claimPosts, 0);

      // A restart: a new store over the same cache and outbox.
      final second = remoteStore(api, cache: cache, outbox: outbox);
      await second.load();
      expect(second.isPending(claim.id), isTrue);
      expect(second.data!.claims.single.amountCents, 400);

      api.online = true;
      await Future.wait([second.flush(), second.flush(), second.flush()]);
      expect(api.claimPosts, 1);
      expect(api.data.claims, hasLength(1));
      expect(await outbox.load(), isEmpty);
      expect(second.data!.claims.single.id, 'server-1');
      expect(second.isPending('server-1'), isFalse);

      // A retry after a post whose answer was lost sends the same key again,
      // and the server keeps one claim.
      await outbox.save([
        PendingClaim(
          key: 'lost-answer',
          claim: const Claim(
            id: 'local',
            benefitId: 'benefit-1',
            cycleKey: '2026-09-01',
            amountCents: 100,
            claimedAt: '2026-09-16T10:00:00.000Z',
          ),
        ),
      ]);
      await second.load();
      await second.flush();
      await outbox.save([
        PendingClaim(
          key: 'lost-answer',
          claim: const Claim(
            id: 'local',
            benefitId: 'benefit-1',
            cycleKey: '2026-09-01',
            amountCents: 100,
            claimedAt: '2026-09-16T10:00:00.000Z',
          ),
        ),
      ]);
      await second.load();
      await second.flush();
      expect(api.data.claims, hasLength(2));
    },
  );

  // @lat: [[mobile-tests#Api store#Offline edits are refused with a message]]
  test('editing a card offline is refused with the offline message', () async {
    final api = FakeApi();
    final store = remoteStore(api);
    await store.load();
    api.online = false;
    final done = await store.updateCard(
      'card-1',
      (c) => c.copyWith(label: 'Renamed'),
    );
    expect(done, isFalse);
    expect(store.problem, offlineMessage);
    expect(store.data!.cards.single.label, 'Server');
    expect(api.data.cards.single.label, 'Server');
    expect(store.canEdit, isFalse);

    api.online = true;
    expect(
      await store.updateCard('card-1', (c) => c.copyWith(label: 'Renamed')),
      isTrue,
    );
    expect(store.data!.cards.single.label, 'Renamed');
  });

  testWidgets('the card editor shows the offline message', (tester) async {
    final api = FakeApi();
    final store = remoteStore(api);
    await store.load();
    api.online = false;
    final ui = UiState();
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RewardApp(store: store, ui: ui, initialLocation: cardPath('card-1')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('field-label')), 'Renamed');
    await tester.pumpAndSettle();
    expect(ui.snackbar.current?.text, offlineMessage);
    expect(api.data.cards.single.label, 'Server');
  });

  // @lat: [[mobile-tests#Api store#A cache of another version is discarded]]
  test('a cache of another version is discarded, queued claims kept', () async {
    final cache = MemoryHouseholdCache()
      ..saved = CachedHousehold(
        version: householdCacheVersion - 1,
        data: household(label: 'Old shape'),
        role: MemberRole.editor,
      );
    final outbox = MemoryClaimOutbox();
    await outbox.save([
      PendingClaim(
        key: 'queued',
        claim: const Claim(
          id: 'local-1',
          benefitId: 'benefit-1',
          cycleKey: '2026-09-01',
          amountCents: 300,
          claimedAt: '2026-09-15T10:00:00.000Z',
        ),
      ),
    ]);
    final api = FakeApi()..online = false;
    final store = remoteStore(api, cache: cache, outbox: outbox);
    await store.load();
    expect(store.data, isNull);
    expect(await outbox.load(), hasLength(1));
    expect(cache.saved, isNull);

    api.online = true;
    await store.refresh();
    expect(store.data!.cards.single.label, 'Server');
    expect(api.data.claims.single.amountCents, 300);
  });

  // @lat: [[mobile-tests#Api store#A reader sees no claim or edit controls]]
  testWidgets('a reader sees no log or edit controls', (tester) async {
    final api = FakeApi(role: MemberRole.reader);
    final store = remoteStore(api);
    await store.load();
    expect(store.canWrite, isFalse);
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(RewardApp(store: store, ui: UiState()));
    await tester.pumpAndSettle();

    final row = tester.widget<CreditRow>(find.byType(CreditRow).first);
    expect(row.onLogAll, isNull);
    await tester.tap(find.byType(CreditRow).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Mark the full'), findsNothing);
    expect(find.text('Log what you spent'), findsNothing);

    await tester.pumpWidget(
      RewardApp(store: store, ui: UiState(), initialLocation: Paths.cards),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('add-card')), findsNothing);
    expect(find.text('Edit card and credits'), findsNothing);
  });
}
