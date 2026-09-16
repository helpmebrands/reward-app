import { addDays, addMonths, compareIsoDate, daysBetween, isWithin, parseIsoDate } from './dates.ts'
import type { Benefit, Cadence, Card, Cycle, IsoDate } from './types.ts'

/** How many months one cycle of each cadence spans. `manual` never recurs. */
const MONTHS_PER_CYCLE: Record<Exclude<Cadence, 'manual'>, number> = {
  monthly: 1,
  quarterly: 3,
  semiannual: 6,
  annual: 12,
}

export function monthsPerCycle(cadence: Cadence): number | null {
  return cadence === 'manual' ? null : MONTHS_PER_CYCLE[cadence]
}

/**
 * The date every cycle of a benefit is measured from.
 *
 * Calendar cycles anchor to January 1st, which puts quarters on Jan/Apr/Jul/Oct
 * and halves on Jan/Jul — the windows issuers actually use. Anniversary cycles
 * anchor to the day the account was opened.
 */
export function anchorDateFor(benefit: Benefit, card: Card): IsoDate {
  if (benefit.anchor === 'anniversary') return card.anniversaryOn
  const { year } = parseIsoDate(card.anniversaryOn)
  // Any January 1st serves as the origin; using the account's own year keeps
  // the arithmetic close to the dates involved.
  return `${String(year).padStart(4, '0')}-01-01`
}

const MONTH_NAMES = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
]

/**
 * The period label the screens show — "Sep 2026", "Q3 2026", "H2 2026", "2026".
 *
 * Calendar-anchored windows get the familiar issuer shorthand. Anniversary
 * windows cannot use it (a cardmember quarter is not Q3), so they are labelled
 * by their start date instead.
 */
export function cycleLabel(benefit: Benefit, start: IsoDate): string {
  const { year, month, day } = parseIsoDate(start)
  if (benefit.anchor === 'anniversary') {
    return `from ${MONTH_NAMES[month - 1]} ${day} ${year}`
  }
  switch (benefit.cadence) {
    case 'monthly':
      return `${MONTH_NAMES[month - 1]} ${year}`
    case 'quarterly':
      return `Q${Math.floor((month - 1) / 3) + 1} ${year}`
    case 'semiannual':
      return `H${month <= 6 ? 1 : 2} ${year}`
    case 'annual':
      return `${year}`
    case 'manual':
      return 'Untracked'
  }
}

/**
 * The cycle containing `on`, for a recurring benefit. `manual` benefits have no
 * window and return `null`.
 *
 * Walks from the anchor in whole cycle-lengths. Month arithmetic clamps
 * (Jan 31 + 1 month is Feb 28), so the step count is corrected by comparison
 * rather than derived from a month difference — clamping makes the naive
 * `(years * 12 + months)` formula land in the wrong window at month ends.
 */
export function cycleFor(benefit: Benefit, card: Card, on: IsoDate): Cycle | null {
  if (benefit.cadence === 'manual') return null

  const span = MONTHS_PER_CYCLE[benefit.cadence]
  const anchor = anchorDateFor(benefit, card)

  const monthsApart =
    (parseIsoDate(on).year - parseIsoDate(anchor).year) * 12 +
    (parseIsoDate(on).month - parseIsoDate(anchor).month)
  let steps = Math.floor(monthsApart / span)

  // At most one correction in either direction is ever needed; the loops are
  // bounded defensively rather than trusted to terminate on their own.
  for (
    let guard = 0;
    guard < 4 && compareIsoDate(addMonths(anchor, steps * span), on) > 0;
    guard++
  ) {
    steps--
  }
  for (
    let guard = 0;
    guard < 4 && compareIsoDate(addMonths(anchor, (steps + 1) * span), on) <= 0;
    guard++
  ) {
    steps++
  }

  const start = addMonths(anchor, steps * span)
  const end = addDays(addMonths(anchor, (steps + 1) * span), -1)
  return { key: start, start, end, label: cycleLabel(benefit, start) }
}

/** The cycle that follows `cycle`, or `null` for untracked benefits. */
export function nextCycle(benefit: Benefit, card: Card, cycle: Cycle): Cycle | null {
  if (benefit.cadence === 'manual') return null
  return cycleFor(benefit, card, addDays(cycle.end, 1))
}

/** The cycle before `cycle`. */
export function previousCycle(benefit: Benefit, card: Card, cycle: Cycle): Cycle | null {
  if (benefit.cadence === 'manual') return null
  return cycleFor(benefit, card, addDays(cycle.start, -1))
}

/**
 * Every cycle overlapping `[from, to]`, oldest first. Used by the period
 * history and by reminder scheduling, which looks past the current window.
 */
export function cyclesBetween(
  benefit: Benefit,
  card: Card,
  from: IsoDate,
  to: IsoDate,
  maxCycles = 64,
): Cycle[] {
  const cycles: Cycle[] = []
  let cycle = cycleFor(benefit, card, from)
  while (cycle && cycles.length < maxCycles && compareIsoDate(cycle.start, to) <= 0) {
    cycles.push(cycle)
    cycle = nextCycle(benefit, card, cycle)
  }
  return cycles
}

/**
 * The closed cycles preceding the one containing `on`, newest first. This is
 * what the Missed ledger and the period-history sheet are built from.
 */
export function closedCyclesBefore(
  benefit: Benefit,
  card: Card,
  on: IsoDate,
  count: number,
): Cycle[] {
  const current = cycleFor(benefit, card, on)
  if (!current) return []
  const cycles: Cycle[] = []
  let cycle = previousCycle(benefit, card, current)
  while (cycle && cycles.length < count) {
    cycles.push(cycle)
    cycle = previousCycle(benefit, card, cycle)
  }
  return cycles
}

/** True when `on` falls inside the cycle window. */
export function isCycleOpen(cycle: Cycle, on: IsoDate): boolean {
  return isWithin(on, cycle.start, cycle.end)
}

/** Whole days from `on` until the cycle closes. 0 means it closes today. */
export function daysRemainingIn(cycle: Cycle, on: IsoDate): number {
  return daysBetween(on, cycle.end)
}

/** How far through its window a cycle is, clamped to 0..1. */
export function cycleProgress(cycle: Cycle, on: IsoDate): number {
  const total = daysBetween(cycle.start, cycle.end) + 1
  if (total <= 0) return 1
  return Math.min(1, Math.max(0, daysBetween(cycle.start, on) / total))
}

const CADENCE_LABELS: Record<Cadence, string> = {
  monthly: 'Monthly',
  quarterly: 'Quarterly',
  semiannual: 'Semi-annual',
  annual: 'Annual',
  manual: 'Manual',
}

export function cadenceLabel(cadence: Cadence): string {
  return CADENCE_LABELS[cadence]
}

/**
 * Value released per year. Untracked credits are counted once: a Global Entry
 * fee every four years is not worth a quarter of itself on the Cards screen.
 */
export function annualValueCents(benefit: Benefit): number {
  const span = monthsPerCycle(benefit.cadence)
  if (span === null) return benefit.valueCents
  return benefit.valueCents * (12 / span)
}
