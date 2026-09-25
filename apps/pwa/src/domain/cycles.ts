import { addDays, addMonths, compareIsoDate, daysBetween, isWithin, parseIsoDate } from './dates.ts'
import type { Benefit, Cadence, Card, Claim, Cycle, IsoDate } from './types.ts'

/**
 * How many months one cycle of each calendar cadence spans. `manual` never
 * recurs and `rolling` takes its span from the benefit.
 */
const MONTHS_PER_CYCLE: Record<Exclude<Cadence, 'manual' | 'rolling'>, number> = {
  monthly: 1,
  quarterly: 3,
  semiannual: 6,
  annual: 12,
}

export function monthsPerCycle(cadence: Cadence): number | null {
  return cadence === 'manual' || cadence === 'rolling' ? null : MONTHS_PER_CYCLE[cadence]
}

/** The end of a window that only a claim can close. */
const OPEN_ENDED: IsoDate = '2999-12-31'

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
    case 'rolling':
      return 'Eligible now'
    case 'manual':
      return 'Untracked'
  }
}

/**
 * A rolling credit's window comes from the claim ledger, not the calendar.
 *
 * The open window is keyed by the day the card was added, or the day after
 * the last closed window. The first claim recorded under that key closes it
 * to `[claim day, claim day + intervalMonths − 1]`, and a new open window
 * keys from the day after. Keys never move, so a claim always finds its
 * window and the app never offers a credit the issuer would refuse.
 */
function rollingCycleFor(benefit: Benefit, card: Card, on: IsoDate, claims: Claim[]): Cycle {
  const interval = benefit.intervalMonths ?? 0
  let key = card.createdAt.slice(0, 10)
  const mine = claims
    .filter((claim) => claim.benefitId === benefit.id)
    .sort((a, b) => a.claimedAt.localeCompare(b.claimedAt))
  for (const claim of mine) {
    if (claim.cycleKey !== key || interval <= 0) continue
    const start = claim.claimedAt.slice(0, 10)
    const end = addDays(addMonths(start, interval), -1)
    if (compareIsoDate(on, end) <= 0) {
      const { year, month } = parseIsoDate(end)
      return { key, start, end, label: `until ${MONTH_NAMES[month - 1]} ${year}` }
    }
    key = addDays(end, 1)
  }
  return { key, start: key, end: OPEN_ENDED, label: 'Eligible now' }
}

/**
 * The cycle containing `on`, for a recurring benefit. `manual` benefits have no
 * window and return `null`; `rolling` ones read their window from `claims`.
 *
 * Walks from the anchor in whole cycle-lengths. Month arithmetic clamps
 * (Jan 31 + 1 month is Feb 28), so the step count is corrected by comparison
 * rather than derived from a month difference — clamping makes the naive
 * `(years * 12 + months)` formula land in the wrong window at month ends.
 */
export function cycleFor(
  benefit: Benefit,
  card: Card,
  on: IsoDate,
  claims: Claim[] = [],
): Cycle | null {
  if (benefit.cadence === 'manual') return null
  if (hasEnded(benefit, on)) return null
  if (benefit.cadence === 'rolling') return rollingCycleFor(benefit, card, on, claims)

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
  const natural = addDays(addMonths(anchor, (steps + 1) * span), -1)
  // The final window of a credit that ends on a date closes on that date.
  const end =
    benefit.endsOn && compareIsoDate(benefit.endsOn, natural) < 0 ? benefit.endsOn : natural
  return { key: start, start, end, label: cycleLabel(benefit, start) }
}

/** True once `on` is past the credit's `endsOn`; never for an open-ended credit. */
export function hasEnded(benefit: Benefit, on: IsoDate): boolean {
  return benefit.endsOn !== undefined && compareIsoDate(on, benefit.endsOn) > 0
}

/**
 * The cycle that follows `cycle`, or `null` for untracked benefits and for
 * rolling ones, whose next window exists only once a claim opens it.
 */
export function nextCycle(benefit: Benefit, card: Card, cycle: Cycle): Cycle | null {
  if (benefit.cadence === 'manual' || benefit.cadence === 'rolling') return null
  return cycleFor(benefit, card, addDays(cycle.end, 1))
}

/** The cycle before `cycle`. */
export function previousCycle(benefit: Benefit, card: Card, cycle: Cycle): Cycle | null {
  if (benefit.cadence === 'manual' || benefit.cadence === 'rolling') return null
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
  const cycles: Cycle[] = []
  // Once a credit has ended, its final window is itself a closed one.
  let cycle = current
    ? previousCycle(benefit, card, current)
    : benefit.endsOn && hasEnded(benefit, on)
      ? cycleFor(benefit, card, benefit.endsOn)
      : null
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
  rolling: 'Rolling',
  manual: 'Manual',
}

export function cadenceLabel(cadence: Cadence): string {
  return CADENCE_LABELS[cadence]
}

/**
 * Value released per year for a cadence. A rolling credit is amortised over
 * its interval: $120 every 48 months is $30 a year. Untracked credits are
 * counted once, since nothing says when they recur.
 */
export function annualValueOf(
  valueCents: number,
  cadence: Cadence,
  intervalMonths?: number,
): number {
  if (cadence === 'rolling') {
    return intervalMonths && intervalMonths > 0
      ? Math.round((valueCents * 12) / intervalMonths)
      : valueCents
  }
  const span = monthsPerCycle(cadence)
  if (span === null) return valueCents
  return valueCents * (12 / span)
}

/** Value a benefit releases per year; see {@link annualValueOf}. */
export function annualValueCents(benefit: Benefit): number {
  return annualValueOf(benefit.valueCents, benefit.cadence, benefit.intervalMonths)
}
