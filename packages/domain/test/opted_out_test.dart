import 'package:domain/domain.dart';
import 'package:test/test.dart';

import 'factories.dart';

/// Credits the household will never use: opted out, they leave every list
/// and total except their own figure, and reactivating one never counts the
/// gap as missed.

const today = '2026-09-16';
const optedOut = '2026-05-01T09:00:00.000Z';

Map<String, Object?> _legacy({IsoDate? endsOn}) => {
  'id': 'b',
  'cardId': 'c',
  'name': 'Oura',
  'category': 'wellness',
  'valueCents': 20000,
  'cadence': 'annual',
  'anchor': 'calendar',
  'enrollmentRequired': false,
  if (endsOn != null) 'endsOn': endsOn,
  'lastCallOnly': false,
  'active': false,
  'createdAt': '2026-01-01T00:00:00.000Z',
  'updatedAt': optedOut,
};

void main() {
  group('an opted-out credit', () {
    // @lat: [[tests#Opted-out credits#Opted out outranks every other rung]]
    test('is opted out whatever else holds, and never claimable', () {
      final data = makeData(
        benefits: [
          makeBenefit(Cadence.monthly, id: 'used', optedOutAt: optedOut),
          makeBenefit(
            Cadence.monthly,
            id: 'locked',
            enrollmentRequired: true,
            optedOutAt: optedOut,
          ),
          makeBenefit(Cadence.monthly, id: 'open', optedOutAt: optedOut),
        ],
        claims: [makeClaim(benefitId: 'used')],
      );
      final instances = currentInstances(data, today);
      expect(instances.map((i) => i.status).toSet(), {BenefitStatus.optedOut});
      expect(instances.where(isClaimable), isEmpty);
      expect(statusLabel(BenefitStatus.optedOut), 'Opted out');
    });

    // @lat: [[tests#Opted-out credits#Opted out is its own total]]
    test('counts its annual value in optedOutCents and nowhere else', () {
      final data = makeData(
        benefits: [
          makeBenefit(Cadence.monthly, id: 'open', valueCents: 1500),
          makeBenefit(
            Cadence.monthly,
            id: 'oura',
            valueCents: 2500,
            optedOutAt: optedOut,
          ),
          makeBenefit(
            Cadence.annual,
            id: 'equinox',
            valueCents: 10000,
            enrollmentRequired: true,
            optedOutAt: optedOut,
          ),
        ],
        claims: [makeClaim(benefitId: 'oura', amountCents: 1000)],
      );
      expect(
        totalsFor(currentInstances(data, today), 0),
        const Totals(
          claimableCents: 1500,
          lockedCents: 0,
          capturedCents: 0,
          missedCents: 0,
          optedOutCents: 2500 * 12 + 10000,
        ),
      );
    });

    // @lat: [[tests#Opted-out credits#Opted out is never missed]]
    test('is left out of the missed ledger', () {
      final data = makeData(
        cards: [makeCard(createdAt: '2026-01-01T00:00:00.000Z')],
        benefits: [makeBenefit(Cadence.monthly, optedOutAt: optedOut)],
      );
      expect(missedCycles(data, today), isEmpty);
    });

    // @lat: [[tests#Opted-out credits#Opted out is never reminded]]
    test('is never scheduled', () {
      final data = makeData(
        benefits: [makeBenefit(Cadence.monthly, optedOutAt: optedOut)],
      );
      final prefs = defaultMemberPreferences.copyWith(enabled: true);
      expect(
        buildSchedule(data, prefs, DateTime(2026, 9, 16, 8)).reminders,
        isEmpty,
      );
    });
  });

  // @lat: [[tests#Opted-out credits#Windows closed before tracking resumed are not missed]]
  test('a window that closed before trackedFrom is never missed', () {
    final data = makeData(
      cards: [makeCard(createdAt: '2026-01-01T00:00:00.000Z')],
      benefits: [
        makeBenefit(Cadence.monthly, valueCents: 1500, trackedFrom: '2026-06-10'),
      ],
    );
    expect(missedCycles(data, today).map((m) => m.cycle.label).toList(), [
      'Aug 2026',
      'Jul 2026',
      'Jun 2026',
    ]);
  });

  // @lat: [[tests#Opted-out credits#A card has a potential and a usable value]]
  test('summarizeCard splits potential from usable value', () {
    final data = makeData(
      benefits: [
        makeBenefit(Cadence.monthly, id: 'open', valueCents: 1500),
        makeBenefit(
          Cadence.annual,
          id: 'oura',
          valueCents: 20000,
          optedOutAt: optedOut,
        ),
        makeBenefit(
          Cadence.annual,
          id: 'gated',
          valueCents: 50000,
          spendThresholdCents: 25000000,
        ),
      ],
    );
    final summary = summarizeCard(
      data.cards.first,
      data,
      currentInstances(data, today),
      const [],
      today,
    );
    expect(summary.potentialValueCents, 18000 + 20000);
    expect(summary.annualValueCents, 18000);
    expect(summary.optedOutCents, 20000);
  });

  group('the codec', () {
    // @lat: [[tests#Opted-out credits#Opted out and tracked from round-trip]]
    test('round-trips optedOutAt and trackedFrom, omitted when absent', () {
      final benefit = makeBenefit(
        Cadence.monthly,
        optedOutAt: optedOut,
        trackedFrom: '2026-06-10',
      );
      final json = benefitToJson(benefit);
      expect(json['optedOutAt'], optedOut);
      expect(json['trackedFrom'], '2026-06-10');
      final back = benefitFromJson(json);
      expect(back.optedOutAt, optedOut);
      expect(back.trackedFrom, '2026-06-10');

      final plain = benefitToJson(
        benefit.copyWith(optedOutAt: null, trackedFrom: null),
      );
      expect(plain.containsKey('optedOutAt'), isFalse);
      expect(plain.containsKey('trackedFrom'), isFalse);
      expect(benefitFromJson(plain).optedOutAt, isNull);
    });

    // @lat: [[tests#Opted-out credits#A paused credit loads as opted out]]
    test('loads a paused credit as opted out, an ended one as inactive', () {
      final paused = benefitFromJson(_legacy());
      expect(paused.active, isTrue);
      expect(paused.optedOutAt, optedOut);

      final endingLater = benefitFromJson(_legacy(endsOn: '2026-12-31'));
      expect(endingLater.active, isTrue);
      expect(endingLater.optedOutAt, optedOut);

      final ended = benefitFromJson(_legacy(endsOn: '2026-03-31'));
      expect(ended.active, isFalse);
      expect(ended.optedOutAt, isNull);
    });
  });

  // @lat: [[tests#Opted-out credits#A linked credit carries its opt-out]]
  test('benefitFromCredit carries optedOutAt and trackedFrom', () {
    const credit = BenefitTemplate(
      id: 'plat/oura',
      name: 'Oura',
      category: BenefitCategory.wellness,
      icon: 'heartbeat',
      valueCents: 20000,
      cadence: Cadence.annual,
      anchor: CycleAnchor.calendar,
    );
    final benefit = benefitFromCredit(
      credit,
      const LinkedBenefitState(
        id: 'b',
        cardId: 'c',
        templateBenefitId: 'plat/oura',
        optedOutAt: optedOut,
        trackedFrom: '2026-06-10',
        createdAt: 't',
        updatedAt: 't',
      ),
    );
    expect(benefit.optedOutAt, optedOut);
    expect(benefit.trackedFrom, '2026-06-10');
  });
}
