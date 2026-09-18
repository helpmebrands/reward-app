import type { Benefit, BenefitCategory, Cadence, CardNetwork, CycleAnchor } from './types.ts'

/**
 * The card catalogue behind "Add a card".
 *
 * Issuers change these terms constantly, so this is a starting point for
 * onboarding, not a source of truth: everything it creates is an ordinary
 * editable credit, and the add-card flow says so. `enrollmentRequired` is the
 * field worth getting right — it is the difference between a credit the user is
 * failing to spend and one they cannot spend at all.
 */

export interface BenefitTemplate {
  name: string
  description?: string
  category: BenefitCategory
  /** Phosphor icon name. */
  icon: string
  merchant?: string
  valueCents: number
  cadence: Cadence
  anchor: CycleAnchor
  enrollmentRequired?: boolean
  redemptionSteps?: string[]
  notes?: string
}

export interface CardTemplate {
  id: string
  issuer: string
  product: string
  network: CardNetwork
  annualFeeCents: number
  benefits: BenefitTemplate[]
}

const AMEX_PLATINUM_BENEFITS: BenefitTemplate[] = [
  {
    name: 'Uber Cash',
    category: 'rideshare',
    icon: 'car-profile',
    merchant: 'Uber',
    valueCents: 1500,
    cadence: 'monthly',
    anchor: 'calendar',
    redemptionSteps: [
      'Open the Uber app and make sure this card is the selected payment method.',
      'Spend it on a ride or an Uber Eats order before the month closes.',
      'It never rolls over — and December is $35, not $15.',
    ],
  },
  {
    name: 'Digital Entertainment Credit',
    category: 'streaming',
    icon: 'monitor-play',
    valueCents: 2500,
    cadence: 'monthly',
    anchor: 'calendar',
    enrollmentRequired: true,
    redemptionSteps: [
      'Enrolment is required once, on the issuer benefits page.',
      'Pay a participating subscription with the card — Disney+, Hulu, ESPN+, Peacock, NYT, WSJ, YouTube Premium, Paramount+.',
      'Up to $25 a month; the balance does not carry forward.',
    ],
  },
  {
    name: 'Walmart+ Membership Credit',
    category: 'shopping',
    icon: 'shopping-bag',
    merchant: 'Walmart',
    valueCents: 1295,
    cadence: 'monthly',
    anchor: 'calendar',
    redemptionSteps: [
      'Pay the monthly Walmart+ membership with this card — not the annual plan.',
      '$12.95 plus tax is reimbursed each month.',
      'Plus Ups are excluded.',
    ],
  },
  {
    name: 'Resy Dining Credit',
    category: 'dining',
    icon: 'fork-knife',
    merchant: 'Resy',
    valueCents: 10_000,
    cadence: 'quarterly',
    anchor: 'calendar',
    enrollmentRequired: true,
    redemptionSteps: [
      'Enrol once, and link the Resy profile to the card.',
      'Spend at an eligible US Resy restaurant and pay with the card.',
      'Up to $100 per quarter.',
    ],
  },
  {
    name: 'lululemon Credit',
    category: 'shopping',
    icon: 'shopping-bag',
    merchant: 'lululemon',
    valueCents: 7500,
    cadence: 'quarterly',
    anchor: 'calendar',
    enrollmentRequired: true,
    redemptionSteps: [
      'Enrolment required on the benefits page.',
      'Spend at a US lululemon store or lululemon.com with the card.',
      'Up to $75 per quarter.',
    ],
  },
  {
    name: 'Hotel Credit (FHR / THC)',
    category: 'lodging',
    icon: 'bed',
    valueCents: 30_000,
    cadence: 'semiannual',
    anchor: 'calendar',
    redemptionSteps: [
      'Book prepaid through the issuer travel portal — not direct with the hotel.',
      'Fine Hotels + Resorts, or The Hotel Collection with a two-night minimum.',
      '$300 per half-year. One booking cannot draw on two cards.',
    ],
  },
  {
    name: 'Airline Fee Credit',
    category: 'airline',
    icon: 'airplane-tilt',
    valueCents: 20_000,
    cadence: 'annual',
    anchor: 'calendar',
    redemptionSteps: [
      'Select one qualifying airline for the calendar year — the selection is per card.',
      'Charge incidental fees: checked bags, seat selection, lounge day passes.',
      'Airfare itself is not eligible.',
    ],
  },
  {
    name: 'CLEAR+ Credit',
    category: 'travel',
    icon: 'fingerprint',
    merchant: 'CLEAR',
    valueCents: 21_900,
    cadence: 'annual',
    anchor: 'calendar',
    redemptionSteps: ['Pay the CLEAR+ membership with the card.', 'Covers the membership in full.'],
  },
  {
    name: 'Uber One Membership Credit',
    category: 'rideshare',
    icon: 'moped',
    merchant: 'Uber',
    valueCents: 12_000,
    cadence: 'annual',
    anchor: 'calendar',
    redemptionSteps: [
      'Set the auto-renewing Uber One membership to bill this card.',
      'Up to $120 a year, credited as it bills.',
    ],
  },
  {
    name: 'Oura Ring Credit',
    category: 'wellness',
    icon: 'heartbeat',
    merchant: 'Oura',
    valueCents: 20_000,
    cadence: 'annual',
    anchor: 'calendar',
    enrollmentRequired: true,
    redemptionSteps: [
      'Enrol on the benefits page first.',
      'Buy the ring directly from Oura with the card.',
    ],
  },
  {
    name: 'Equinox Credit',
    category: 'wellness',
    icon: 'barbell',
    merchant: 'Equinox',
    valueCents: 30_000,
    cadence: 'annual',
    anchor: 'calendar',
    enrollmentRequired: true,
    redemptionSteps: [
      'Enrol on the benefits page — this is the blocker, not the spend.',
      'Charge an Equinox club membership or Equinox+ to the card.',
    ],
  },
  {
    name: 'Global Entry / TSA PreCheck',
    category: 'travel',
    icon: 'identification-card',
    valueCents: 12_000,
    cadence: 'manual',
    anchor: 'calendar',
    redemptionSteps: [
      'Pay the application fee with the card when you next become eligible.',
      'Global Entry $120 every four years, or PreCheck up to $85 every four and a half.',
    ],
    notes: 'No cycle tracks this — review it by hand when the membership nears expiry.',
  },
]

export const CARD_TEMPLATES: CardTemplate[] = [
  {
    id: 'amex-platinum',
    issuer: 'American Express',
    product: 'Platinum',
    network: 'amex',
    annualFeeCents: 89_500,
    benefits: AMEX_PLATINUM_BENEFITS,
  },
  {
    id: 'amex-gold',
    issuer: 'American Express',
    product: 'Gold',
    network: 'amex',
    annualFeeCents: 32_500,
    benefits: [
      {
        name: 'Dining Credit',
        category: 'dining',
        icon: 'fork-knife',
        valueCents: 1000,
        cadence: 'monthly',
        anchor: 'calendar',
        enrollmentRequired: true,
      },
      {
        name: 'Uber Cash',
        category: 'rideshare',
        icon: 'car-profile',
        merchant: 'Uber',
        valueCents: 1000,
        cadence: 'monthly',
        anchor: 'calendar',
        enrollmentRequired: true,
      },
      {
        name: 'Resy Credit',
        category: 'dining',
        icon: 'wine',
        merchant: 'Resy',
        valueCents: 10_000,
        cadence: 'semiannual',
        anchor: 'calendar',
        enrollmentRequired: true,
      },
      {
        name: 'Dunkin’ Credit',
        category: 'dining',
        icon: 'coffee',
        merchant: 'Dunkin',
        valueCents: 700,
        cadence: 'monthly',
        anchor: 'calendar',
        enrollmentRequired: true,
      },
    ],
  },
  {
    id: 'amex-business-platinum',
    issuer: 'American Express',
    product: 'Business Platinum',
    network: 'amex',
    annualFeeCents: 89_500,
    benefits: [
      {
        name: 'Dell Credit',
        category: 'shopping',
        icon: 'desktop',
        merchant: 'Dell',
        valueCents: 20_000,
        cadence: 'semiannual',
        anchor: 'calendar',
        enrollmentRequired: true,
      },
      {
        name: 'Adobe Credit',
        category: 'shopping',
        icon: 'pen-nib',
        merchant: 'Adobe',
        valueCents: 15_000,
        cadence: 'annual',
        anchor: 'calendar',
        enrollmentRequired: true,
      },
      {
        name: 'Indeed Credit',
        category: 'shopping',
        icon: 'briefcase',
        merchant: 'Indeed',
        valueCents: 9000,
        cadence: 'quarterly',
        anchor: 'calendar',
        enrollmentRequired: true,
      },
      {
        name: 'Wireless Credit',
        category: 'shopping',
        icon: 'wifi-high',
        valueCents: 1000,
        cadence: 'monthly',
        anchor: 'calendar',
        enrollmentRequired: true,
      },
      {
        name: 'Airline Fee Credit',
        category: 'airline',
        icon: 'airplane-tilt',
        valueCents: 20_000,
        cadence: 'annual',
        anchor: 'calendar',
      },
      {
        name: 'CLEAR+ Credit',
        category: 'travel',
        icon: 'fingerprint',
        merchant: 'CLEAR',
        valueCents: 20_900,
        cadence: 'annual',
        anchor: 'calendar',
      },
      {
        name: 'Hilton Credit',
        category: 'lodging',
        icon: 'bed',
        merchant: 'Hilton',
        valueCents: 20_000,
        cadence: 'semiannual',
        anchor: 'calendar',
        enrollmentRequired: true,
      },
    ],
  },
  {
    id: 'chase-sapphire-reserve',
    issuer: 'Chase',
    product: 'Sapphire Reserve',
    network: 'visa',
    annualFeeCents: 55_000,
    benefits: [
      {
        name: 'Travel Credit',
        category: 'travel',
        icon: 'airplane-tilt',
        valueCents: 30_000,
        cadence: 'annual',
        anchor: 'anniversary',
        redemptionSteps: [
          'Applies automatically to the first travel purchases of the cardmember year.',
          'Runs on the cardmember year, not the calendar year.',
        ],
      },
      {
        name: 'DashPass Membership',
        category: 'dining',
        icon: 'moped',
        merchant: 'DoorDash',
        valueCents: 12_000,
        cadence: 'annual',
        anchor: 'anniversary',
        enrollmentRequired: true,
      },
      {
        name: 'DoorDash Promo Credits',
        category: 'dining',
        icon: 'bowl-food',
        merchant: 'DoorDash',
        valueCents: 1000,
        cadence: 'monthly',
        anchor: 'calendar',
        enrollmentRequired: true,
      },
      {
        name: 'Lyft Credit',
        category: 'rideshare',
        icon: 'car-profile',
        merchant: 'Lyft',
        valueCents: 1000,
        cadence: 'monthly',
        anchor: 'calendar',
        enrollmentRequired: true,
      },
      {
        name: 'Peloton Credit',
        category: 'wellness',
        icon: 'barbell',
        merchant: 'Peloton',
        valueCents: 12_000,
        cadence: 'annual',
        anchor: 'anniversary',
        enrollmentRequired: true,
      },
      {
        name: 'Global Entry / TSA PreCheck',
        category: 'travel',
        icon: 'identification-card',
        valueCents: 12_000,
        cadence: 'manual',
        anchor: 'calendar',
      },
    ],
  },
  {
    id: 'capital-one-venture-x',
    issuer: 'Capital One',
    product: 'Venture X',
    network: 'visa',
    annualFeeCents: 39_500,
    benefits: [
      {
        name: 'Travel Credit',
        category: 'travel',
        icon: 'airplane-tilt',
        valueCents: 30_000,
        cadence: 'annual',
        anchor: 'anniversary',
        redemptionSteps: ['Must be booked through the issuer travel portal.'],
      },
      {
        name: 'Global Entry / TSA PreCheck',
        category: 'travel',
        icon: 'identification-card',
        valueCents: 12_000,
        cadence: 'manual',
        anchor: 'calendar',
      },
    ],
  },
  {
    id: 'hilton-aspire',
    issuer: 'Hilton',
    product: 'Honors Aspire',
    network: 'amex',
    annualFeeCents: 55_000,
    benefits: [
      {
        name: 'Hilton Resort Credit',
        category: 'lodging',
        icon: 'umbrella',
        merchant: 'Hilton',
        valueCents: 20_000,
        cadence: 'semiannual',
        anchor: 'calendar',
        enrollmentRequired: true,
      },
      {
        name: 'Airline Flight Credit',
        category: 'airline',
        icon: 'airplane-tilt',
        valueCents: 5000,
        cadence: 'quarterly',
        anchor: 'calendar',
      },
      {
        name: 'CLEAR+ Credit',
        category: 'travel',
        icon: 'fingerprint',
        merchant: 'CLEAR',
        valueCents: 20_900,
        cadence: 'annual',
        anchor: 'calendar',
        enrollmentRequired: true,
      },
      {
        name: 'Free Night Award',
        category: 'lodging',
        icon: 'bed',
        valueCents: 25_000,
        cadence: 'annual',
        anchor: 'anniversary',
      },
    ],
  },
  {
    id: 'delta-reserve',
    issuer: 'Delta',
    product: 'Reserve',
    network: 'amex',
    annualFeeCents: 65_000,
    benefits: [
      {
        name: 'Resy Credit',
        category: 'dining',
        icon: 'fork-knife',
        merchant: 'Resy',
        valueCents: 2000,
        cadence: 'monthly',
        anchor: 'calendar',
        enrollmentRequired: true,
      },
      {
        name: 'Rideshare Credit',
        category: 'rideshare',
        icon: 'car-profile',
        valueCents: 1000,
        cadence: 'monthly',
        anchor: 'calendar',
        enrollmentRequired: true,
      },
      {
        name: 'Delta Stays Credit',
        category: 'lodging',
        icon: 'bed',
        valueCents: 20_000,
        cadence: 'annual',
        anchor: 'anniversary',
      },
    ],
  },
  {
    id: 'blank',
    issuer: '',
    product: '',
    network: 'other',
    annualFeeCents: 0,
    benefits: [],
  },
]

export function findTemplate(id: string): CardTemplate | undefined {
  return CARD_TEMPLATES.find((template) => template.id === id)
}

/** Total value a template releases in a year, for the catalogue rows. */
export function templateAnnualValueCents(template: CardTemplate): number {
  const perYear: Record<Cadence, number> = {
    monthly: 12,
    quarterly: 4,
    semiannual: 2,
    annual: 1,
    manual: 1,
  }
  return template.benefits.reduce((sum, b) => sum + b.valueCents * perYear[b.cadence], 0)
}

/** Credits in a template that are stuck behind an enrolment box. */
export function templateEnrollmentNames(template: CardTemplate): string[] {
  return template.benefits.filter((b) => b.enrollmentRequired).map((b) => b.name)
}

/** Turns a template into real benefits attached to a newly created card. */
export function benefitsFromTemplate(
  template: CardTemplate,
  cardId: string,
  now: string,
  newId: () => string,
): Benefit[] {
  return template.benefits.map((entry) => ({
    id: newId(),
    cardId,
    name: entry.name,
    category: entry.category,
    icon: entry.icon,
    valueCents: entry.valueCents,
    cadence: entry.cadence,
    anchor: entry.anchor,
    enrollmentRequired: entry.enrollmentRequired ?? false,
    redemptionSteps: entry.redemptionSteps ?? [],
    muted: false,
    lastCallOnly: false,
    active: true,
    createdAt: now,
    updatedAt: now,
    ...(entry.description ? { description: entry.description } : {}),
    ...(entry.merchant ? { merchant: entry.merchant } : {}),
    ...(entry.notes ? { notes: entry.notes } : {}),
  }))
}
