import type { AppData, Benefit, Cadence, Card, Claim, CycleAnchor } from '../src/domain/types.ts'
import { DEFAULT_SETTINGS } from '../src/services/db.ts'

/** Test fixtures, so each test states only what it is actually about. */

export function makeCard(overrides: Partial<Card> = {}): Card {
  return {
    id: 'card-1',
    issuer: 'American Express',
    product: 'Platinum',
    holder: 'Jim',
    network: 'amex',
    kind: 'personal',
    annualFeeCents: 89_500,
    anniversaryOn: '2020-03-14',
    muted: false,
    archived: false,
    createdAt: '2020-03-14T00:00:00.000Z',
    updatedAt: '2020-03-14T00:00:00.000Z',
    ...overrides,
  }
}

export function makeBenefit(
  cadence: Cadence = 'monthly',
  overrides: Partial<Benefit> = {},
): Benefit {
  return {
    id: 'benefit-1',
    cardId: 'card-1',
    name: 'Test credit',
    category: 'other',
    valueCents: 2500,
    cadence,
    anchor: 'calendar' as CycleAnchor,
    enrollmentRequired: false,
    redemptionSteps: [],
    muted: false,
    lastCallOnly: false,
    active: true,
    createdAt: '2020-03-14T00:00:00.000Z',
    updatedAt: '2020-03-14T00:00:00.000Z',
    ...overrides,
  }
}

export function makeClaim(overrides: Partial<Claim> = {}): Claim {
  return {
    id: 'claim-1',
    benefitId: 'benefit-1',
    cycleKey: '2026-09-01',
    amountCents: 2500,
    claimedAt: '2026-09-10T12:00:00.000Z',
    ...overrides,
  }
}

export function makeData(overrides: Partial<AppData> = {}): AppData {
  return {
    version: 1,
    cards: [makeCard()],
    benefits: [makeBenefit()],
    claims: [],
    settings: DEFAULT_SETTINGS,
    ...overrides,
  }
}
