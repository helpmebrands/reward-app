/**
 * Generates `samples/sample-household.json`, importable from Settings.
 *
 * A fresh install is empty, and the screens worth judging — the Value tab, the
 * missed ledger, a card that has not earned its fee back — only appear once
 * there is history. This builds that history with the real domain functions, so
 * every claim lands on a cycle key the app will actually compute.
 *
 * Run: node --experimental-strip-types scripts/make-sample.ts
 */
import { writeFileSync } from 'node:fs'
import { benefitsFromTemplate, findTemplate } from '../src/domain/catalog.ts'
import { cycleFor } from '../src/domain/cycles.ts'
import type { AppData, Benefit, Card, Claim } from '../src/domain/types.ts'
import { DEFAULT_SETTINGS } from '../src/services/db.ts'

/** The date the design's scenario is set on. */
const TODAY = '2026-09-16'
/** Tracking starts in January, so the year's misses are attributable. */
const TRACKED_FROM = '2026-01-01T00:00:00.000Z'

let seq = 0
const id = (prefix: string) => `${prefix}-${String(++seq).padStart(4, '0')}`

function makeCard(holder: string, anniversaryOn: string): Card {
  return {
    id: id('card'),
    issuer: 'American Express',
    product: 'Platinum',
    holder,
    network: 'amex',
    annualFeeCents: 89_500,
    anniversaryOn,
    muted: false,
    archived: false,
    createdAt: TRACKED_FROM,
    updatedAt: TRACKED_FROM,
  }
}

const jim = makeCard('Jim', '2021-03-14')
const kathy = makeCard('Kathy', '2022-07-02')

const template = findTemplate('amex-platinum')
if (!template) throw new Error('missing amex-platinum template')

const benefits: Benefit[] = [
  ...benefitsFromTemplate(template, jim.id, TRACKED_FROM, () => id('ben')),
  ...benefitsFromTemplate(template, kathy.id, TRACKED_FROM, () => id('ben')),
]

function find(cardId: string, name: string): Benefit {
  const benefit = benefits.find((b) => b.cardId === cardId && b.name.startsWith(name))
  if (!benefit) throw new Error(`no benefit "${name}"`)
  return benefit
}

/** Marks a credit enrolled, which is what moves it off the Locked pile. */
function enrol(cardId: string, ...names: string[]) {
  for (const name of names) find(cardId, name).enrolledAt = TRACKED_FROM
}

// Jim keeps on top of the enrolment page; Kathy has two still unticked, which
// is what puts $500 of her card out of reach.
enrol(jim.id, 'Digital Entertainment', 'Resy', 'lululemon', 'Oura', 'Equinox')
enrol(kathy.id, 'Digital Entertainment', 'Resy', 'lululemon')

const claims: Claim[] = []

/**
 * Logs a claim against whichever cycle contains `on`, using the app's own cycle
 * maths so the key matches what the UI will look up.
 */
function claim(card: Card, name: string, on: string, amountCents?: number, atHour = 12) {
  const benefit = find(card.id, name)
  const cycle = cycleFor(benefit, card, on)
  if (!cycle) throw new Error(`${name} has no cycle`)
  claims.push({
    id: id('claim'),
    benefitId: benefit.id,
    cycleKey: cycle.key,
    amountCents: amountCents ?? benefit.valueCents,
    claimedAt: `${on}T${String(atHour).padStart(2, '0')}:00:00.000Z`,
  })
}

const MONTHS = ['01', '02', '03', '04', '05', '06', '07', '08', '09']

// Jim: uses the monthly Uber credit most months, and the big annual ones early.
for (const month of MONTHS) claim(jim, 'Uber Cash', `2026-${month}-14`)
claim(jim, 'Airline Fee', '2026-02-20')
claim(jim, 'CLEAR+', '2026-01-09')
claim(jim, 'lululemon', '2026-08-11')
claim(jim, 'Resy', '2026-08-28')
claim(jim, 'Hotel Credit', '2026-05-02')
claim(jim, 'Uber One', '2026-03-05')
// Partway through this month's entertainment credit — the partial-claim case.
claim(jim, 'Digital Entertainment', '2026-09-08', 1200)

// Kathy: barely touches hers. Eight months of small monthly credits gone, and
// the whole H1 hotel credit expired — the shape of loss the ladder exists for.
claim(kathy, 'CLEAR+', '2026-01-19')
claim(kathy, 'Uber Cash', '2026-07-21')
claim(kathy, 'Uber Cash', '2026-09-03')
claim(kathy, 'Resy', '2026-04-17', 4000)

const data: AppData = {
  version: 1,
  cards: [jim, kathy],
  benefits,
  claims,
  settings: {
    ...DEFAULT_SETTINGS,
    // Left off so the import does not silently start scheduling notifications;
    // turn it on in Settings to see the ladder.
    notifications: { ...DEFAULT_SETTINGS.notifications, enabled: false },
  },
}

writeFileSync('samples/sample-household.json', `${JSON.stringify(data, null, 2)}\n`)

console.log(
  `wrote samples/sample-household.json — ${data.cards.length} cards, ` +
    `${data.benefits.length} credits, ${data.claims.length} claims (as of ${TODAY})`,
)
