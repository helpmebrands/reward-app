import { describe, expect, it } from 'vitest'
import {
  biggestLeaks,
  cardLabel,
  currentInstances,
  findOverlaps,
  lockReason,
  missedCycles,
  monthlyTotals,
  nextReset,
  summarizeCard,
  totalsFor,
} from '../src/domain/selectors.ts'
import { makeBenefit, makeCard, makeClaim, makeData } from './factories.ts'

const TODAY = '2026-09-16'

describe('the status ladder', () => {
  it('calls a credit Use soon inside the 30-day horizon', () => {
    const data = makeData({ benefits: [makeBenefit('monthly')] })
    expect(currentInstances(data, TODAY)[0]?.status).toBe('use_soon')
  })

  it('calls a credit Available when it has more than a month of runway', () => {
    const data = makeData({ benefits: [makeBenefit('annual')] })
    expect(currentInstances(data, TODAY)[0]?.status).toBe('available')
  })

  it('calls a fully claimed credit Captured', () => {
    const data = makeData({
      benefits: [makeBenefit('monthly', { valueCents: 2500 })],
      claims: [makeClaim({ amountCents: 2500 })],
    })
    const instance = currentInstances(data, TODAY)[0]
    expect(instance?.status).toBe('captured')
    expect(instance?.remainingCents).toBe(0)
  })

  it('keeps a partly used credit open, with only the balance at stake', () => {
    const data = makeData({
      benefits: [makeBenefit('monthly', { valueCents: 2500 })],
      claims: [makeClaim({ amountCents: 1000 })],
    })
    const instance = currentInstances(data, TODAY)[0]
    expect(instance?.status).toBe('use_soon')
    expect(instance?.remainingCents).toBe(1500)
    expect(instance?.claimedCents).toBe(1000)
  })

  it('sums several partial claims within one cycle', () => {
    const data = makeData({
      benefits: [makeBenefit('monthly', { valueCents: 2500 })],
      claims: [
        makeClaim({ id: 'c1', amountCents: 1000 }),
        makeClaim({ id: 'c2', amountCents: 1500 }),
      ],
    })
    expect(currentInstances(data, TODAY)[0]?.status).toBe('captured')
  })

  it('calls an un-enrolled credit Locked rather than Use soon', () => {
    // The distinction the whole app rests on: this is not money the user is
    // failing to spend, it is money they cannot spend at all yet.
    const data = makeData({
      benefits: [makeBenefit('monthly', { enrollmentRequired: true })],
    })
    expect(currentInstances(data, TODAY)[0]?.status).toBe('locked')
  })

  it('unlocks once enrolment is confirmed', () => {
    const data = makeData({
      benefits: [
        makeBenefit('monthly', {
          enrollmentRequired: true,
          enrolledAt: '2026-09-01T00:00:00.000Z',
        }),
      ],
    })
    expect(currentInstances(data, TODAY)[0]?.status).toBe('use_soon')
  })

  it('calls an untracked credit Manual, never at risk', () => {
    const data = makeData({ benefits: [makeBenefit('manual')] })
    expect(currentInstances(data, TODAY)[0]?.status).toBe('manual')
  })

  it('counts a credit as Captured even while locked, if it was already used', () => {
    const data = makeData({
      benefits: [makeBenefit('monthly', { enrollmentRequired: true, valueCents: 2500 })],
      claims: [makeClaim({ amountCents: 2500 })],
    })
    expect(currentInstances(data, TODAY)[0]?.status).toBe('captured')
  })

  it('skips archived cards and inactive credits', () => {
    const data = makeData({
      cards: [makeCard({ archived: true })],
      benefits: [makeBenefit('monthly')],
    })
    expect(currentInstances(data, TODAY)).toHaveLength(0)
    expect(
      currentInstances(makeData({ benefits: [makeBenefit('monthly', { active: false })] }), TODAY),
    ).toHaveLength(0)
  })

  it('marks a credit muted when its card is muted', () => {
    const data = makeData({ cards: [makeCard({ muted: true })] })
    expect(currentInstances(data, TODAY)[0]?.muted).toBe(true)
  })
})

describe('ordering', () => {
  it('puts what closes soonest first, and locked below open', () => {
    const data = makeData({
      benefits: [
        makeBenefit('annual', { id: 'annual' }),
        makeBenefit('monthly', { id: 'locked', enrollmentRequired: true }),
        makeBenefit('monthly', { id: 'monthly' }),
      ],
    })
    expect(currentInstances(data, TODAY).map((i) => i.benefit.id)).toEqual([
      'monthly',
      'annual',
      'locked',
    ])
  })
})

describe('totals', () => {
  it('keeps claimable, locked, captured and missed apart', () => {
    const data = makeData({
      benefits: [
        makeBenefit('monthly', { id: 'open', valueCents: 1500 }),
        makeBenefit('monthly', { id: 'blocked', valueCents: 2500, enrollmentRequired: true }),
        makeBenefit('monthly', { id: 'done', valueCents: 1000 }),
      ],
      claims: [makeClaim({ benefitId: 'done', amountCents: 1000 })],
    })
    const totals = totalsFor(currentInstances(data, TODAY), 5000)
    expect(totals).toEqual({
      claimableCents: 1500,
      lockedCents: 2500,
      capturedCents: 1000,
      missedCents: 5000,
    })
  })
})

describe('nextReset', () => {
  it('reports the nearest window close among open credits', () => {
    const data = makeData({
      benefits: [makeBenefit('annual', { id: 'a' }), makeBenefit('monthly', { id: 'm' })],
    })
    expect(nextReset(currentInstances(data, TODAY))).toBe('2026-09-30')
  })

  it('is null when nothing is open', () => {
    expect(nextReset([])).toBeNull()
  })
})

describe('findOverlaps — the same credit held twice', () => {
  const jim = makeCard({ id: 'jim', holder: 'Jim' })
  const kathy = makeCard({ id: 'kathy', holder: 'Kathy' })

  it('flags one credit carried by two cards in the household', () => {
    const data = makeData({
      cards: [jim, kathy],
      benefits: [
        makeBenefit('quarterly', { id: 'b1', cardId: 'jim', name: 'Resy Dining Credit' }),
        makeBenefit('quarterly', { id: 'b2', cardId: 'kathy', name: 'Resy Dining Credit' }),
      ],
    })
    const overlaps = findOverlaps(currentInstances(data, TODAY))
    expect(overlaps).toHaveLength(1)
    expect(overlaps[0]?.label).toBe('Resy Dining Credit')
    expect(overlaps[0]?.sameProduct).toBe(true)
    expect(overlaps[0]?.instances.map((i) => i.card.holder)).toEqual(['Jim', 'Kathy'])
  })

  it('matches across issuers by merchant, not by name', () => {
    const data = makeData({
      cards: [jim, makeCard({ id: 'chase', holder: 'Kathy', issuer: 'Chase', product: 'Reserve' })],
      benefits: [
        makeBenefit('monthly', { id: 'b1', cardId: 'jim', name: 'Uber Cash', merchant: 'Uber' }),
        makeBenefit('monthly', {
          id: 'b2',
          cardId: 'chase',
          name: 'Rideshare Credit',
          merchant: 'Uber',
        }),
      ],
    })
    const overlaps = findOverlaps(currentInstances(data, TODAY))
    expect(overlaps).toHaveLength(1)
    expect(overlaps[0]?.sameProduct).toBe(false)
  })

  it('does not flag two credits that merely sit on the same card', () => {
    const data = makeData({
      benefits: [
        makeBenefit('monthly', { id: 'b1', name: 'Uber Cash', merchant: 'Uber' }),
        makeBenefit('annual', { id: 'b2', name: 'Uber One', merchant: 'Uber' }),
      ],
    })
    expect(findOverlaps(currentInstances(data, TODAY))).toHaveLength(0)
  })

  it('totals what is still unclaimed across the pair', () => {
    const data = makeData({
      cards: [jim, kathy],
      benefits: [
        makeBenefit('quarterly', { id: 'b1', cardId: 'jim', valueCents: 10_000 }),
        makeBenefit('quarterly', { id: 'b2', cardId: 'kathy', valueCents: 10_000 }),
      ],
      claims: [makeClaim({ benefitId: 'b1', cycleKey: '2026-07-01', amountCents: 4000 })],
    })
    expect(findOverlaps(currentInstances(data, TODAY))[0]?.remainingCents).toBe(16_000)
  })
})

describe('missedCycles', () => {
  it('counts a closed window with nothing claimed against it', () => {
    const data = makeData({
      cards: [makeCard({ createdAt: '2026-01-01T00:00:00.000Z' })],
      benefits: [makeBenefit('monthly', { valueCents: 1500 })],
    })
    const missed = missedCycles(data, TODAY)
    expect(missed).toHaveLength(8) // January through August
    expect(missed[0]?.cycle.label).toBe('Aug 2026')
    expect(missed.reduce((sum, m) => sum + m.missedCents, 0)).toBe(12_000)
  })

  it('counts only the shortfall when a window was partly used', () => {
    const data = makeData({
      cards: [makeCard({ createdAt: '2026-08-01T00:00:00.000Z' })],
      benefits: [makeBenefit('monthly', { valueCents: 1500 })],
      claims: [makeClaim({ cycleKey: '2026-08-01', amountCents: 500 })],
    })
    expect(missedCycles(data, TODAY)).toEqual([expect.objectContaining({ missedCents: 1000 })])
  })

  it('never blames the user for windows that closed before tracking began', () => {
    const data = makeData({
      cards: [makeCard({ createdAt: '2026-08-15T00:00:00.000Z' })],
      benefits: [makeBenefit('monthly', { valueCents: 1500 })],
    })
    // Only September is open and August started before the card was added.
    expect(missedCycles(data, TODAY)).toHaveLength(0)
  })

  it('ignores untracked credits, which have no window to miss', () => {
    const data = makeData({
      cards: [makeCard({ createdAt: '2026-01-01T00:00:00.000Z' })],
      benefits: [makeBenefit('manual')],
    })
    expect(missedCycles(data, TODAY)).toHaveLength(0)
  })
})

describe('biggestLeaks', () => {
  it('groups a repeatedly missed credit into one line', () => {
    const data = makeData({
      cards: [makeCard({ createdAt: '2026-01-01T00:00:00.000Z' })],
      benefits: [makeBenefit('monthly', { name: 'Uber Cash', valueCents: 1500 })],
    })
    const leaks = biggestLeaks(missedCycles(data, TODAY))
    expect(leaks).toHaveLength(1)
    expect(leaks[0]).toMatchObject({
      label: 'Uber Cash × 8',
      when: 'Jan 2026 – Aug 2026',
      missedCents: 12_000,
      occurrences: 8,
    })
  })

  it('ranks by money lost, worst first', () => {
    const data = makeData({
      cards: [makeCard({ createdAt: '2026-01-01T00:00:00.000Z' })],
      benefits: [
        makeBenefit('monthly', { id: 'small', name: 'Uber Cash', valueCents: 1500 }),
        makeBenefit('quarterly', { id: 'big', name: 'Resy', valueCents: 10_000 }),
      ],
    })
    const leaks = biggestLeaks(missedCycles(data, TODAY))
    expect(leaks.map((l) => l.missedCents)).toEqual([20_000, 12_000])
  })
})

describe('monthlyTotals', () => {
  it('bins claims by when they were logged and misses by when the window shut', () => {
    const data = makeData({
      cards: [makeCard({ createdAt: '2026-01-01T00:00:00.000Z' })],
      benefits: [makeBenefit('monthly', { valueCents: 1500 })],
      claims: [makeClaim({ cycleKey: '2026-09-01', amountCents: 1500 })],
    })
    const months = monthlyTotals(data, missedCycles(data, TODAY), TODAY, 9)
    expect(months).toHaveLength(9)
    expect(months.at(-1)).toMatchObject({ label: 'Sep', capturedCents: 1500, missedCents: 0 })
    expect(months.at(-2)).toMatchObject({ label: 'Aug', capturedCents: 0, missedCents: 1500 })
  })
})

describe('summarizeCard', () => {
  it('reports net against the fee, and flags a card not paying for itself', () => {
    const data = makeData({
      cards: [makeCard({ annualFeeCents: 89_500, anniversaryOn: '2020-01-01' })],
      benefits: [makeBenefit('monthly', { valueCents: 10_000 })],
      claims: [makeClaim({ amountCents: 10_000 })],
    })
    const summary = summarizeCard(
      data.cards[0] as NonNullable<(typeof data.cards)[0]>,
      data,
      currentInstances(data, TODAY),
      [],
      TODAY,
    )
    expect(summary.capturedCents).toBe(10_000)
    expect(summary.netCents).toBe(-79_500)
    expect(summary.feeProgress).toBeCloseTo(0.1117, 3)
  })
})

describe('cardLabel', () => {
  it('names the holder, because the household holds the same product twice', () => {
    expect(cardLabel(makeCard({ holder: 'Kathy' }))).toBe('American Express Platinum — Kathy')
  })

  it('prefers a nickname when the user has set one', () => {
    expect(cardLabel(makeCard({ nickname: 'The travel one' }))).toBe('The travel one')
  })
})

describe('a credit that ends on a date', () => {
  it('fires Use soon against the clamped end', () => {
    const data = makeData({ benefits: [makeBenefit('annual', { endsOn: '2026-09-30' })] })
    const instance = currentInstances(data, TODAY)[0]
    expect(instance?.status).toBe('use_soon')
    expect(instance?.cycle.end).toBe('2026-09-30')
    expect(instance?.daysRemaining).toBe(14)
  })

  it('is absent the day after it ends', () => {
    const data = makeData({ benefits: [makeBenefit('monthly', { endsOn: '2026-09-20' })] })
    expect(currentInstances(data, '2026-09-20')).toHaveLength(1)
    expect(currentInstances(data, '2026-09-21')).toHaveLength(0)
  })

  it("reports the final window's shortfall in the missed ledger", () => {
    const data = makeData({
      cards: [makeCard({ createdAt: '2026-08-01T00:00:00.000Z' })],
      benefits: [makeBenefit('monthly', { endsOn: '2026-09-20' })],
    })
    const missed = missedCycles(data, '2026-09-25')
    expect(missed.map((m) => m.cycle.end)).toEqual(['2026-09-20', '2026-08-31'])
    expect(missed[0]?.missedCents).toBe(2500)
  })
})

describe('a rolling credit', () => {
  const card = makeCard({ createdAt: '2026-01-01T00:00:00.000Z' })
  const benefit = makeBenefit('rolling', { valueCents: 12_000, intervalMonths: 48 })
  const claimed = makeClaim({
    cycleKey: '2026-01-01',
    amountCents: 12_000,
    claimedAt: '2026-09-16T12:00:00.000Z',
  })

  it('is Available with no deadline until claimed, then Captured until the interval ends', () => {
    const open = currentInstances(makeData({ cards: [card], benefits: [benefit] }), TODAY)[0]
    expect(open?.status).toBe('available')
    expect(open?.cycle.label).toBe('Eligible now')

    const data = makeData({ cards: [card], benefits: [benefit], claims: [claimed] })
    expect(currentInstances(data, TODAY)[0]?.status).toBe('captured')
    expect(currentInstances(data, '2030-09-15')[0]?.status).toBe('captured')
    const again = currentInstances(data, '2030-09-16')[0]
    expect(again?.status).toBe('available')
    expect(again?.cycle.key).toBe('2030-09-16')
  })

  it('is never Use soon and never missed', () => {
    const partial = { ...claimed, amountCents: 5000 }
    const data = makeData({ cards: [card], benefits: [benefit], claims: [partial] })
    // A fortnight before the closed window ends, with money left in it.
    expect(currentInstances(data, '2030-09-01')[0]?.status).toBe('available')
    expect(missedCycles(data, '2031-01-01')).toHaveLength(0)
  })

  it('is worth its amortised value on the card', () => {
    const data = makeData({ cards: [card], benefits: [benefit] })
    expect(summarizeCard(card, data, currentInstances(data, TODAY), [], TODAY).annualValueCents).toBe(
      3000,
    )
  })
})

describe('a spend-gated credit', () => {
  const card = makeCard()

  it('is Locked, for spend, until the threshold is met', () => {
    const benefit = makeBenefit('annual', { spendThresholdCents: 25_000_000 })
    expect(currentInstances(makeData({ benefits: [benefit] }), TODAY)[0]?.status).toBe('locked')
    expect(lockReason(benefit, card, TODAY)).toBe('spend')
  })

  it('names enrolment first when both apply', () => {
    const benefit = makeBenefit('annual', { enrollmentRequired: true, spendThresholdCents: 100 })
    expect(lockReason(benefit, card, TODAY)).toBe('enrollment')
  })

  it('unlocks with a spend met inside the current calendar year, not the previous one', () => {
    const met = (spendMetAt: string) =>
      makeBenefit('annual', { spendThresholdCents: 100, spendMetAt })
    const statusOf = (spendMetAt: string) =>
      currentInstances(makeData({ benefits: [met(spendMetAt)] }), TODAY)[0]?.status
    expect(statusOf('2026-03-01T00:00:00.000Z')).toBe('available')
    expect(statusOf('2025-12-31T00:00:00.000Z')).toBe('locked')
  })

  it('measures the year from the anniversary when the credit is anchored there', () => {
    // The card's year turns over on 14 March, so February is last year.
    const met = (spendMetAt: string) =>
      makeBenefit('annual', { anchor: 'anniversary', spendThresholdCents: 100, spendMetAt })
    expect(lockReason(met('2026-02-01T00:00:00.000Z'), card, TODAY)).toBe('spend')
    expect(lockReason(met('2026-04-01T00:00:00.000Z'), card, TODAY)).toBeNull()
  })

  it("contributes nothing to the card's annual value while gated", () => {
    const gated = makeBenefit('annual', {
      id: 'gated',
      valueCents: 120_000,
      spendThresholdCents: 100,
    })
    const open = makeBenefit('monthly', { id: 'open', valueCents: 1500 })
    const annual = (benefits: (typeof gated)[]) => {
      const data = makeData({ benefits })
      return summarizeCard(card, data, currentInstances(data, TODAY), [], TODAY).annualValueCents
    }
    expect(annual([gated, open])).toBe(18_000)
    expect(annual([{ ...gated, spendMetAt: '2026-03-01T00:00:00.000Z' }, open])).toBe(138_000)
  })
})
