import 'dart:async';

import 'package:domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reward/data/snapshot_store.dart';
import 'package:reward/logic/app_store.dart';

// The mutation suite: every store write yields the expected snapshot, exactly
// one notification, and a save through the SnapshotStore. Fixtures mirror the
// domain's factories.dart: an Amex Platinum held by Jim, dated 16 Sep 2026.

final DateTime _now = DateTime(2026, 9, 16, 10, 30);
const IsoInstant _stamp = '2020-03-14T00:00:00.000Z';

Card _card({String id = 'card-1'}) => Card(
  id: id,
  issuer: 'American Express',
  product: 'Platinum',
  network: CardNetwork.amex,
  kind: CardKind.personal,
  annualFeeCents: 89500,
  anniversaryOn: '2020-03-14',
  archived: false,
  createdAt: _stamp,
  updatedAt: _stamp,
);

Benefit _benefit({
  String id = 'benefit-1',
  String cardId = 'card-1',
  int valueCents = 2500,
  bool enrollmentRequired = false,
  IsoInstant? enrolledAt,
  int? spendThresholdCents,
  IsoInstant? optedOutAt,
}) => Benefit(
  id: id,
  cardId: cardId,
  name: 'Test credit',
  category: BenefitCategory.other,
  valueCents: valueCents,
  cadence: Cadence.monthly,
  anchor: CycleAnchor.calendar,
  enrollmentRequired: enrollmentRequired,
  enrolledAt: enrolledAt,
  spendThresholdCents: spendThresholdCents,
  redemptionSteps: const [],
  lastCallOnly: false,
  active: true,
  optedOutAt: optedOutAt,
  createdAt: _stamp,
  updatedAt: _stamp,
);

Claim _claim({
  String id = 'claim-1',
  String benefitId = 'benefit-1',
  IsoDate cycleKey = '2026-09-01',
  int amountCents = 1000,
}) => Claim(
  id: id,
  benefitId: benefitId,
  cycleKey: cycleKey,
  amountCents: amountCents,
  claimedAt: '2026-09-10T12:00:00.000Z',
);

AppData _data({
  List<Card>? cards,
  List<Benefit>? benefits,
  List<Claim> claims = const [],
}) => AppData(
  version: 1,
  cards: cards ?? [_card()],
  benefits: benefits ?? [_benefit()],
  claims: claims,
  settings: defaultSettings,
);

class _Harness {
  _Harness(AppData? data) : memory = MemorySnapshotStore(data) {
    store = AppStore(store: memory, clock: () => _now);
    store.addListener(() => notifications++);
  }

  final MemorySnapshotStore memory;
  late AppStore store;
  int notifications = 0;

  Future<_Harness> loaded() async {
    await store.load();
    notifications = 0;
    return this;
  }

  /// The snapshot as the store exposes it, and as it was saved: both must
  /// agree after every mutation.
  AppData get saved {
    expect(memory.data, isNotNull, reason: 'the mutation was not saved');
    expect(appDataToJson(memory.data!), appDataToJson(store.data!));
    return memory.data!;
  }

  /// The member's preferences as the store exposes them, and as they were
  /// saved.
  MemberPreferences get savedPreferences {
    expect(memory.preferences, isNotNull, reason: 'preferences not saved');
    expect(
      memberPreferencesToJson(memory.preferences!),
      memberPreferencesToJson(store.preferences),
    );
    return memory.preferences!;
  }
}

Future<_Harness> _load([AppData? data]) => _Harness(data ?? _data()).loaded();

void main() {
  group('cards', () {
    // @lat: [[mobile-tests#Store#A template becomes a card with its credits]]
    test(
      'addCardFromTemplate adds the card and its template benefits',
      () async {
        final h = await _load(_data(cards: [], benefits: []));
        final template = cardTemplates.first;

        final card = await h.store.addCardFromTemplate(
          template,
          label: 'Ann Plat',
          anniversaryOn: '2024-05-01',
        );

        expect(h.notifications, 1);
        final saved = h.saved;
        expect(saved.cards.map((c) => c.id), [card.id]);
        expect(card.issuer, template.issuer);
        expect(card.product, template.product);
        expect(card.label, 'Ann Plat');
        expect(card.anniversaryOn, '2024-05-01');
        expect(card.createdAt, _now.toUtc().toIso8601String());
        expect(card.updatedAt, card.createdAt);
        expect(saved.benefits, hasLength(template.benefits.length));
        expect(saved.benefits.every((b) => b.cardId == card.id), isTrue);
        expect(
          saved.benefits.map((b) => b.id).toSet(),
          hasLength(saved.benefits.length),
        );
        expect(saved.benefits.map((b) => b.id), isNot(contains(card.id)));
      },
    );

    // @lat: [[mobile-tests#Store#A blank template takes the typed issuer and product]]
    test('addCardFromTemplate takes issuer and product overrides', () async {
      final h = await _load(_data(cards: [], benefits: []));
      final blank = findTemplate('blank')!;

      final card = await h.store.addCardFromTemplate(
        blank,
        issuer: 'Chase',
        product: 'Sapphire',
      );

      expect(card.issuer, 'Chase');
      expect(card.product, 'Sapphire');
      expect(card.anniversaryOn, '2026-09-16');
      expect(h.saved.benefits, isEmpty);
    });

    // @lat: [[mobile-tests#Store#Card patches stamp updatedAt]]
    test('updateCard applies the patch and stamps updatedAt', () async {
      final h = await _load();

      await h.store.updateCard(
        'card-1',
        (card) => card.copyWith(label: 'Work card', last4: '1234'),
      );

      expect(h.notifications, 1);
      final card = h.saved.cards.single;
      expect(card.label, 'Work card');
      expect(card.last4, '1234');
      expect(card.createdAt, _stamp);
      expect(card.updatedAt, _now.toUtc().toIso8601String());
    });

    // @lat: [[mobile-tests#Store#Mute is the member's and archive is a card patch]]
    test(
      'toggleCardMute flips the member’s mute and archiveCard archives',
      () async {
        final h = await _load();
        final before = appDataToJson(h.store.data!);

        await h.store.toggleCardMute('card-1');
        expect(h.savedPreferences.mutedCardIds, {'card-1'});
        expect(h.store.isCardMuted('card-1'), isTrue);
        await h.store.toggleCardMute('card-1');
        expect(h.savedPreferences.mutedCardIds, isEmpty);
        expect(appDataToJson(h.store.data!), before);
        await h.store.archiveCard('card-1');
        expect(h.saved.cards.single.archived, isTrue);
        expect(h.notifications, 3);
        expect(h.store.hasCards, isFalse);
      },
    );

    // @lat: [[mobile-tests#Store#Deleting a card cascades]]
    test(
      'deleteCard removes the card, its benefits and their claims',
      () async {
        final h = await _load(
          _data(
            cards: [
              _card(),
              _card(id: 'card-2'),
            ],
            benefits: [
              _benefit(),
              _benefit(id: 'benefit-2'),
              _benefit(id: 'benefit-3', cardId: 'card-2'),
            ],
            claims: [
              _claim(),
              _claim(id: 'claim-2', benefitId: 'benefit-2'),
              _claim(id: 'claim-3', benefitId: 'benefit-3'),
            ],
          ),
        );

        await h.store.deleteCard('card-1');

        expect(h.notifications, 1);
        final saved = h.saved;
        expect(saved.cards.map((c) => c.id), ['card-2']);
        expect(saved.benefits.map((b) => b.id), ['benefit-3']);
        expect(saved.claims.map((c) => c.id), ['claim-3']);
      },
    );
  });

  group('benefits', () {
    // @lat: [[mobile-tests#Store#A benefit draft gets its identity from the store]]
    test('addBenefit assigns the id and timestamps', () async {
      final h = await _load();

      final benefit = await h.store.addBenefit(
        _benefit(id: 'draft', valueCents: 5000),
      );

      expect(h.notifications, 1);
      expect(benefit.id, isNot('draft'));
      expect(benefit.valueCents, 5000);
      expect(benefit.createdAt, _now.toUtc().toIso8601String());
      expect(benefit.updatedAt, benefit.createdAt);
      expect(h.saved.benefits.map((b) => b.id), ['benefit-1', benefit.id]);
    });

    // @lat: [[mobile-tests#Store#Benefit patches stamp updatedAt]]
    test('updateBenefit patches and stamps', () async {
      final h = await _load();

      await h.store.updateBenefit(
        'benefit-1',
        (b) => b.copyWith(name: 'Uber Cash', valueCents: 1500),
      );
      final benefit = h.saved.benefits.single;
      expect(benefit.name, 'Uber Cash');
      expect(benefit.valueCents, 1500);
      expect(benefit.updatedAt, _now.toUtc().toIso8601String());
      expect(h.notifications, 1);
    });

    // @lat: [[mobile-tests#Store#Muting a credit leaves the household alone]]
    test('toggleBenefitMute writes the member’s preferences only', () async {
      final h = await _load();
      final before = appDataToJson(h.store.data!);

      await h.store.toggleBenefitMute('benefit-1');

      expect(h.savedPreferences.mutedBenefitIds, {'benefit-1'});
      expect(appDataToJson(h.store.data!), before);
      expect(h.store.instances.single.muted, isTrue);
      expect(h.notifications, 1);
    });

    // @lat: [[mobile-tests#Store#Enrolment is confirmed and revoked]]
    test(
      'confirmEnrollment stamps enrolledAt and revokeEnrollment clears it',
      () async {
        final h = await _load(
          _data(benefits: [_benefit(enrollmentRequired: true)]),
        );

        await h.store.confirmEnrollment('benefit-1');
        expect(
          h.saved.benefits.single.enrolledAt,
          _now.toUtc().toIso8601String(),
        );
        expect(h.store.locked, isEmpty);

        await h.store.revokeEnrollment('benefit-1');
        expect(h.saved.benefits.single.enrolledAt, isNull);
        expect(h.store.locked.single.benefit.id, 'benefit-1');
        expect(h.notifications, 2);
      },
    );

    // @lat: [[mobile-tests#Store#A spend threshold is confirmed and revoked]]
    test('confirmSpend stamps spendMetAt and revokeSpend clears it', () async {
      final h = await _load(
        _data(benefits: [_benefit(spendThresholdCents: 500000)]),
      );
      expect(h.store.locked.single.benefit.id, 'benefit-1');

      await h.store.confirmSpend('benefit-1');
      expect(
        h.saved.benefits.single.spendMetAt,
        _now.toUtc().toIso8601String(),
      );
      expect(h.store.locked, isEmpty);

      await h.store.revokeSpend('benefit-1');
      expect(h.saved.benefits.single.spendMetAt, isNull);
      expect(h.store.locked.single.benefit.id, 'benefit-1');
      expect(h.notifications, 2);
    });

    // @lat: [[mobile-tests#Store#Deleting a benefit takes its claims]]
    test('deleteBenefit removes the benefit and its claims only', () async {
      final h = await _load(
        _data(
          benefits: [
            _benefit(),
            _benefit(id: 'benefit-2'),
          ],
          claims: [
            _claim(),
            _claim(id: 'claim-2', benefitId: 'benefit-2'),
          ],
        ),
      );

      await h.store.deleteBenefit('benefit-1');

      expect(h.notifications, 1);
      expect(h.saved.benefits.map((b) => b.id), ['benefit-2']);
      expect(h.saved.claims.map((c) => c.id), ['claim-2']);
    });
  });

  group('claims', () {
    // @lat: [[mobile-tests#Store#A claim defaults to what is left]]
    test('claim without an amount records the remaining cents', () async {
      final h = await _load(_data(claims: [_claim(amountCents: 1000)]));
      final instance = h.store.instances.single;
      expect(instance.remainingCents, 1500);

      final claim = await h.store.claim(instance, note: 'Dinner');

      expect(h.notifications, 1);
      expect(claim.amountCents, 1500);
      expect(claim.note, 'Dinner');
      expect(claim.benefitId, 'benefit-1');
      expect(claim.cycleKey, '2026-09-01');
      expect(claim.claimedAt, _now.toUtc().toIso8601String());
      expect(h.saved.claims.map((c) => c.id), ['claim-1', claim.id]);
      expect(h.store.instances.single.status, BenefitStatus.captured);
    });

    // @lat: [[mobile-tests#Store#A partial claim records its amount]]
    test('claim with an amount records that amount', () async {
      final h = await _load();

      final claim = await h.store.claim(
        h.store.instances.single,
        amountCents: 700,
      );

      expect(claim.amountCents, 700);
      expect(claim.note, isNull);
      expect(h.store.instances.single.remainingCents, 1800);
    });

    // @lat: [[mobile-tests#Store#Removing one claim keeps the cycle's others]]
    test(
      'removeClaim deletes one claim and unclaim clears the cycle',
      () async {
        final h = await _load(
          _data(
            claims: [
              _claim(),
              _claim(id: 'claim-2', amountCents: 500),
              _claim(id: 'claim-3', cycleKey: '2026-08-01'),
            ],
          ),
        );

        await h.store.removeClaim('claim-1');
        expect(h.saved.claims.map((c) => c.id), ['claim-2', 'claim-3']);

        await h.store.unclaim('benefit-1', '2026-09-01');
        expect(h.saved.claims.map((c) => c.id), ['claim-3']);
        expect(h.notifications, 2);
      },
    );
  });

  group('settings', () {
    // @lat: [[mobile-tests#Store#Settings patches keep the rest]]
    test('updateSettings and updatePreferences patch in place', () async {
      final h = await _load();

      await h.store.updateSettings(
        (s) => s.copyWith(useSoonDays: 14, theme: ThemeSetting.dark),
      );
      var settings = h.saved.settings;
      expect(settings.useSoonDays, 14);
      expect(settings.theme, ThemeSetting.dark);

      await h.store.updatePreferences(
        (p) => p.copyWith(enabled: true, timeOfDay: '08:00'),
      );
      final prefs = h.savedPreferences;
      expect(prefs.enabled, isTrue);
      expect(prefs.timeOfDay, '08:00');
      expect(prefs.minValueCents, 100);
      expect(h.saved.settings.useSoonDays, 14);
      expect(h.notifications, 2);
    });
  });

  group('derived views', () {
    // @lat: [[mobile-tests#Store#Opted-out credits stay off the lists]]
    test('instances and instanceFor leave opted-out credits out', () async {
      final h = await _load(
        _data(
          benefits: [
            _benefit(),
            _benefit(id: 'oura', optedOutAt: '2026-05-01T09:00:00.000Z'),
          ],
        ),
      );
      expect(h.store.instances.map((i) => i.benefit.id), ['benefit-1']);
      expect(h.store.instanceFor('oura'), isNull);
    });
  });

  group('load', () {
    // @lat: [[mobile-tests#Store#A write before load wins]]
    test('a mutation before load completes is not overwritten', () async {
      final gate = Completer<void>();
      final slow = _GatedSnapshotStore(_data(), gate.future);
      final store = AppStore(store: slow, clock: () => _now);
      var notifications = 0;
      store.addListener(() => notifications++);

      final loading = store.load();
      final card = await store.addCardFromTemplate(findTemplate('blank')!);
      expect(store.data!.cards.map((c) => c.id), [card.id]);

      gate.complete();
      await loading;

      expect(store.loading, isFalse);
      expect(store.data!.cards.map((c) => c.id), [card.id]);
      expect(slow.saved!.cards.map((c) => c.id), [card.id]);
      expect(notifications, 2);
    });
  });
}

/// A store whose load resolves only when the test lets it, so a mutation can
/// land while the snapshot is still in flight.
class _GatedSnapshotStore implements SnapshotStore {
  _GatedSnapshotStore(this._data, this._gate);

  final AppData _data;
  final Future<void> _gate;
  AppData? saved;

  @override
  Future<AppData?> load() async {
    await _gate;
    return _data;
  }

  @override
  Future<void> save(AppData data) async => saved = data;

  @override
  Future<MemberPreferences?> loadPreferences() async => null;

  @override
  Future<void> savePreferences(MemberPreferences preferences) async {}
}
