/**
 * Dumps what the PWA's Cards screen shows for the sample household on
 * 16 September 2026: the fee and captured totals, and per active card its
 * label, figures, break-even line, verdict and tags, as Cards.tsx words
 * them. The Flutter app's `cards_screen_test.dart` asserts it renders the
 * same, so regenerate this whenever the sample or the selectors change:
 *
 *   node --experimental-strip-types scripts/cards-snapshot.ts \
 *     > ../mobile/test/fixtures/sample-cards.json
 */
import { readFileSync } from 'node:fs'
import { formatMoney } from '../src/domain/format.ts'
import {
  type CardSummary,
  cardLabel,
  currentInstances,
  missedCycles,
  summarizeCard,
} from '../src/domain/selectors.ts'
import type { AppData } from '../src/domain/types.ts'

const data = JSON.parse(
  readFileSync(new URL('../samples/sample-household.json', import.meta.url), 'utf8'),
) as AppData
const on = '2026-09-16'
const instances = currentInstances(data, on)
const missed = missedCycles(data, on)
const summaries = data.cards
  .filter((card) => !card.archived)
  .map((card) => summarizeCard(card, data, instances, missed, on))

// The verdict, as Cards.tsx words it.
function verdict(summary: CardSummary): { headline: string; body: string } {
  const { netCents, annualFeeCents, claimableCents, lockedCents, daysUntilRenewal } = summary
  if (annualFeeCents === 0) {
    return {
      headline: 'No fee',
      body: 'Nothing to break even against — every credit you capture is upside.',
    }
  }
  if (netCents >= 0) {
    return {
      headline: 'Keep',
      body: `Already ${formatMoney(netCents)} past the fee, with ${formatMoney(claimableCents)} still open.`,
    }
  }
  if (lockedCents > 0 && claimableCents + lockedCents >= Math.abs(netCents)) {
    return {
      headline: 'Unlock first',
      body: `${formatMoney(lockedCents)} is sitting behind an enrolment box. With it, there is enough left this year to clear the ${formatMoney(Math.abs(netCents))} shortfall — so unlock it before you weigh a downgrade.`,
    }
  }
  if (claimableCents >= Math.abs(netCents)) {
    return {
      headline: 'Catch up',
      body: `${formatMoney(claimableCents)} is still claimable — more than the ${formatMoney(Math.abs(netCents))} you are short. ${daysUntilRenewal} days to the renewal.`,
    }
  }
  return {
    headline: 'Decide',
    body: `${formatMoney(Math.abs(netCents))} short with ${daysUntilRenewal} days to the renewal, and only ${formatMoney(claimableCents)} left to claim. Lounge access and status are not counted here.`,
  }
}

function tags(summary: CardSummary): string[] {
  const out: string[] = []
  if (summary.claimableCents > 0) out.push(`${formatMoney(summary.claimableCents)} claimable`)
  if (summary.lockedCents > 0) out.push(`${formatMoney(summary.lockedCents)} locked`)
  if (summary.missedCents > 0) out.push(`${formatMoney(summary.missedCents)} missed`)
  out.push(`${summary.instances.length} credit${summary.instances.length === 1 ? '' : 's'}`)
  return out
}

console.log(
  JSON.stringify(
    {
      on,
      feeTotalCents: summaries.reduce((sum, s) => sum + s.annualFeeCents, 0),
      capturedTotalCents: summaries.reduce((sum, s) => sum + s.capturedCents, 0),
      cards: summaries.map((summary) => ({
        id: summary.card.id,
        issuer: summary.card.issuer,
        label: cardLabel(summary.card),
        fee: formatMoney(summary.annualFeeCents),
        captured: formatMoney(summary.capturedCents),
        net: `${summary.netCents >= 0 ? '+' : '−'}${formatMoney(Math.abs(summary.netCents))}`,
        percent: Math.round(summary.feeProgress * 100),
        daysUntilRenewal: summary.daysUntilRenewal,
        verdict: verdict(summary),
        tags: tags(summary),
      })),
    },
    null,
    2,
  ),
)
