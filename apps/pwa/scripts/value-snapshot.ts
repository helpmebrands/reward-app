/**
 * Dumps what the PWA's Value screen shows for the sample household on
 * 16 September 2026: the captured and missed totals over the last nine
 * months, each month's bars, the cards ranked worst-first and the biggest
 * leaks. The Flutter app's `value_screen_test.dart` asserts it renders the
 * same, so regenerate this whenever the sample or the selectors change:
 *
 *   node --experimental-strip-types scripts/value-snapshot.ts \
 *     > ../mobile/test/fixtures/sample-value.json
 */
import { readFileSync } from 'node:fs'
import {
  biggestLeaks,
  cardLabel,
  currentInstances,
  missedCycles,
  monthlyTotals,
  summarizeCard,
} from '../src/domain/selectors.ts'
import type { AppData } from '../src/domain/types.ts'

const data = JSON.parse(
  readFileSync(new URL('../samples/sample-household.json', import.meta.url), 'utf8'),
) as AppData
const on = '2026-09-16'
const instances = currentInstances(data, on)
const missed = missedCycles(data, on)
const months = monthlyTotals(data, missed, on, 9)
const summaries = data.cards
  .filter((card) => !card.archived)
  .map((card) => summarizeCard(card, data, instances, missed, on))
const ranked = [...summaries].sort((a, b) => a.feeProgress - b.feeProgress)

console.log(
  JSON.stringify(
    {
      on,
      monthsBack: 9,
      capturedTotalCents: months.reduce((sum, m) => sum + m.capturedCents, 0),
      missedTotalCents: months.reduce((sum, m) => sum + m.missedCents, 0),
      peakCents: Math.max(1, ...months.map((m) => Math.max(m.capturedCents, m.missedCents))),
      months: months.map((m) => ({
        label: m.label,
        capturedCents: m.capturedCents,
        missedCents: m.missedCents,
      })),
      ranked: ranked.map((s) => ({
        label: cardLabel(s.card),
        percent: Math.round(s.feeProgress * 100),
      })),
      leaks: biggestLeaks(missed).map((leak) => ({
        label: leak.label,
        when: leak.when,
        missedCents: leak.missedCents,
      })),
    },
    null,
    2,
  ),
)
