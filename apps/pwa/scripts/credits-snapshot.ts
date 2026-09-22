/**
 * Dumps what the PWA's Credits screen shows for the sample household on
 * 16 September 2026: the header counts, the four totals, and for every
 * filter the row names in order, plus the group labels and figures each
 * grouping produces. The Flutter app's `credits_screen_test.dart` asserts
 * it renders the same, so regenerate this whenever the sample or the
 * selectors change:
 *
 *   node --experimental-strip-types scripts/credits-snapshot.ts \
 *     > ../mobile/test/fixtures/sample-credits.json
 */
import { readFileSync } from 'node:fs'
import { cadenceLabel } from '../src/domain/cycles.ts'
import { formatMoney } from '../src/domain/format.ts'
import {
  byStatus,
  cardLabel,
  currentInstances,
  isClaimable,
  missedCycles,
  statusLabel,
  sumClaimed,
  sumRemaining,
  totalsFor,
} from '../src/domain/selectors.ts'
import type { AppData, BenefitInstance } from '../src/domain/types.ts'

const data = JSON.parse(
  readFileSync(new URL('../samples/sample-household.json', import.meta.url), 'utf8'),
) as AppData
const on = '2026-09-16'
const live = currentInstances(data, on)
const missed = missedCycles(data, on)

// Credits.tsx folds closed windows in as first-class rows.
const missedRows: BenefitInstance[] = missed.map((entry) => ({
  benefit: entry.benefit,
  card: entry.card,
  cycle: entry.cycle,
  status: 'missed' as const,
  claimedCents: entry.benefit.valueCents - entry.missedCents,
  remainingCents: entry.missedCents,
  daysRemaining: -1,
  cycleProgress: 1,
  muted: entry.benefit.muted || entry.card.muted,
}))
const allRows = [...live, ...missedRows]

type Filter = 'all' | 'use_soon' | 'open' | 'locked' | 'captured' | 'missed'
const FILTERS: Filter[] = ['all', 'use_soon', 'open', 'locked', 'captured', 'missed']

function filtered(filter: Filter): BenefitInstance[] {
  switch (filter) {
    case 'use_soon':
      return byStatus(allRows, 'use_soon')
    case 'open':
      return allRows.filter(isClaimable)
    case 'locked':
      return byStatus(allRows, 'locked')
    case 'captured':
      return allRows.filter((row) => row.claimedCents > 0 && row.status !== 'missed')
    case 'missed':
      return byStatus(allRows, 'missed')
    default:
      return allRows
  }
}

function figureFor(filter: Filter, instances: BenefitInstance[]): string {
  if (filter === 'missed') return `${formatMoney(sumRemaining(instances))} missed`
  if (filter === 'captured') return `${formatMoney(sumClaimed(instances))} captured`
  if (filter === 'locked') return `${formatMoney(sumRemaining(instances))} locked`
  const claimable = instances.filter(isClaimable)
  return `${formatMoney(sumRemaining(claimable))} claimable`
}

type Grouping = 'card' | 'cycle' | 'status'
function groups(filter: Filter, grouping: Grouping) {
  const buckets = new Map<string, BenefitInstance[]>()
  for (const row of filtered(filter)) {
    const key =
      grouping === 'card' ? row.card.id : grouping === 'cycle' ? row.benefit.cadence : row.status
    const bucket = buckets.get(key)
    if (bucket) bucket.push(row)
    else buckets.set(key, [row])
  }
  return [...buckets.values()].flatMap((instances) => {
    const first = instances[0]
    if (!first) return []
    const label =
      grouping === 'card'
        ? cardLabel(first.card)
        : grouping === 'cycle'
          ? cadenceLabel(first.benefit.cadence)
          : statusLabel(first.status)
    return [{ label, count: instances.length, figure: figureFor(filter, instances) }]
  })
}

const row = (i: BenefitInstance) => `${i.benefit.name} · ${i.card.holder} · ${i.cycle.label}`

console.log(
  JSON.stringify(
    {
      on,
      header: {
        open: live.filter(isClaimable).length,
        locked: byStatus(live, 'locked').length,
        missed: missed.length,
      },
      totals: totalsFor(
        live,
        missed.reduce((sum, m) => sum + m.missedCents, 0),
      ),
      filters: Object.fromEntries(FILTERS.map((f) => [f, filtered(f).map(row)])),
      groups: {
        card: groups('all', 'card'),
        cycle: groups('all', 'cycle'),
        status: groups('all', 'status'),
        missedByCard: groups('missed', 'card'),
        capturedByCard: groups('captured', 'card'),
      },
    },
    null,
    2,
  ),
)
