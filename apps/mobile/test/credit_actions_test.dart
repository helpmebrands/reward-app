import 'package:domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reward/data/snapshot_store.dart';
import 'package:reward/logic/app_store.dart';
import 'package:reward/logic/credit_actions.dart';
import 'package:reward/logic/snackbar_state.dart';

/// The shared credit actions: every one writes the store at once and hands
/// the snackbar a message, with an Undo that takes exactly that change back.

const _stamp = '2026-01-01T00:00:00.000Z';

Benefit _benefit(
  String id,
  String name,
  int valueCents, {
  bool enrollmentRequired = false,
}) => Benefit(
  id: id,
  cardId: 'jim',
  name: name,
  category: BenefitCategory.dining,
  valueCents: valueCents,
  cadence: Cadence.quarterly,
  anchor: CycleAnchor.calendar,
  enrollmentRequired: enrollmentRequired,
  redemptionSteps: const [],
  lastCallOnly: false,
  active: true,
  createdAt: _stamp,
  updatedAt: _stamp,
);

AppData _household() => AppData(
  version: 1,
  cards: const [
    Card(
      id: 'jim',
      issuer: 'American Express',
      product: 'Platinum',
      network: CardNetwork.amex,
      kind: CardKind.personal,
      annualFeeCents: 89500,
      anniversaryOn: '2021-03-14',
      archived: false,
      createdAt: _stamp,
      updatedAt: _stamp,
    ),
  ],
  benefits: [
    _benefit('resy', 'Resy Dining Credit', 10000),
    _benefit('equinox', 'Equinox Credit', 30000, enrollmentRequired: true),
  ],
  claims: const [
    Claim(
      id: 'old',
      benefitId: 'resy',
      cycleKey: '2026-07-01',
      amountCents: 3000,
      claimedAt: '2026-09-02T12:00:00.000Z',
    ),
  ],
  settings: defaultSettings,
);

class _Harness {
  _Harness() {
    store = AppStore(
      store: MemorySnapshotStore(_household()),
      clock: () => DateTime(2026, 9, 16),
    );
    actions = CreditActions(store: store, snackbar: snackbar);
  }

  late final AppStore store;
  final SnackbarState snackbar = SnackbarState();
  late final CreditActions actions;

  Future<_Harness> loaded() async {
    await store.load();
    return this;
  }

  BenefitInstance instance(String id) => store.instanceFor(id)!;
  List<String> claimIds(String benefitId) => store.data!.claims
      .where((c) => c.benefitId == benefitId)
      .map((c) => c.id)
      .toList();
}

void main() {
  // @lat: [[mobile-tests#Credit actions#Logging writes at once and Undo removes that claim]]
  test('logAll claims the remainder at once and Undo removes it', () async {
    final h = await _Harness().loaded();

    final claim = await h.actions.logAll(h.instance('resy'));

    expect(claim.amountCents, 7000);
    expect(h.claimIds('resy'), ['old', claim.id]);
    final message = h.snackbar.current!;
    expect(message.text, 'Logged \$70 on Resy Dining Credit.');
    expect(message.action!.label, 'Undo');
    expect(message.action!.semanticsLabel, 'Undo logging Resy Dining Credit');

    message.action!.onAct();
    await Future<void>.delayed(Duration.zero);
    expect(h.claimIds('resy'), ['old']);
  });

  // @lat: [[mobile-tests#Credit actions#A partial log names its amount]]
  test('log with an amount records it and says so', () async {
    final h = await _Harness().loaded();

    final claim = await h.actions.log(h.instance('resy'), amountCents: 3500);

    expect(claim.amountCents, 3500);
    expect(h.snackbar.current!.text, 'Logged \$35 on Resy Dining Credit.');
  });

  // @lat: [[mobile-tests#Credit actions#Muting has an Undo that restores the previous state]]
  test(
    'toggleMute silences with an Undo, and unsilences the same way',
    () async {
      final h = await _Harness().loaded();

      await h.actions.toggleMute(h.instance('resy'));
      expect(h.store.isBenefitMuted(h.store.data!.benefits.first.id), isTrue);
      var message = h.snackbar.current!;
      expect(message.text, 'Silenced Resy Dining Credit. It is still tracked.');
      expect(
        message.action!.semanticsLabel,
        'Undo silencing Resy Dining Credit',
      );

      message.action!.onAct();
      await Future<void>.delayed(Duration.zero);
      expect(h.store.isBenefitMuted(h.store.data!.benefits.first.id), isFalse);

      await h.actions.toggleMute(h.instance('resy'));
      await h.actions.toggleMute(h.instance('resy'));
      expect(h.store.isBenefitMuted(h.store.data!.benefits.first.id), isFalse);
      message = h.snackbar.current!;
      expect(message.text, 'Reminders back on for Resy Dining Credit.');
      expect(
        message.action!.semanticsLabel,
        'Undo reminders back on for Resy Dining Credit',
      );
      message.action!.onAct();
      await Future<void>.delayed(Duration.zero);
      expect(h.store.isBenefitMuted(h.store.data!.benefits.first.id), isTrue);
    },
  );

  // @lat: [[mobile-tests#Credit actions#Opting out has an Undo that brings the credit back]]
  test('optOut takes the credit off the list with an Undo', () async {
    final h = await _Harness().loaded();

    await h.actions.optOut(h.instance('resy'));
    expect(h.store.instanceFor('resy'), isNull);
    final message = h.snackbar.current!;
    expect(
      message.text,
      'Opted out of Resy Dining Credit. Reactivate it from the card’s setup.',
    );
    expect(message.action!.label, 'Undo');
    expect(
      message.action!.semanticsLabel,
      'Undo opting out of Resy Dining Credit',
    );

    message.action!.onAct();
    await Future<void>.delayed(Duration.zero);
    expect(h.store.instanceFor('resy'), isNotNull);
    final resy = h.store.data!.benefits.firstWhere((b) => b.id == 'resy');
    expect(resy.optedOutAt, isNull);
    expect(resy.trackedFrom, isNull, reason: 'Undo is not a reactivation');
  });

  // @lat: [[mobile-tests#Credit actions#Unlocking has an Undo that revokes]]
  test('confirmEnrollment unlocks with an Undo that revokes', () async {
    final h = await _Harness().loaded();

    await h.actions.confirmEnrollment(h.instance('equinox'));
    expect(h.store.data!.benefits[1].enrolledAt, isNotNull);
    final message = h.snackbar.current!;
    expect(message.text, 'Equinox Credit unlocked.');
    expect(message.action!.semanticsLabel, 'Undo unlocking Equinox Credit');

    message.action!.onAct();
    await Future<void>.delayed(Duration.zero);
    expect(h.store.data!.benefits[1].enrolledAt, isNull);
  });

  // @lat: [[mobile-tests#Credit actions#Removing and clearing report without an Undo]]
  test('removeClaim and unclaimAll report plainly', () async {
    final h = await _Harness().loaded();
    final instance = h.instance('resy');
    final claim = h.store.claimsFor('resy', instance.cycle.key).single;

    await h.actions.removeClaim(instance, claim);
    expect(h.claimIds('resy'), isEmpty);
    expect(h.snackbar.current!.text, 'Removed \$30 from Resy Dining Credit.');
    expect(h.snackbar.current!.action, isNull);

    await h.actions.log(h.instance('resy'), amountCents: 1000);
    await h.actions.unclaimAll(h.instance('resy'));
    expect(h.claimIds('resy'), isEmpty);
    expect(
      h.snackbar.current!.text,
      'Cleared what was logged against Resy Dining Credit.',
    );
    expect(h.snackbar.current!.action, isNull);
  });
}
