/**
 * Dumps what the PWA's Today screen shows for the sample household on
 * 16 September 2026: the totals, the rows in each section in order, and the
 * tone each row is drawn in. The Flutter app's `today_screen_test.dart`
 * asserts it renders the same, so regenerate this whenever the sample or
 * the selectors change:
 *
 *   node --experimental-strip-types scripts/today-snapshot.ts \
 *     > ../mobile/test/fixtures/sample-today.json
 */
import { readFileSync } from 'node:fs'
import {
  byStatus,
  currentInstances,
  findOverlaps,
  missedCycles,
  nextReset,
  totalsFor,
} from '../src/domain/selectors.ts'
import type { AppData, BenefitInstance, BenefitStatus } from '../src/domain/types.ts'

const data = JSON.parse(
  readFileSync(new URL('../samples/sample-household.json', import.meta.url), 'utf8'),
) as AppData
const on = '2026-09-16'
const instances = currentInstances(data, on)
const missed = missedCycles(data, on)

// The tone classes CreditRow.tsx applies, by status.
const tone = (status: BenefitStatus) =>
  status === 'use_soon'
    ? 'soon'
    : status === 'locked'
      ? 'locked'
      : status === 'captured' || status === 'manual'
        ? 'captured'
        : status === 'missed'
          ? 'missed'
          : 'available'

const row = (i: BenefitInstance) => ({
  name: i.benefit.name,
  holder: i.card.holder,
  tone: tone(i.status),
  cents: i.status === 'captured' ? i.claimedCents : i.remainingCents,
})

console.log(
  JSON.stringify(
    {
      on,
      totals: totalsFor(
        instances,
        missed.reduce((sum, m) => sum + m.missedCents, 0),
      ),
      nextReset: nextReset(instances),
      soon: byStatus(instances, 'use_soon').map(row),
      overlaps: findOverlaps(instances)
        .slice(0, 3)
        .map((o) => ({
          label: o.label,
          count: o.instances.length,
          remainingCents: o.remainingCents,
        })),
      locked: byStatus(instances, 'locked').map(row),
      captured: instances.filter((i) => i.claimedCents > 0).map(row),
    },
    null,
    2,
  ),
)
