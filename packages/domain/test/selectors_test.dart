import 'package:domain/domain.dart';
import 'package:test/test.dart';

import 'factories.dart';

const today = '2026-09-16';

void main() {
  // @lat: [[tests#Statuses, totals and ledgers]]
  group('the status ladder', () {
    test('calls a credit Use soon inside the 30-day horizon', () {
      final data = makeData(benefits: [makeBenefit(Cadence.monthly)]);
      expect(currentInstances(data, today).first.status, BenefitStatus.useSoon);
    });

    test(
      'calls a credit Available when it has more than a month of runway',
      () {
        final data = makeData(benefits: [makeBenefit(Cadence.annual)]);
        expect(
          currentInstances(data, today).first.status,
          BenefitStatus.available,
        );
      },
    );

    test('calls a fully claimed credit Captured', () {
      final data = makeData(
        benefits: [makeBenefit(Cadence.monthly, valueCents: 2500)],
        claims: [makeClaim(amountCents: 2500)],
      );
      final instance = currentInstances(data, today).first;
      expect(instance.status, BenefitStatus.captured);
      expect(instance.remainingCents, 0);
    });

    test('keeps a partly used credit open, with only the balance at stake', () {
      final data = makeData(
        benefits: [makeBenefit(Cadence.monthly, valueCents: 2500)],
        claims: [makeClaim(amountCents: 1000)],
      );
      final instance = currentInstances(data, today).first;
      expect(instance.status, BenefitStatus.useSoon);
      expect(instance.remainingCents, 1500);
      expect(instance.claimedCents, 1000);
    });

    test('sums several partial claims within one cycle', () {
      final data = makeData(
        benefits: [makeBenefit(Cadence.monthly, valueCents: 2500)],
        claims: [
          makeClaim(id: 'c1', amountCents: 1000),
          makeClaim(id: 'c2', amountCents: 1500),
        ],
      );
      expect(
        currentInstances(data, today).first.status,
        BenefitStatus.captured,
      );
    });

    test('calls an un-enrolled credit Locked rather than Use soon', () {
      // The distinction the whole app rests on: this is not money the user is
      // failing to spend, it is money they cannot spend at all yet.
      final data = makeData(
        benefits: [makeBenefit(Cadence.monthly, enrollmentRequired: true)],
      );
      expect(currentInstances(data, today).first.status, BenefitStatus.locked);
    });

    test('unlocks once enrolment is confirmed', () {
      final data = makeData(
        benefits: [
          makeBenefit(
            Cadence.monthly,
            enrollmentRequired: true,
            enrolledAt: '2026-09-01T00:00:00.000Z',
          ),
        ],
      );
      expect(currentInstances(data, today).first.status, BenefitStatus.useSoon);
    });

    test('calls an untracked credit Manual, never at risk', () {
      final data = makeData(benefits: [makeBenefit(Cadence.manual)]);
      expect(currentInstances(data, today).first.status, BenefitStatus.manual);
    });

    test(
      'counts a credit as Captured even while locked, if it was already used',
      () {
        final data = makeData(
          benefits: [
            makeBenefit(
              Cadence.monthly,
              enrollmentRequired: true,
              valueCents: 2500,
            ),
          ],
          claims: [makeClaim(amountCents: 2500)],
        );
        expect(
          currentInstances(data, today).first.status,
          BenefitStatus.captured,
        );
      },
    );

    test('skips archived cards and inactive credits', () {
      final data = makeData(
        cards: [makeCard(archived: true)],
        benefits: [makeBenefit(Cadence.monthly)],
      );
      expect(currentInstances(data, today), isEmpty);
      expect(
        currentInstances(
          makeData(benefits: [makeBenefit(Cadence.monthly, active: false)]),
          today,
        ),
        isEmpty,
      );
    });

    test('marks a credit muted when its card is muted', () {
      final data = makeData(cards: [makeCard(muted: true)]);
      expect(currentInstances(data, today).first.muted, isTrue);
    });
  });

  group('ordering', () {
    test('puts what closes soonest first, and locked below open', () {
      final data = makeData(
        benefits: [
          makeBenefit(Cadence.annual, id: 'annual'),
          makeBenefit(Cadence.monthly, id: 'locked', enrollmentRequired: true),
          makeBenefit(Cadence.monthly, id: 'monthly'),
        ],
      );
      expect(currentInstances(data, today).map((i) => i.benefit.id).toList(), [
        'monthly',
        'annual',
        'locked',
      ]);
    });
  });

  group('totals', () {
    test('keeps claimable, locked, captured and missed apart', () {
      final data = makeData(
        benefits: [
          makeBenefit(Cadence.monthly, id: 'open', valueCents: 1500),
          makeBenefit(
            Cadence.monthly,
            id: 'blocked',
            valueCents: 2500,
            enrollmentRequired: true,
          ),
          makeBenefit(Cadence.monthly, id: 'done', valueCents: 1000),
        ],
        claims: [makeClaim(benefitId: 'done', amountCents: 1000)],
      );
      final totals = totalsFor(currentInstances(data, today), 5000);
      expect(
        totals,
        const Totals(
          claimableCents: 1500,
          lockedCents: 2500,
          capturedCents: 1000,
          missedCents: 5000,
        ),
      );
    });
  });

  group('nextReset', () {
    test('reports the nearest window close among open credits', () {
      final data = makeData(
        benefits: [
          makeBenefit(Cadence.annual, id: 'a'),
          makeBenefit(Cadence.monthly, id: 'm'),
        ],
      );
      expect(nextReset(currentInstances(data, today)), '2026-09-30');
    });

    test('is null when nothing is open', () {
      expect(nextReset([]), isNull);
    });
  });

  group('findOverlaps, the same credit held twice', () {
    final jim = makeCard(id: 'jim', holder: 'Jim');
    final kathy = makeCard(id: 'kathy', holder: 'Kathy');

    test('flags one credit carried by two cards in the household', () {
      final data = makeData(
        cards: [jim, kathy],
        benefits: [
          makeBenefit(
            Cadence.quarterly,
            id: 'b1',
            cardId: 'jim',
            name: 'Resy Dining Credit',
          ),
          makeBenefit(
            Cadence.quarterly,
            id: 'b2',
            cardId: 'kathy',
            name: 'Resy Dining Credit',
          ),
        ],
      );
      final overlaps = findOverlaps(currentInstances(data, today));
      expect(overlaps, hasLength(1));
      expect(overlaps.first.label, 'Resy Dining Credit');
      expect(overlaps.first.sameProduct, isTrue);
      expect(overlaps.first.instances.map((i) => i.card.holder).toList(), [
        'Jim',
        'Kathy',
      ]);
    });

    test('matches across issuers by merchant, not by name', () {
      final data = makeData(
        cards: [
          jim,
          makeCard(
            id: 'chase',
            holder: 'Kathy',
            issuer: 'Chase',
            product: 'Reserve',
          ),
        ],
        benefits: [
          makeBenefit(
            Cadence.monthly,
            id: 'b1',
            cardId: 'jim',
            name: 'Uber Cash',
            merchant: 'Uber',
          ),
          makeBenefit(
            Cadence.monthly,
            id: 'b2',
            cardId: 'chase',
            name: 'Rideshare Credit',
            merchant: 'Uber',
          ),
        ],
      );
      final overlaps = findOverlaps(currentInstances(data, today));
      expect(overlaps, hasLength(1));
      expect(overlaps.first.sameProduct, isFalse);
    });

    test('does not flag two credits that merely sit on the same card', () {
      final data = makeData(
        benefits: [
          makeBenefit(
            Cadence.monthly,
            id: 'b1',
            name: 'Uber Cash',
            merchant: 'Uber',
          ),
          makeBenefit(
            Cadence.annual,
            id: 'b2',
            name: 'Uber One',
            merchant: 'Uber',
          ),
        ],
      );
      expect(findOverlaps(currentInstances(data, today)), isEmpty);
    });

    test('totals what is still unclaimed across the pair', () {
      final data = makeData(
        cards: [jim, kathy],
        benefits: [
          makeBenefit(
            Cadence.quarterly,
            id: 'b1',
            cardId: 'jim',
            valueCents: 10000,
          ),
          makeBenefit(
            Cadence.quarterly,
            id: 'b2',
            cardId: 'kathy',
            valueCents: 10000,
          ),
        ],
        claims: [
          makeClaim(benefitId: 'b1', cycleKey: '2026-07-01', amountCents: 4000),
        ],
      );
      expect(
        findOverlaps(currentInstances(data, today)).first.remainingCents,
        16000,
      );
    });
  });

  group('missedCycles', () {
    test('counts a closed window with nothing claimed against it', () {
      final data = makeData(
        cards: [makeCard(createdAt: '2026-01-01T00:00:00.000Z')],
        benefits: [makeBenefit(Cadence.monthly, valueCents: 1500)],
      );
      final missed = missedCycles(data, today);
      expect(missed, hasLength(8)); // January through August
      expect(missed.first.cycle.label, 'Aug 2026');
      expect(missed.fold(0, (sum, m) => sum + m.missedCents), 12000);
    });

    test('counts only the shortfall when a window was partly used', () {
      final data = makeData(
        cards: [makeCard(createdAt: '2026-08-01T00:00:00.000Z')],
        benefits: [makeBenefit(Cadence.monthly, valueCents: 1500)],
        claims: [makeClaim(cycleKey: '2026-08-01', amountCents: 500)],
      );
      final missed = missedCycles(data, today);
      expect(missed, hasLength(1));
      expect(missed.first.missedCents, 1000);
    });

    test(
      'never blames the user for windows that closed before tracking began',
      () {
        final data = makeData(
          cards: [makeCard(createdAt: '2026-08-15T00:00:00.000Z')],
          benefits: [makeBenefit(Cadence.monthly, valueCents: 1500)],
        );
        // Only September is open and August started before the card was added.
        expect(missedCycles(data, today), isEmpty);
      },
    );

    test('ignores untracked credits, which have no window to miss', () {
      final data = makeData(
        cards: [makeCard(createdAt: '2026-01-01T00:00:00.000Z')],
        benefits: [makeBenefit(Cadence.manual)],
      );
      expect(missedCycles(data, today), isEmpty);
    });
  });

  group('biggestLeaks', () {
    test('groups a repeatedly missed credit into one line', () {
      final data = makeData(
        cards: [makeCard(createdAt: '2026-01-01T00:00:00.000Z')],
        benefits: [
          makeBenefit(Cadence.monthly, name: 'Uber Cash', valueCents: 1500),
        ],
      );
      final leaks = biggestLeaks(missedCycles(data, today));
      expect(leaks, hasLength(1));
      expect(leaks.first.label, 'Uber Cash × 8');
      expect(leaks.first.when, 'Jan 2026 – Aug 2026');
      expect(leaks.first.missedCents, 12000);
      expect(leaks.first.occurrences, 8);
    });

    test('ranks by money lost, worst first', () {
      final data = makeData(
        cards: [makeCard(createdAt: '2026-01-01T00:00:00.000Z')],
        benefits: [
          makeBenefit(
            Cadence.monthly,
            id: 'small',
            name: 'Uber Cash',
            valueCents: 1500,
          ),
          makeBenefit(
            Cadence.quarterly,
            id: 'big',
            name: 'Resy',
            valueCents: 10000,
          ),
        ],
      );
      final leaks = biggestLeaks(missedCycles(data, today));
      expect(leaks.map((l) => l.missedCents).toList(), [20000, 12000]);
    });
  });

  group('monthlyTotals', () {
    test(
      'bins claims by when they were logged and misses by when the window shut',
      () {
        final data = makeData(
          cards: [makeCard(createdAt: '2026-01-01T00:00:00.000Z')],
          benefits: [makeBenefit(Cadence.monthly, valueCents: 1500)],
          claims: [makeClaim(cycleKey: '2026-09-01', amountCents: 1500)],
        );
        final months = monthlyTotals(
          data,
          missedCycles(data, today),
          on: today,
          months: 9,
        );
        expect(months, hasLength(9));
        final last = months[months.length - 1];
        expect(last.label, 'Sep');
        expect(last.capturedCents, 1500);
        expect(last.missedCents, 0);
        final previous = months[months.length - 2];
        expect(previous.label, 'Aug');
        expect(previous.capturedCents, 0);
        expect(previous.missedCents, 1500);
      },
    );
  });

  group('summarizeCard', () {
    test(
      'reports net against the fee, and flags a card not paying for itself',
      () {
        final data = makeData(
          cards: [makeCard(annualFeeCents: 89500, anniversaryOn: '2020-01-01')],
          benefits: [makeBenefit(Cadence.monthly, valueCents: 10000)],
          claims: [makeClaim(amountCents: 10000)],
        );
        final summary = summarizeCard(
          data.cards.first,
          data,
          currentInstances(data, today),
          const [],
          today,
        );
        expect(summary.capturedCents, 10000);
        expect(summary.netCents, -79500);
        expect(summary.feeProgress, closeTo(0.1117, 0.0005));
      },
    );
  });

  group('cardLabel', () {
    test(
      'names the holder, because the household holds the same product twice',
      () {
        expect(
          cardLabel(makeCard(holder: 'Kathy')),
          'American Express Platinum — Kathy',
        );
      },
    );

    test('prefers a nickname when the user has set one', () {
      expect(cardLabel(makeCard(nickname: 'The travel one')), 'The travel one');
    });
  });
}
