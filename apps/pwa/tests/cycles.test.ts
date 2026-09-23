import { describe, expect, it } from 'vitest'
import {
  annualValueCents,
  closedCyclesBefore,
  cycleFor,
  cycleProgress,
  cyclesBetween,
  daysRemainingIn,
  nextCycle,
} from '../src/domain/cycles.ts'
import { addDays, daysBetween } from '../src/domain/dates.ts'
import type { Cycle } from '../src/domain/types.ts'
import { makeBenefit, makeCard } from './factories.ts'

/** Narrows a nullable cycle, failing loudly rather than silently skipping. */
function expectCycle(cycle: Cycle | null): Cycle {
  expect(cycle).not.toBeNull()
  return cycle as Cycle
}

describe('cycleFor — calendar anchored', () => {
  const card = makeCard()

  it('bounds a monthly cycle to the calendar month', () => {
    expect(cycleFor(makeBenefit('monthly'), card, '2026-09-16')).toEqual({
      key: '2026-09-01',
      start: '2026-09-01',
      end: '2026-09-30',
      label: 'Sep 2026',
    })
  })

  it('handles February in a leap year', () => {
    expect(cycleFor(makeBenefit('monthly'), card, '2024-02-10')?.end).toBe('2024-02-29')
  })

  it('puts quarters on Jan/Apr/Jul/Oct', () => {
    expect(cycleFor(makeBenefit('quarterly'), card, '2026-09-16')).toEqual({
      key: '2026-07-01',
      start: '2026-07-01',
      end: '2026-09-30',
      label: 'Q3 2026',
    })
    expect(cycleFor(makeBenefit('quarterly'), card, '2026-01-01')?.start).toBe('2026-01-01')
    expect(cycleFor(makeBenefit('quarterly'), card, '2026-12-31')?.start).toBe('2026-10-01')
  })

  it('splits semi-annual credits at Jan 1 and Jul 1', () => {
    expect(cycleFor(makeBenefit('semiannual'), card, '2026-06-30')).toEqual({
      key: '2026-01-01',
      start: '2026-01-01',
      end: '2026-06-30',
      label: 'H1 2026',
    })
    expect(cycleFor(makeBenefit('semiannual'), card, '2026-07-01')?.label).toBe('H2 2026')
  })

  it('bounds an annual credit to the calendar year', () => {
    expect(cycleFor(makeBenefit('annual'), card, '2026-09-16')).toEqual({
      key: '2026-01-01',
      start: '2026-01-01',
      end: '2026-12-31',
      label: '2026',
    })
  })

  it('resolves dates before the anchor year', () => {
    expect(cycleFor(makeBenefit('quarterly'), card, '2018-05-04')?.start).toBe('2018-04-01')
  })
})

describe('cycleFor — anniversary anchored', () => {
  const card = makeCard({ anniversaryOn: '2020-03-14' })
  const benefit = makeBenefit('annual', { anchor: 'anniversary' })

  it('runs a cardmember year from the account open date', () => {
    expect(cycleFor(benefit, card, '2026-09-16')).toMatchObject({
      start: '2026-03-14',
      end: '2027-03-13',
    })
  })

  it('places a date just before the anniversary in the prior year', () => {
    expect(cycleFor(benefit, card, '2026-03-13')).toMatchObject({
      start: '2025-03-14',
      end: '2026-03-13',
    })
  })

  it('starts the new cycle on the anniversary itself', () => {
    expect(cycleFor(benefit, card, '2026-03-14')?.start).toBe('2026-03-14')
  })

  it('does not drift for a 31st anniversary across short months', () => {
    // Month-clamping is the trap: Jan 31 + 1 month is Feb 28, so the step count
    // must be corrected by comparison rather than derived from a month count.
    const shortMonthCard = makeCard({ anniversaryOn: '2021-01-31' })
    const monthly = makeBenefit('monthly', { anchor: 'anniversary' })
    expect(cycleFor(monthly, shortMonthCard, '2026-02-27')).toMatchObject({
      start: '2026-01-31',
      end: '2026-02-27',
    })
    expect(cycleFor(monthly, shortMonthCard, '2026-02-28')).toMatchObject({
      start: '2026-02-28',
      end: '2026-03-30',
    })
  })

  it('produces windows with no gaps and no overlaps', () => {
    // The invariant that matters: every day belongs to exactly one cycle.
    const shortMonthCard = makeCard({ anniversaryOn: '2021-01-31' })
    const monthly = makeBenefit('monthly', { anchor: 'anniversary' })
    const cycles = cyclesBetween(monthly, shortMonthCard, '2026-01-01', '2027-01-01')
    expect(cycles.length).toBeGreaterThan(10)
    for (const [index, cycle] of cycles.entries()) {
      expect(daysBetween(cycle.start, cycle.end)).toBeGreaterThanOrEqual(26)
      const next = cycles[index + 1]
      if (next) expect(addDays(cycle.end, 1)).toBe(next.start)
    }
  })

  it('labels anniversary windows by date, since Q3 would be a lie', () => {
    expect(cycleFor(benefit, card, '2026-09-16')?.label).toBe('from Mar 14 2026')
  })
})

describe('manual benefits', () => {
  it('have no window and never recur', () => {
    const benefit = makeBenefit('manual')
    const card = makeCard()
    expect(cycleFor(benefit, card, '2026-09-16')).toBeNull()
    expect(cyclesBetween(benefit, card, '2026-01-01', '2027-01-01')).toEqual([])
  })
})

describe('cyclesBetween', () => {
  it('returns every monthly window overlapping the range', () => {
    const cycles = cyclesBetween(makeBenefit('monthly'), makeCard(), '2026-09-16', '2026-12-01')
    expect(cycles.map((c) => c.start)).toEqual([
      '2026-09-01',
      '2026-10-01',
      '2026-11-01',
      '2026-12-01',
    ])
  })

  it('is bounded by maxCycles', () => {
    const cycles = cyclesBetween(makeBenefit('monthly'), makeCard(), '2026-01-01', '2099-01-01', 5)
    expect(cycles).toHaveLength(5)
  })
})

describe('closedCyclesBefore', () => {
  it('walks backwards from the current window, newest first', () => {
    const cycles = closedCyclesBefore(makeBenefit('quarterly'), makeCard(), '2026-09-16', 3)
    expect(cycles.map((c) => c.label)).toEqual(['Q2 2026', 'Q1 2026', 'Q4 2025'])
  })

  it('never includes the open window', () => {
    const cycles = closedCyclesBefore(makeBenefit('monthly'), makeCard(), '2026-09-16', 5)
    expect(cycles.every((c) => c.end < '2026-09-16')).toBe(true)
  })
})

describe('nextCycle', () => {
  it('starts the day after the previous window closes', () => {
    const card = makeCard()
    const benefit = makeBenefit('monthly')
    const current = expectCycle(cycleFor(benefit, card, '2026-09-16'))
    expect(nextCycle(benefit, card, current)?.start).toBe('2026-10-01')
  })
})

describe('daysRemainingIn', () => {
  it('counts the final day as zero days remaining', () => {
    const cycle = expectCycle(cycleFor(makeBenefit('monthly'), makeCard(), '2026-09-16'))
    expect(daysRemainingIn(cycle, '2026-09-30')).toBe(0)
    expect(daysRemainingIn(cycle, '2026-09-16')).toBe(14)
    expect(daysRemainingIn(cycle, '2026-10-01')).toBe(-1)
  })
})

describe('cycleProgress', () => {
  it('runs from 0 at the start to 1 once the window has closed', () => {
    const cycle: Cycle = {
      key: '2026-09-01',
      start: '2026-09-01',
      end: '2026-09-30',
      label: 'Sep 2026',
    }
    expect(cycleProgress(cycle, '2026-09-01')).toBe(0)
    expect(cycleProgress(cycle, '2026-09-16')).toBeCloseTo(0.5, 1)
    expect(cycleProgress(cycle, '2026-10-05')).toBe(1)
  })
})

describe('annualValueCents', () => {
  it('scales each cadence to a yearly figure', () => {
    expect(annualValueCents(makeBenefit('monthly', { valueCents: 1500 }))).toBe(18_000)
    expect(annualValueCents(makeBenefit('quarterly', { valueCents: 5000 }))).toBe(20_000)
    expect(annualValueCents(makeBenefit('semiannual', { valueCents: 5000 }))).toBe(10_000)
    expect(annualValueCents(makeBenefit('annual', { valueCents: 30_000 }))).toBe(30_000)
  })

  it('counts an untracked credit once, not once per notional year', () => {
    // Global Entry is $120 every four years; calling it $120 a year would
    // overstate what the card is worth.
    expect(annualValueCents(makeBenefit('manual', { valueCents: 12_000 }))).toBe(12_000)
  })
})

describe('a credit that ends on a date', () => {
  const card = makeCard()
  const benefit = makeBenefit('monthly', { endsOn: '2026-09-20' })

  it('clamps the final window to endsOn', () => {
    expect(cycleFor(benefit, card, '2026-09-16')).toEqual({
      key: '2026-09-01',
      start: '2026-09-01',
      end: '2026-09-20',
      label: 'Sep 2026',
    })
  })

  it('has no window after endsOn, so nothing follows the final one', () => {
    expect(cycleFor(benefit, card, '2026-09-21')).toBeNull()
    const last = expectCycle(cycleFor(benefit, card, '2026-09-16'))
    expect(nextCycle(benefit, card, last)).toBeNull()
    expect(cyclesBetween(benefit, card, '2026-08-01', '2026-12-31').map((c) => c.end)).toEqual([
      '2026-08-31',
      '2026-09-20',
    ])
  })

  it('still lists the final window among the closed ones once it has passed', () => {
    expect(closedCyclesBefore(benefit, card, '2026-09-25', 2).map((c) => c.end)).toEqual([
      '2026-09-20',
      '2026-08-31',
    ])
  })

  it('does not prorate the annual value of a credit that ends mid-year', () => {
    expect(
      annualValueCents(makeBenefit('monthly', { valueCents: 1500, endsOn: '2026-09-20' })),
    ).toBe(18_000)
  })
})
