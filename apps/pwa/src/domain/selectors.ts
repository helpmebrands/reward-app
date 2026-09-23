import {
  annualValueCents,
  closedCyclesBefore,
  cycleFor,
  cycleProgress,
  daysRemainingIn,
  hasEnded,
} from './cycles.ts'
import { compareIsoDate, daysBetween, isWithin, todayIso } from './dates.ts'
import type {
  AppData,
  Benefit,
  BenefitInstance,
  BenefitStatus,
  Card,
  Claim,
  Cycle,
  IsoDate,
} from './types.ts'
import { USE_SOON_DAYS } from './types.ts'

/** Claims indexed by benefit + cycle, so resolving every credit stays O(n). */
type ClaimIndex = Map<string, number>

function keyOf(benefitId: string, cycleKey: string): string {
  // Ids are UUIDs and cycle keys are ISO dates, so neither can contain '::'.
  return `${benefitId}::${cycleKey}`
}

export function indexClaims(claims: Claim[]): ClaimIndex {
  const index: ClaimIndex = new Map()
  for (const claim of claims) {
    const key = keyOf(claim.benefitId, claim.cycleKey)
    index.set(key, (index.get(key) ?? 0) + claim.amountCents)
  }
  return index
}

export function claimedIn(claims: ClaimIndex, benefitId: string, cycleKey: string): number {
  return claims.get(keyOf(benefitId, cycleKey)) ?? 0
}

/** Why a credit cannot be spent yet. Enrolment outranks spend. */
export type LockReason = 'enrollment' | 'spend'

/**
 * What stands between the user and the credit, or null when nothing does: an
 * unticked enrolment box, or a spend threshold not yet met this year.
 */
export function lockReason(benefit: Benefit, card: Card, on: IsoDate): LockReason | null {
  if (benefit.enrollmentRequired && !benefit.enrolledAt) return 'enrollment'
  if (benefit.spendThresholdCents !== undefined && !spendMetThisYear(benefit, card, on)) {
    return 'spend'
  }
  return null
}

/** True when a credit cannot be spent until a box is ticked or a spend reached. */
export function isLocked(benefit: Benefit, card: Card, on: IsoDate): boolean {
  return lockReason(benefit, card, on) !== null
}

/**
 * Whether the spend was met in the credit's current year: the calendar year
 * for a calendar-anchored credit, the cardmember year for an anniversary one.
 */
function spendMetThisYear(benefit: Benefit, card: Card, on: IsoDate): boolean {
  if (!benefit.spendMetAt) return false
  const year = cycleFor({ ...benefit, cadence: 'annual' }, card, on)
  return year !== null && isWithin(benefit.spendMetAt.slice(0, 10), year.start, year.end)
}

function statusFor(
  benefit: Benefit,
  claimedCents: number,
  daysRemaining: number,
  locked: boolean,
  useSoonDays: number,
): BenefitStatus {
  if (claimedCents >= benefit.valueCents) return 'captured'
  if (benefit.cadence === 'manual') return 'manual'
  if (locked) return 'locked'
  if (daysRemaining < 0) return 'missed'
  return daysRemaining <= useSoonDays ? 'use_soon' : 'available'
}

/**
 * Resolves one benefit against one cycle.
 *
 * `locked` outranks `use_soon` deliberately: a credit stuck behind an unticked
 * box is not something the user is failing to spend, and dunning them to spend
 * it would be telling them to do something they cannot do.
 */
export function resolveInstance(
  benefit: Benefit,
  card: Card,
  cycle: Cycle,
  claims: ClaimIndex,
  on: IsoDate,
  useSoonDays: number = USE_SOON_DAYS,
): BenefitInstance {
  const claimedCents = claimedIn(claims, benefit.id, cycle.key)
  const daysRemaining = daysRemainingIn(cycle, on)
  return {
    benefit,
    card,
    cycle,
    claimedCents,
    remainingCents: Math.max(0, benefit.valueCents - claimedCents),
    status: statusFor(
      benefit,
      claimedCents,
      daysRemaining,
      isLocked(benefit, card, on),
      useSoonDays,
    ),
    daysRemaining,
    cycleProgress: cycleProgress(cycle, on),
    muted: benefit.muted || card.muted,
  }
}

/** A stand-in window for `manual` credits, which have no real cycle. */
function untrackedCycle(on: IsoDate): Cycle {
  return { key: on, start: on, end: '2999-12-31', label: 'Untracked' }
}

/**
 * Every active benefit resolved against its current cycle, ordered by what the
 * user is closest to losing.
 */
export function currentInstances(data: AppData, on: IsoDate = todayIso()): BenefitInstance[] {
  const claims = indexClaims(data.claims)
  const cardsById = new Map(data.cards.map((card) => [card.id, card]))
  const instances: BenefitInstance[] = []

  for (const benefit of data.benefits) {
    if (!benefit.active || hasEnded(benefit, on)) continue
    const card = cardsById.get(benefit.cardId)
    if (!card || card.archived) continue
    const cycle = cycleFor(benefit, card, on) ?? untrackedCycle(on)
    instances.push(resolveInstance(benefit, card, cycle, claims, on, data.settings.useSoonDays))
  }

  return instances.sort(compareByUrgency)
}

const STATUS_ORDER: Record<BenefitStatus, number> = {
  use_soon: 0,
  available: 1,
  locked: 2,
  manual: 3,
  captured: 4,
  missed: 5,
}

/** Ladder position first, then soonest deadline, then biggest amount at stake. */
export function compareByUrgency(a: BenefitInstance, b: BenefitInstance): number {
  const byStatus = STATUS_ORDER[a.status] - STATUS_ORDER[b.status]
  if (byStatus !== 0) return byStatus
  if (a.daysRemaining !== b.daysRemaining) return a.daysRemaining - b.daysRemaining
  return b.remainingCents - a.remainingCents
}

/** Spendable right now: open, unlocked, and on a real cycle. */
export function isClaimable(instance: BenefitInstance): boolean {
  return instance.status === 'use_soon' || instance.status === 'available'
}

export function byStatus(instances: BenefitInstance[], status: BenefitStatus): BenefitInstance[] {
  return instances.filter((i) => i.status === status)
}

export function sumRemaining(instances: BenefitInstance[]): number {
  return instances.reduce((sum, i) => sum + i.remainingCents, 0)
}

export function sumClaimed(instances: BenefitInstance[]): number {
  return instances.reduce((sum, i) => sum + i.claimedCents, 0)
}

/**
 * The four figures the Credits screen insists on keeping apart. Adding money
 * you can still get to money you have already lost would be meaningless, so
 * they are never summed into one total.
 */
export interface Totals {
  /** Open and spendable. Today's headline number. */
  claimableCents: number
  /** Behind an enrolment box — excluded from `claimable` on purpose. */
  lockedCents: number
  /** Already used this cycle. */
  capturedCents: number
  /** Windows that closed unused, this calendar year. */
  missedCents: number
}

export function totalsFor(instances: BenefitInstance[], missedCents: number): Totals {
  return {
    claimableCents: sumRemaining(instances.filter(isClaimable)),
    lockedCents: sumRemaining(byStatus(instances, 'locked')),
    capturedCents: sumClaimed(instances),
    missedCents,
  }
}

/** Open credits whose window closes within the "Use soon" horizon. */
export function useSoon(instances: BenefitInstance[]): BenefitInstance[] {
  return byStatus(instances, 'use_soon')
}

/** The date the nearest open window closes, which Today headlines. */
export function nextReset(instances: BenefitInstance[]): IsoDate | null {
  const open = instances.filter(isClaimable)
  if (open.length === 0) return null
  return open.reduce(
    (soonest, i) => (compareIsoDate(i.cycle.end, soonest) < 0 ? i.cycle.end : soonest),
    open[0]?.cycle.end ?? '',
  )
}

export interface OverlapGroup {
  /** The credit both cards carry, e.g. "Resy Dining Credit". */
  label: string
  instances: BenefitInstance[]
  /** Combined value still unclaimed across the group this cycle. */
  remainingCents: number
  /** True when the same product is held by two people in the household. */
  sameProduct: boolean
}

/**
 * Credits that exist twice.
 *
 * The design's premise: the household holds the same Platinum twice, so every
 * credit on it exists twice and one booking cannot draw on both. Matching is by
 * credit name within a card product, then by merchant across products — name
 * alone would collide across issuers that happen to use the same wording.
 */
export function findOverlaps(instances: BenefitInstance[]): OverlapGroup[] {
  const groups = new Map<string, BenefitInstance[]>()

  for (const instance of instances) {
    if (!isClaimable(instance) && instance.status !== 'locked') continue
    const merchant = instance.benefit.merchant?.trim().toLowerCase()
    const key = merchant ? `m:${merchant}` : `n:${instance.benefit.name.trim().toLowerCase()}`
    const bucket = groups.get(key)
    if (bucket) bucket.push(instance)
    else groups.set(key, [instance])
  }

  const overlaps: OverlapGroup[] = []
  for (const group of groups.values()) {
    const first = group[0]
    if (!first) continue
    // Two rows on the *same* card are not an overlap, they are two credits.
    if (new Set(group.map((i) => i.card.id)).size < 2) continue
    overlaps.push({
      label: first.benefit.name,
      instances: group.sort((a, b) => a.card.holder.localeCompare(b.card.holder)),
      remainingCents: sumRemaining(group),
      sameProduct: new Set(group.map((i) => `${i.card.issuer} ${i.card.product}`)).size === 1,
    })
  }

  return overlaps.sort((a, b) => b.remainingCents - a.remainingCents)
}

export interface MissedCycle {
  benefit: Benefit
  card: Card
  cycle: Cycle
  missedCents: number
}

/**
 * Windows that closed with money left in them, newest first.
 *
 * This is computed rather than stored: a closed cycle with no claim against it
 * is a miss, and deriving it means the ledger is always consistent with the
 * claims the user actually logged.
 */
export function missedCycles(
  data: AppData,
  on: IsoDate = todayIso(),
  lookbackCycles = 24,
): MissedCycle[] {
  const claims = indexClaims(data.claims)
  const cardsById = new Map(data.cards.map((card) => [card.id, card]))
  const missed: MissedCycle[] = []
  // Only count windows that opened after the card was added — the app cannot
  // know whether a credit was used before it started tracking.
  for (const benefit of data.benefits) {
    if (!benefit.active || benefit.cadence === 'manual') continue
    const card = cardsById.get(benefit.cardId)
    if (!card || card.archived) continue
    const trackedFrom = card.createdAt.slice(0, 10)

    for (const cycle of closedCyclesBefore(benefit, card, on, lookbackCycles)) {
      if (compareIsoDate(cycle.start, trackedFrom) < 0) break
      const claimed = claimedIn(claims, benefit.id, cycle.key)
      const shortfall = benefit.valueCents - claimed
      if (shortfall > 0) missed.push({ benefit, card, cycle, missedCents: shortfall })
    }
  }

  return missed.sort((a, b) => compareIsoDate(b.cycle.end, a.cycle.end))
}

export interface Leak {
  label: string
  /** e.g. "Jan – Aug 2026". */
  when: string
  missedCents: number
  occurrences: number
  icon?: string
}

/**
 * Recurring credits that keep expiring unclaimed, worst first.
 *
 * Grouped by credit rather than listed per cycle, because "Uber Cash, eight
 * months, $240" is a fixable habit while eight separate $15 rows are noise.
 */
export function biggestLeaks(missed: MissedCycle[], limit = 5): Leak[] {
  const groups = new Map<string, MissedCycle[]>()
  for (const entry of missed) {
    const key = `${entry.benefit.name}::${entry.card.id}`
    const bucket = groups.get(key)
    if (bucket) bucket.push(entry)
    else groups.set(key, [entry])
  }

  const leaks: Leak[] = []
  for (const group of groups.values()) {
    const first = group[0]
    const last = group[group.length - 1]
    if (!first || !last) continue
    leaks.push({
      label: group.length > 1 ? `${first.benefit.name} × ${group.length}` : first.benefit.name,
      when: group.length > 1 ? `${last.cycle.label} – ${first.cycle.label}` : first.cycle.label,
      missedCents: group.reduce((sum, entry) => sum + entry.missedCents, 0),
      occurrences: group.length,
      ...(first.benefit.icon ? { icon: first.benefit.icon } : {}),
    })
  }

  return leaks.sort((a, b) => b.missedCents - a.missedCents).slice(0, limit)
}

export interface MonthTotals {
  /** `YYYY-MM`. */
  month: string
  label: string
  capturedCents: number
  missedCents: number
}

/** Captured against missed, by month — the Value tab's chart. */
export function monthlyTotals(
  data: AppData,
  missed: MissedCycle[],
  on: IsoDate = todayIso(),
  months = 9,
): MonthTotals[] {
  const buckets = new Map<string, MonthTotals>()
  const { year, month } = { year: Number(on.slice(0, 4)), month: Number(on.slice(5, 7)) }

  for (let back = months - 1; back >= 0; back--) {
    const zeroBased = year * 12 + (month - 1) - back
    const key = `${Math.floor(zeroBased / 12)}-${String((zeroBased % 12) + 1).padStart(2, '0')}`
    buckets.set(key, {
      month: key,
      label: MONTH_LABELS[zeroBased % 12] ?? '',
      capturedCents: 0,
      missedCents: 0,
    })
  }

  for (const claim of data.claims) {
    const bucket = buckets.get(claim.claimedAt.slice(0, 7))
    if (bucket) bucket.capturedCents += claim.amountCents
  }
  for (const entry of missed) {
    // A miss lands in the month its window closed, which is when the money
    // actually went away.
    const bucket = buckets.get(entry.cycle.end.slice(0, 7))
    if (bucket) bucket.missedCents += entry.missedCents
  }

  return [...buckets.values()]
}

const MONTH_LABELS = [
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

export interface CardSummary {
  card: Card
  instances: BenefitInstance[]
  /** Value this card releases over a full year. */
  annualValueCents: number
  /** Claimed so far this cardmember year. */
  capturedCents: number
  /** Still claimable in the current windows. */
  claimableCents: number
  lockedCents: number
  missedCents: number
  annualFeeCents: number
  /** Captured minus the fee. Negative means the card is not paying for itself. */
  netCents: number
  /** Captured as a share of the fee, 0..1+ — the break-even bar. */
  feeProgress: number
  daysUntilRenewal: number
}

export function summarizeCard(
  card: Card,
  data: AppData,
  instances: BenefitInstance[],
  missed: MissedCycle[],
  on: IsoDate = todayIso(),
): CardSummary {
  const mine = instances.filter((i) => i.card.id === card.id)
  const benefits = data.benefits.filter((b) => b.cardId === card.id && b.active)
  const capturedCents = claimedThisCardYear(card, data, on)
  return {
    card,
    instances: mine,
    // A spend-gated credit is not the card's to give until the spend is met.
    annualValueCents: benefits.reduce(
      (sum, b) => sum + (lockReason(b, card, on) === 'spend' ? 0 : annualValueCents(b)),
      0,
    ),
    capturedCents,
    claimableCents: sumRemaining(mine.filter(isClaimable)),
    lockedCents: sumRemaining(mine.filter((i) => i.status === 'locked')),
    missedCents: missed
      .filter((m) => m.card.id === card.id)
      .reduce((sum, m) => sum + m.missedCents, 0),
    annualFeeCents: card.annualFeeCents,
    netCents: capturedCents - card.annualFeeCents,
    feeProgress: card.annualFeeCents > 0 ? capturedCents / card.annualFeeCents : 1,
    daysUntilRenewal: daysUntilRenewal(card, on),
  }
}

/** A stand-in benefit used to reuse the cycle maths for card-level windows. */
function cardYearBenefit(card: Card): Benefit {
  return {
    id: `${card.id}-year`,
    cardId: card.id,
    name: 'Cardmember year',
    category: 'fee_credit',
    valueCents: card.annualFeeCents,
    cadence: 'annual',
    anchor: 'anniversary',
    enrollmentRequired: false,
    redemptionSteps: [],
    muted: false,
    lastCallOnly: false,
    active: true,
    createdAt: card.createdAt,
    updatedAt: card.updatedAt,
  }
}

/** The start of the cardmember year containing `on`. */
export function cardYearStart(card: Card, on: IsoDate = todayIso()): IsoDate {
  return cycleFor(cardYearBenefit(card), card, on)?.start ?? on
}

/** Cents claimed since the card's most recent anniversary. */
export function claimedThisCardYear(card: Card, data: AppData, on: IsoDate = todayIso()): number {
  const benefitIds = new Set(data.benefits.filter((b) => b.cardId === card.id).map((b) => b.id))
  const yearStart = cardYearStart(card, on)
  return data.claims
    .filter((claim) => benefitIds.has(claim.benefitId) && claim.claimedAt.slice(0, 10) >= yearStart)
    .reduce((sum, claim) => sum + claim.amountCents, 0)
}

/** Days until the annual fee posts again. */
export function daysUntilRenewal(card: Card, on: IsoDate = todayIso()): number {
  const cycle = cycleFor(cardYearBenefit(card), card, on)
  return cycle ? daysBetween(on, cycle.end) + 1 : 0
}

/** Distinct household members, in the order their cards were added. */
export function holders(data: AppData): string[] {
  const seen: string[] = []
  for (const card of data.cards) {
    if (!card.archived && card.holder && !seen.includes(card.holder)) seen.push(card.holder)
  }
  return seen
}

export function cardLabel(card: Card): string {
  if (card.nickname) return card.nickname
  const product = [card.issuer, card.product].filter(Boolean).join(' ').trim() || 'Card'
  return card.holder ? `${product} — ${card.holder}` : product
}

const CATEGORY_LABELS: Record<BenefitCategoryKey, string> = {
  travel: 'Travel',
  dining: 'Dining',
  shopping: 'Shopping',
  entertainment: 'Entertainment',
  rideshare: 'Rideshare / Food',
  wellness: 'Health / Fitness',
  lodging: 'Lodging',
  airline: 'Airline',
  streaming: 'Streaming',
  fee_credit: 'Fee credit',
  other: 'Other',
}

type BenefitCategoryKey = Benefit['category']

export function categoryLabel(category: BenefitCategoryKey): string {
  return CATEGORY_LABELS[category]
}

const STATUS_LABELS: Record<BenefitStatus, string> = {
  use_soon: 'Use soon',
  available: 'Available',
  locked: 'Locked',
  captured: 'Captured',
  manual: 'Manual',
  missed: 'Missed',
}

export function statusLabel(status: BenefitStatus): string {
  return STATUS_LABELS[status]
}
