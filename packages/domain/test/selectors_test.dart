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

    test('marks a credit muted when the member muted its card', () {
      final prefs = defaultMemberPreferences.copyWith(mutedCardIds: {'card-1'});
      expect(currentInstances(makeData(), today, prefs).first.muted, isTrue);
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
    final jim = makeCard(id: 'jim', label: 'Jim’s Platinum');
    final kathy = makeCard(id: 'kathy', label: 'Kathy’s Platinum');

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
      expect(overlaps.first.instances.map((i) => cardLabel(i.card)).toList(), [
        'Jim’s Platinum',
        'Kathy’s Platinum',
      ]);
    });

    test('matches across issuers by merchant, not by name', () {
      final data = makeData(
        cards: [
          jim,
          makeCard(id: 'chase', issuer: 'Chase', product: 'Reserve'),
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

  // @lat: [[tests#Member preferences#Mutes come from the member, not the household]]
  test('an instance is muted by the member’s card or benefit mute', () {
    final data = makeData(
      benefits: [
        makeBenefit(Cadence.monthly, id: 'x'),
        makeBenefit(Cadence.monthly, id: 'y'),
      ],
    );
    bool mutedFor(MemberPreferences? prefs, String id) => currentInstances(
      data,
      today,
      prefs,
    ).firstWhere((i) => i.benefit.id == id).muted;
    expect(mutedFor(null, 'x'), isFalse);
    final benefitMute = defaultMemberPreferences.copyWith(
      mutedBenefitIds: {'x'},
    );
    expect(mutedFor(benefitMute, 'x'), isTrue);
    expect(mutedFor(benefitMute, 'y'), isFalse);
    final cardMute = defaultMemberPreferences.copyWith(
      mutedCardIds: {'card-1'},
    );
    expect(mutedFor(cardMute, 'y'), isTrue);
  });

  group('display names', () {
    // @lat: [[tests#Card labels#A card shows its label or its product name]]
    test(
      'a card without a label shows its product name, one with a label shows the label',
      () {
        expect(cardLabel(makeCard()), 'American Express Platinum');
        expect(cardLabel(makeCard(label: 'The travel one')), 'The travel one');
        expect(cardLabel(makeCard(label: '')), 'American Express Platinum');
      },
    );

    // @lat: [[tests#Card labels#A duplicate product proposes a numbered label]]
    test('the second card of a product proposes (1), the third (2)', () {
      final first = makeCard(id: 'a');
      expect(defaultLabel([], 'American Express', 'Platinum'), isNull);
      expect(
        defaultLabel([first], 'American Express', 'Platinum'),
        'American Express Platinum (1)',
      );
      final second = makeCard(id: 'b', label: 'American Express Platinum (1)');
      expect(
        defaultLabel([first, second], 'American Express', 'Platinum'),
        'American Express Platinum (2)',
      );
      expect(
        defaultLabel([first, second], 'Chase', 'Sapphire Reserve'),
        isNull,
      );
    });

    // @lat: [[tests#Card labels#Deleting a card renames nothing]]
    test(
      'deleting the first of three identical cards leaves the other labels',
      () {
        final cards = [
          makeCard(id: 'a'),
          makeCard(id: 'b', label: 'American Express Platinum (1)'),
          makeCard(id: 'c', label: 'American Express Platinum (2)'),
        ];
        final remaining = cards.skip(1).toList();
        expect(remaining.map(cardLabel).toList(), [
          'American Express Platinum (1)',
          'American Express Platinum (2)',
        ]);
        // The product name is free again, so a fourth card needs no number.
        expect(defaultLabel(remaining, 'American Express', 'Platinum'), isNull);
      },
    );

    // @lat: [[tests#Card labels#A label may not repeat another card's display name]]
    test('refuses a label that is another card’s display name', () {
      final cards = [makeCard(id: 'a'), makeCard(id: 'b', label: 'Travel')];
      expect(
        labelError(
          'Travel',
          cards: cards,
          issuer: 'American Express',
          product: 'Platinum',
          cardId: 'a',
        ),
        contains('Travel'),
      );
      expect(
        labelError(
          'american express platinum ',
          cards: cards,
          issuer: 'American Express',
          product: 'Platinum',
          cardId: 'b',
        ),
        isNotNull,
      );
      // Its own name, a fresh name, and a blank label on a free product pass.
      expect(
        labelError(
          'Travel',
          cards: cards,
          issuer: 'American Express',
          product: 'Platinum',
          cardId: 'b',
        ),
        isNull,
      );
      expect(
        labelError(
          'Everyday',
          cards: cards,
          issuer: 'American Express',
          product: 'Platinum',
        ),
        isNull,
      );
      expect(
        labelError(
          '',
          cards: cards,
          issuer: 'Chase',
          product: 'Sapphire Reserve',
        ),
        isNull,
      );
      // A blank label on a product another card already shows is a collision.
      expect(
        labelError(
          '',
          cards: cards,
          issuer: 'American Express',
          product: 'Platinum',
        ),
        isNotNull,
      );
    });
  });

  group('a credit that ends on a date', () {
    test('fires Use soon against the clamped end', () {
      final data = makeData(
        benefits: [makeBenefit(Cadence.annual, endsOn: '2026-09-30')],
      );
      final instance = currentInstances(data, today).first;
      expect(instance.status, BenefitStatus.useSoon);
      expect(instance.cycle.end, '2026-09-30');
      expect(instance.daysRemaining, 14);
    });

    test('is absent the day after it ends', () {
      final data = makeData(
        benefits: [makeBenefit(Cadence.monthly, endsOn: '2026-09-20')],
      );
      expect(currentInstances(data, '2026-09-20'), hasLength(1));
      expect(currentInstances(data, '2026-09-21'), isEmpty);
    });

    test("reports the final window's shortfall in the missed ledger", () {
      final data = makeData(
        cards: [makeCard(createdAt: '2026-08-01T00:00:00.000Z')],
        benefits: [makeBenefit(Cadence.monthly, endsOn: '2026-09-20')],
      );
      final missed = missedCycles(data, '2026-09-25');
      expect(missed.map((m) => m.cycle.end), ['2026-09-20', '2026-08-31']);
      expect(missed.first.missedCents, 2500);
    });
  });

  group('a rolling credit', () {
    final card = makeCard(createdAt: '2026-01-01T00:00:00.000Z');
    final benefit = makeBenefit(
      Cadence.rolling,
      valueCents: 12000,
      intervalMonths: 48,
    );
    final claimed = makeClaim(
      cycleKey: '2026-01-01',
      amountCents: 12000,
      claimedAt: '2026-09-16T12:00:00.000Z',
    );

    test(
      'is Available with no deadline until claimed, then Captured until the interval ends',
      () {
        final open = currentInstances(
          makeData(cards: [card], benefits: [benefit]),
          today,
        ).first;
        expect(open.status, BenefitStatus.available);
        expect(open.cycle.label, 'Eligible now');

        final data = makeData(
          cards: [card],
          benefits: [benefit],
          claims: [claimed],
        );
        expect(
          currentInstances(data, today).first.status,
          BenefitStatus.captured,
        );
        expect(
          currentInstances(data, '2030-09-15').first.status,
          BenefitStatus.captured,
        );
        final again = currentInstances(data, '2030-09-16').first;
        expect(again.status, BenefitStatus.available);
        expect(again.cycle.key, '2030-09-16');
      },
    );

    test('is never Use soon and never missed', () {
      final partial = makeClaim(
        cycleKey: '2026-01-01',
        amountCents: 5000,
        claimedAt: '2026-09-16T12:00:00.000Z',
      );
      final data = makeData(
        cards: [card],
        benefits: [benefit],
        claims: [partial],
      );
      // A fortnight before the closed window ends, with money left in it.
      expect(
        currentInstances(data, '2030-09-01').first.status,
        BenefitStatus.available,
      );
      expect(missedCycles(data, '2031-01-01'), isEmpty);
    });

    test('is worth its amortised value on the card', () {
      final data = makeData(cards: [card], benefits: [benefit]);
      expect(
        summarizeCard(
          card,
          data,
          currentInstances(data, today),
          const [],
          today,
        ).annualValueCents,
        3000,
      );
    });
  });

  group('a spend-gated credit', () {
    final card = makeCard();

    test('is Locked, for spend, until the threshold is met', () {
      final benefit = makeBenefit(
        Cadence.annual,
        spendThresholdCents: 25000000,
      );
      expect(
        currentInstances(makeData(benefits: [benefit]), today).first.status,
        BenefitStatus.locked,
      );
      expect(lockReason(benefit, card, today), LockReason.spend);
    });

    test('names enrolment first when both apply', () {
      final benefit = makeBenefit(
        Cadence.annual,
        enrollmentRequired: true,
        spendThresholdCents: 100,
      );
      expect(lockReason(benefit, card, today), LockReason.enrollment);
    });

    test(
      'unlocks with a spend met inside the current calendar year, not the previous one',
      () {
        BenefitStatus statusOf(String spendMetAt) => currentInstances(
          makeData(
            benefits: [
              makeBenefit(
                Cadence.annual,
                spendThresholdCents: 100,
                spendMetAt: spendMetAt,
              ),
            ],
          ),
          today,
        ).first.status;
        expect(statusOf('2026-03-01T00:00:00.000Z'), BenefitStatus.available);
        expect(statusOf('2025-12-31T00:00:00.000Z'), BenefitStatus.locked);
      },
    );

    test(
      'measures the year from the anniversary when the credit is anchored there',
      () {
        // The card's year turns over on 14 March, so February is last year.
        Benefit met(String spendMetAt) => makeBenefit(
          Cadence.annual,
          anchor: CycleAnchor.anniversary,
          spendThresholdCents: 100,
          spendMetAt: spendMetAt,
        );
        expect(
          lockReason(met('2026-02-01T00:00:00.000Z'), card, today),
          LockReason.spend,
        );
        expect(
          lockReason(met('2026-04-01T00:00:00.000Z'), card, today),
          isNull,
        );
      },
    );

    test("contributes nothing to the card's annual value while gated", () {
      final gated = makeBenefit(
        Cadence.annual,
        id: 'gated',
        valueCents: 120000,
        spendThresholdCents: 100,
      );
      final open = makeBenefit(Cadence.monthly, id: 'open', valueCents: 1500);
      int annual(List<Benefit> benefits) {
        final data = makeData(benefits: benefits);
        return summarizeCard(
          card,
          data,
          currentInstances(data, today),
          const [],
          today,
        ).annualValueCents;
      }

      expect(annual([gated, open]), 18000);
      expect(
        annual([gated.copyWith(spendMetAt: '2026-03-01T00:00:00.000Z'), open]),
        138000,
      );
    });
  });
}
