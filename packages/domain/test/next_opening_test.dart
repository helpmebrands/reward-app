import 'package:domain/domain.dart';
import 'package:test/test.dart';

import 'factories.dart';
import 'sample_household_test.dart' show loadSampleHousehold;

/// The next day a credit window opens, which Today's "Next up" card names
/// once nothing is left to claim.

const today = '2026-09-16';

void main() {
  // @lat: [[tests#Next opening#The sample household opens Uber Cash on Oct 1]]
  test('the sample household next opens its monthly credits on Oct 1', () {
    final data = loadSampleHousehold();
    final claims = [
      for (final instance in currentInstances(data, today))
        if (instance.remainingCents > 0)
          Claim(
            id: 'all-${instance.benefit.id}',
            benefitId: instance.benefit.id,
            cycleKey: instance.cycle.key,
            amountCents: instance.remainingCents,
            claimedAt: '2026-09-15T12:00:00.000Z',
          ),
    ];
    final captured = data.copyWith(claims: [...data.claims, ...claims]);

    final next = nextOpening(captured, today)!;
    expect(next.on, '2026-10-01');
    final uber = next.benefits.where((b) => b.name == 'Uber Cash').toList();
    expect(uber, hasLength(2));
    expect(uber.map((b) => b.cardId).toSet(), hasLength(2));
  });

  // @lat: [[tests#Next opening#Credits opening the same day come together]]
  test('returns every credit opening that day, with its value', () {
    final data = makeData(
      benefits: [
        makeBenefit(Cadence.monthly, id: 'a', valueCents: 1500),
        makeBenefit(Cadence.quarterly, id: 'b', valueCents: 10000),
        makeBenefit(Cadence.annual, id: 'c', valueCents: 20000),
      ],
    );
    final next = nextOpening(data, today)!;
    expect(next.on, '2026-10-01');
    expect(next.benefits.map((b) => b.id), ['a', 'b']);
    expect(next.valueCents, 11500);
  });

  // @lat: [[tests#Next opening#Opted-out, archived and ending credits are ignored]]
  test('ignores opted-out, archived-card and ending credits', () {
    final data = makeData(
      cards: [
        makeCard(),
        makeCard(id: 'card-2', archived: true),
      ],
      benefits: [
        makeBenefit(
          Cadence.monthly,
          id: 'opted',
          optedOutAt: '2026-05-01T09:00:00.000Z',
        ),
        makeBenefit(Cadence.monthly, id: 'archived', cardId: 'card-2'),
        makeBenefit(Cadence.monthly, id: 'ending', endsOn: '2026-09-30'),
        makeBenefit(Cadence.quarterly, id: 'inactive', active: false),
        makeBenefit(Cadence.annual, id: 'annual'),
      ],
    );
    final next = nextOpening(data, today)!;
    expect(next.on, '2027-01-01');
    expect(next.benefits.map((b) => b.id), ['annual']);
  });

  // @lat: [[tests#Next opening#A locked credit is not next up]]
  test('skips a credit that will still be locked when it opens', () {
    final data = makeData(
      benefits: [
        makeBenefit(Cadence.monthly, id: 'locked', enrollmentRequired: true),
        makeBenefit(
          Cadence.quarterly,
          id: 'spend',
          spendThresholdCents: 100000,
        ),
        makeBenefit(Cadence.annual, id: 'open'),
      ],
    );
    final next = nextOpening(data, today)!;
    expect(next.on, '2027-01-01');
    expect(next.benefits.map((b) => b.id), ['open']);
  });

  // @lat: [[tests#Next opening#Nothing opening again is null]]
  test('is null when no credit will open again', () {
    final data = makeData(
      benefits: [
        makeBenefit(Cadence.manual, id: 'manual'),
        makeBenefit(Cadence.monthly, id: 'ending', endsOn: '2026-09-30'),
      ],
    );
    expect(nextOpening(data, today), isNull);
    expect(nextOpening(makeData(benefits: []), today), isNull);
  });
}
