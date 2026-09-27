import 'package:domain/domain.dart';
import 'package:test/test.dart';

import 'factories.dart';

/// The value bar's four segments: earned, available, missed and opt out, for
/// one credit's current window, a card's calendar year to date and the
/// household.

const today = '2026-09-16';
const optedOut = '2026-05-01T09:00:00.000Z';

ValueBreakdown _credit(AppData data) =>
    creditBreakdown(currentInstances(data, today).single);

ValueBreakdown _card(AppData data) =>
    cardYearToDateBreakdown(data.cards.first, data, today);

ValueBreakdown _breakdown({
  int earned = 0,
  int available = 0,
  int missed = 0,
  int optOut = 0,
}) => ValueBreakdown(
  earnedCents: earned,
  availableCents: available,
  missedCents: missed,
  optOutCents: optOut,
);

void main() {
  group('ValueBreakdown', () {
    // @lat: [[tests#Value breakdown#Breakdowns sum segment by segment]]
    test('totals its segments and sums with +', () {
      final a = _breakdown(earned: 100, available: 200, missed: 300);
      final b = _breakdown(earned: 1, optOut: 4);
      expect(a.totalCents, 600);
      expect(
        a + b,
        _breakdown(earned: 101, available: 200, missed: 300, optOut: 4),
      );
      expect(ValueBreakdown.zero.totalCents, 0);
    });
  });

  group('creditBreakdown', () {
    // @lat: [[tests#Value breakdown#A credit splits its window into earned and available]]
    test('splits the current window into earned and available', () {
      final data = makeData(
        benefits: [makeBenefit(Cadence.monthly, valueCents: 10000)],
        claims: [makeClaim(amountCents: 3000)],
      );
      expect(_credit(data), _breakdown(earned: 3000, available: 7000));
    });

    // @lat: [[tests#Value breakdown#Un-enrolled and opted-out credits are opt out]]
    test('puts an un-enrolled or opted-out credit in opt out', () {
      final unenrolled = makeData(
        benefits: [
          makeBenefit(
            Cadence.monthly,
            valueCents: 5000,
            enrollmentRequired: true,
          ),
        ],
      );
      final declined = makeData(
        benefits: [
          makeBenefit(Cadence.monthly, valueCents: 5000, optedOutAt: optedOut),
        ],
      );
      expect(_credit(unenrolled), _breakdown(optOut: 5000));
      expect(_credit(declined), _breakdown(optOut: 5000));
    });

    // @lat: [[tests#Value breakdown#A spend-gated credit is left out]]
    test('leaves out a spend-gated credit whose spend is not met', () {
      final data = makeData(
        benefits: [
          makeBenefit(
            Cadence.monthly,
            valueCents: 5000,
            spendThresholdCents: 400000,
          ),
        ],
      );
      expect(_credit(data), ValueBreakdown.zero);
      expect(_card(data), ValueBreakdown.zero);
    });
  });

  group('cardYearToDateBreakdown', () {
    final card2025 = makeCard(createdAt: '2025-06-01T00:00:00.000Z');

    // @lat: [[tests#Value breakdown#A card counts this year's closed windows]]
    test('adds the windows closed this year to earned and missed', () {
      final data = makeData(
        cards: [card2025],
        benefits: [makeBenefit(Cadence.monthly, valueCents: 1500)],
      );
      expect(_card(data), _breakdown(available: 1500, missed: 12000));

      final claimed = data.copyWith(
        claims: [
          makeClaim(
            cycleKey: '2026-03-01',
            amountCents: 1500,
            claimedAt: '2026-03-10T12:00:00.000Z',
          ),
        ],
      );
      expect(
        _card(claimed),
        _breakdown(earned: 1500, available: 1500, missed: 10500),
      );
    });

    // @lat: [[tests#Value breakdown#Windows before the card was added are not missed]]
    test('does not count windows that opened before the card was added', () {
      final data = makeData(
        cards: [makeCard(createdAt: '2026-05-10T00:00:00.000Z')],
        benefits: [makeBenefit(Cadence.monthly, valueCents: 1500)],
      );
      // June, July and August; May opened before the card was added.
      expect(_card(data), _breakdown(available: 1500, missed: 4500));
    });

    // @lat: [[tests#Value breakdown#Last year's windows are not counted]]
    test('does not count a window that closed last year', () {
      final data = makeData(
        cards: [makeCard(createdAt: '2024-01-15T00:00:00.000Z')],
        benefits: [makeBenefit(Cadence.annual, valueCents: 20000)],
      );
      expect(_card(data), _breakdown(available: 20000));
    });

    // @lat: [[tests#Value breakdown#A multi-year window counts whole]]
    test('counts a 48-month window that opened in 2024 in full', () {
      final data = makeData(
        cards: [makeCard(createdAt: '2024-02-01T00:00:00.000Z')],
        benefits: [
          makeBenefit(
            Cadence.rolling,
            valueCents: 12000,
            intervalMonths: 48,
          ),
        ],
        claims: [
          makeClaim(
            cycleKey: '2024-02-01',
            amountCents: 12000,
            claimedAt: '2024-05-01T12:00:00.000Z',
          ),
        ],
      );
      expect(_card(data), _breakdown(earned: 12000));
    });

    // @lat: [[tests#Value breakdown#A card's opt out is its current windows]]
    test('counts an opted-out credit as opt out for its current window', () {
      final data = makeData(
        cards: [card2025],
        benefits: [
          makeBenefit(Cadence.monthly, valueCents: 1500, optedOutAt: optedOut),
          makeBenefit(
            Cadence.quarterly,
            id: 'locked',
            valueCents: 5000,
            enrollmentRequired: true,
          ),
        ],
      );
      expect(_card(data), _breakdown(optOut: 6500));
    });
  });

  group('householdBreakdown', () {
    // @lat: [[tests#Value breakdown#The household sums its active cards]]
    test('sums every unarchived card', () {
      final data = makeData(
        cards: [
          makeCard(createdAt: '2025-06-01T00:00:00.000Z'),
          makeCard(id: 'card-2'),
          makeCard(id: 'card-3', archived: true),
        ],
        benefits: [
          makeBenefit(Cadence.monthly, valueCents: 1500),
          makeBenefit(
            Cadence.annual,
            id: 'b2',
            cardId: 'card-2',
            valueCents: 20000,
          ),
          makeBenefit(
            Cadence.annual,
            id: 'b3',
            cardId: 'card-3',
            valueCents: 30000,
          ),
        ],
        claims: [
          makeClaim(
            benefitId: 'b2',
            cycleKey: '2026-01-01',
            amountCents: 5000,
          ),
        ],
      );
      final expected =
          cardYearToDateBreakdown(data.cards[0], data, today) +
          cardYearToDateBreakdown(data.cards[1], data, today);
      expect(householdBreakdown(data, today), expected);
      expect(
        expected,
        _breakdown(earned: 5000, available: 1500 + 15000, missed: 12000),
      );
    });
  });
}
