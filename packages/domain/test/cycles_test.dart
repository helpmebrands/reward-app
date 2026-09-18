import 'package:domain/domain.dart';
import 'package:test/test.dart';

import 'factories.dart';

/// Narrows a nullable cycle, failing loudly rather than silently skipping.
Cycle expectCycle(Cycle? cycle) {
  expect(cycle, isNotNull);
  return cycle!;
}

// @lat: [[tests#Cycles]]
void main() {
  group('cycleFor, calendar anchored', () {
    final card = makeCard();

    test('bounds a monthly cycle to the calendar month', () {
      expect(
        cycleFor(makeBenefit(Cadence.monthly), card, '2026-09-16'),
        const Cycle(
          key: '2026-09-01',
          start: '2026-09-01',
          end: '2026-09-30',
          label: 'Sep 2026',
        ),
      );
    });

    test('handles February in a leap year', () {
      expect(
        cycleFor(makeBenefit(Cadence.monthly), card, '2024-02-10')?.end,
        '2024-02-29',
      );
    });

    test('puts quarters on Jan/Apr/Jul/Oct', () {
      final quarterly = makeBenefit(Cadence.quarterly);
      expect(
        cycleFor(quarterly, card, '2026-09-16'),
        const Cycle(
          key: '2026-07-01',
          start: '2026-07-01',
          end: '2026-09-30',
          label: 'Q3 2026',
        ),
      );
      expect(cycleFor(quarterly, card, '2026-01-01')?.start, '2026-01-01');
      expect(cycleFor(quarterly, card, '2026-12-31')?.start, '2026-10-01');
    });

    test('splits semi-annual credits at Jan 1 and Jul 1', () {
      final semiannual = makeBenefit(Cadence.semiannual);
      expect(
        cycleFor(semiannual, card, '2026-06-30'),
        const Cycle(
          key: '2026-01-01',
          start: '2026-01-01',
          end: '2026-06-30',
          label: 'H1 2026',
        ),
      );
      expect(cycleFor(semiannual, card, '2026-07-01')?.label, 'H2 2026');
    });

    test('bounds an annual credit to the calendar year', () {
      expect(
        cycleFor(makeBenefit(Cadence.annual), card, '2026-09-16'),
        const Cycle(
          key: '2026-01-01',
          start: '2026-01-01',
          end: '2026-12-31',
          label: '2026',
        ),
      );
    });

    test('resolves dates before the anchor year', () {
      expect(
        cycleFor(makeBenefit(Cadence.quarterly), card, '2018-05-04')?.start,
        '2018-04-01',
      );
    });
  });

  group('cycleFor, anniversary anchored', () {
    final card = makeCard(anniversaryOn: '2020-03-14');
    final benefit = makeBenefit(
      Cadence.annual,
      anchor: CycleAnchor.anniversary,
    );

    test('runs a cardmember year from the account open date', () {
      final cycle = expectCycle(cycleFor(benefit, card, '2026-09-16'));
      expect(cycle.start, '2026-03-14');
      expect(cycle.end, '2027-03-13');
    });

    test('places a date just before the anniversary in the prior year', () {
      final cycle = expectCycle(cycleFor(benefit, card, '2026-03-13'));
      expect(cycle.start, '2025-03-14');
      expect(cycle.end, '2026-03-13');
    });

    test('starts the new cycle on the anniversary itself', () {
      expect(cycleFor(benefit, card, '2026-03-14')?.start, '2026-03-14');
    });

    test('does not drift for a 31st anniversary across short months', () {
      // Month-clamping is the trap: Jan 31 + 1 month is Feb 28, so the step
      // count must be corrected by comparison rather than derived from a
      // month count.
      final shortMonthCard = makeCard(anniversaryOn: '2021-01-31');
      final monthly = makeBenefit(
        Cadence.monthly,
        anchor: CycleAnchor.anniversary,
      );
      final before = expectCycle(
        cycleFor(monthly, shortMonthCard, '2026-02-27'),
      );
      expect(before.start, '2026-01-31');
      expect(before.end, '2026-02-27');
      final after = expectCycle(
        cycleFor(monthly, shortMonthCard, '2026-02-28'),
      );
      expect(after.start, '2026-02-28');
      expect(after.end, '2026-03-30');
    });

    test('produces windows with no gaps and no overlaps', () {
      // The invariant that matters: every day belongs to exactly one cycle.
      final shortMonthCard = makeCard(anniversaryOn: '2021-01-31');
      final monthly = makeBenefit(
        Cadence.monthly,
        anchor: CycleAnchor.anniversary,
      );
      final cycles = cyclesBetween(
        monthly,
        shortMonthCard,
        '2026-01-01',
        '2027-01-01',
      );
      expect(cycles.length, greaterThan(10));
      for (var index = 0; index < cycles.length; index++) {
        final cycle = cycles[index];
        expect(daysBetween(cycle.start, cycle.end), greaterThanOrEqualTo(26));
        if (index + 1 < cycles.length) {
          expect(addDays(cycle.end, 1), cycles[index + 1].start);
        }
      }
    });

    test('labels anniversary windows by date, since Q3 would be a lie', () {
      expect(cycleFor(benefit, card, '2026-09-16')?.label, 'from Mar 14 2026');
    });
  });

  group('manual benefits', () {
    test('have no window and never recur', () {
      final benefit = makeBenefit(Cadence.manual);
      final card = makeCard();
      expect(cycleFor(benefit, card, '2026-09-16'), isNull);
      expect(cyclesBetween(benefit, card, '2026-01-01', '2027-01-01'), isEmpty);
    });
  });

  group('cyclesBetween', () {
    test('returns every monthly window overlapping the range', () {
      final cycles = cyclesBetween(
        makeBenefit(Cadence.monthly),
        makeCard(),
        '2026-09-16',
        '2026-12-01',
      );
      expect(cycles.map((c) => c.start).toList(), [
        '2026-09-01',
        '2026-10-01',
        '2026-11-01',
        '2026-12-01',
      ]);
    });

    test('is bounded by maxCycles', () {
      final cycles = cyclesBetween(
        makeBenefit(Cadence.monthly),
        makeCard(),
        '2026-01-01',
        '2099-01-01',
        maxCycles: 5,
      );
      expect(cycles, hasLength(5));
    });
  });

  group('closedCyclesBefore', () {
    test('walks backwards from the current window, newest first', () {
      final cycles = closedCyclesBefore(
        makeBenefit(Cadence.quarterly),
        makeCard(),
        '2026-09-16',
        3,
      );
      expect(cycles.map((c) => c.label).toList(), [
        'Q2 2026',
        'Q1 2026',
        'Q4 2025',
      ]);
    });

    test('never includes the open window', () {
      final cycles = closedCyclesBefore(
        makeBenefit(Cadence.monthly),
        makeCard(),
        '2026-09-16',
        5,
      );
      expect(cycles.every((c) => c.end.compareTo('2026-09-16') < 0), isTrue);
    });
  });

  group('nextCycle', () {
    test('starts the day after the previous window closes', () {
      final card = makeCard();
      final benefit = makeBenefit(Cadence.monthly);
      final current = expectCycle(cycleFor(benefit, card, '2026-09-16'));
      expect(nextCycle(benefit, card, current)?.start, '2026-10-01');
    });
  });

  group('daysRemainingIn', () {
    test('counts the final day as zero days remaining', () {
      final cycle = expectCycle(
        cycleFor(makeBenefit(Cadence.monthly), makeCard(), '2026-09-16'),
      );
      expect(daysRemainingIn(cycle, '2026-09-30'), 0);
      expect(daysRemainingIn(cycle, '2026-09-16'), 14);
      expect(daysRemainingIn(cycle, '2026-10-01'), -1);
    });
  });

  group('cycleProgress', () {
    test('runs from 0 at the start to 1 once the window has closed', () {
      const cycle = Cycle(
        key: '2026-09-01',
        start: '2026-09-01',
        end: '2026-09-30',
        label: 'Sep 2026',
      );
      expect(cycleProgress(cycle, '2026-09-01'), 0);
      expect(cycleProgress(cycle, '2026-09-16'), closeTo(0.5, 0.05));
      expect(cycleProgress(cycle, '2026-10-05'), 1);
    });
  });

  group('annualValueCents', () {
    test('scales each cadence to a yearly figure', () {
      expect(
        annualValueCents(makeBenefit(Cadence.monthly, valueCents: 1500)),
        18000,
      );
      expect(
        annualValueCents(makeBenefit(Cadence.quarterly, valueCents: 5000)),
        20000,
      );
      expect(
        annualValueCents(makeBenefit(Cadence.semiannual, valueCents: 5000)),
        10000,
      );
      expect(
        annualValueCents(makeBenefit(Cadence.annual, valueCents: 30000)),
        30000,
      );
    });

    test('counts an untracked credit once, not once per notional year', () {
      // Global Entry is $120 every four years; calling it $120 a year would
      // overstate what the card is worth.
      expect(
        annualValueCents(makeBenefit(Cadence.manual, valueCents: 12000)),
        12000,
      );
    });
  });
}
