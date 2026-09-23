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

export const CARD_TEMPLATES: CardTemplate[] = [
  {
    id: 'amex-business-platinum',
    issuer: 'American Express',
    product: 'Business Platinum',
    network: 'amex',
    annualFeeCents: 89500,
    benefits: [
      {
        name: 'Hotel Credit (Fine Hotels + Resorts / The Hotel Collection)',
        description:
          'Up to $300 back each half-year on prepaid FHR or Hotel Collection bookings via Amex Travel.',
        category: 'lodging',
        icon: 'bed',
        merchant: 'Amex Travel',
        valueCents: 30000,
        cadence: 'semiannual',
        anchor: 'calendar',
        enrollmentRequired: false,
        redemptionSteps: [
          'Book a prepaid FHR or The Hotel Collection stay (2-night minimum for Hotel Collection) on AmexTravel.com',
          'Pay with the Business Platinum Card',
        ],
        notes:
          '$600/yr split $300 January-June and $300 July-December. Added in the Sept 2025 refresh.',
      },
      {
        name: 'Dell Technologies Credit (base)',
        description:
          'Up to $150 per calendar year on U.S. purchases directly with Dell Technologies.',
        category: 'shopping',
        icon: 'laptop',
        merchant: 'Dell',
        valueCents: 15000,
        cadence: 'annual',
        anchor: 'calendar',
        enrollmentRequired: true,
        redemptionSteps: [
          'Enroll in the benefit',
          'Buy directly from Dell Technologies (U.S.) with the card',
        ],
        notes:
          'Dell benefit totals up to $1,150/yr: $150 base plus a separate $1,000 credit after $5,000+ Dell spend in the calendar year (split into two entries).',
      },
      {
        name: 'Dell Technologies Credit ($5K spend bonus)',
        description:
          'Additional $1,000 credit after spending $5,000+ with Dell Technologies in a calendar year.',
        category: 'shopping',
        icon: 'laptop',
        merchant: 'Dell',
        valueCents: 100000,
        cadence: 'annual',
        anchor: 'calendar',
        enrollmentRequired: true,
        redemptionSteps: [
          'Enroll in the Dell benefit',
          'Spend $5,000+ on U.S. purchases directly with Dell in the calendar year',
        ],
        notes: 'Conditional on $5,000 Dell spend within the calendar year.',
      },
      {
        name: 'Adobe Credit',
        description: '$250 credit per calendar year after $600+ in U.S. Adobe purchases.',
        category: 'other',
        icon: 'paint-brush',
        merchant: 'Adobe',
        valueCents: 25000,
        cadence: 'annual',
        anchor: 'calendar',
        enrollmentRequired: true,
        redemptionSteps: [
          'Enroll in the benefit',
          'Spend $600+ on U.S. purchases directly with Adobe in the calendar year',
        ],
      },
      {
        name: 'Indeed Credit',
        description: 'Up to $90 back each quarter on Indeed purchases.',
        category: 'other',
        icon: 'briefcase',
        merchant: 'Indeed',
        valueCents: 9000,
        cadence: 'quarterly',
        anchor: 'calendar',
        enrollmentRequired: true,
        redemptionSteps: ['Enroll in the benefit', 'Pay for Indeed services with the card'],
        notes: '$360/yr.',
      },
      {
        name: 'Wireless Credit',
        description: 'Up to $10 back each month on U.S. wireless phone service.',
        category: 'other',
        icon: 'device-mobile',
        valueCents: 1000,
        cadence: 'monthly',
        anchor: 'calendar',
        enrollmentRequired: true,
        redemptionSteps: [
          'Enroll in the benefit',
          'Pay a U.S. wireless provider directly with the card',
        ],
        notes: '$120/yr.',
      },
      {
        name: 'Hilton for Business Credit',
        description: 'Up to $50 back each quarter on eligible purchases directly with Hilton.',
        category: 'lodging',
        icon: 'bed',
        merchant: 'Hilton',
        valueCents: 5000,
        cadence: 'quarterly',
        anchor: 'calendar',
        enrollmentRequired: true,
        redemptionSteps: [
          'Enroll the card in Hilton for Business',
          'Pay directly with a Hilton property with the card',
        ],
        notes: '$200/yr. Requires a Hilton for Business membership.',
      },
      {
        name: 'ChatGPT Business Credit',
        description:
          'Up to $300 per calendar year on U.S. ChatGPT Business subscription purchases.',
        category: 'other',
        icon: 'robot',
        merchant: 'OpenAI',
        valueCents: 30000,
        cadence: 'annual',
        anchor: 'calendar',
        enrollmentRequired: true,
        redemptionSteps: [
          'Enroll in the benefit',
          'Pay for an auto-renewing ChatGPT Business subscription with the card',
        ],
        notes: 'Launched May 12, 2026.',
      },
      {
        name: 'Airline Fee Credit',
        description: 'Up to $200 per calendar year for incidental fees on one selected airline.',
        category: 'airline',
        icon: 'airplane',
        valueCents: 20000,
        cadence: 'annual',
        anchor: 'calendar',
        enrollmentRequired: true,
        redemptionSteps: [
          'Select one qualifying airline in your Amex account',
          'Charge incidental fees with that airline to the card',
        ],
      },
      {
        name: 'CLEAR+ Credit',
        description: 'Up to $219 per calendar year for an auto-renewing CLEAR+ membership.',
        category: 'travel',
        icon: 'fingerprint',
        merchant: 'CLEAR',
        valueCents: 21900,
        cadence: 'annual',
        anchor: 'calendar',
        enrollmentRequired: false,
        redemptionSteps: ['Pay for an auto-renewing CLEAR+ membership with the card'],
        notes: 'Excludes taxes and fees.',
      },
      {
        name: 'Global Entry / TSA PreCheck Credit',
        description:
          'Statement credit for Global Entry ($120) or TSA PreCheck (up to $85) application fee.',
        category: 'fee_credit',
        icon: 'identification-card',
        merchant: 'Global Entry / TSA PreCheck',
        valueCents: 12000,
        cadence: 'manual',
        anchor: 'anniversary',
        enrollmentRequired: false,
        redemptionSteps: ['Pay the Global Entry or TSA PreCheck application fee with the card'],
        notes:
          'Global Entry $120 every 4 years or TSA PreCheck up to $85 every 4.5 years. Rolling interval from last use; no calendar/anniversary reset evidence, so anchor omitted.',
      },
      {
        name: 'Amex Travel Flight Credit ($250K spend unlock)',
        description:
          'Up to $1,200 in credits for flights booked on AmexTravel.com next calendar year, unlocked by $250,000 spend this calendar year.',
        category: 'airline',
        icon: 'suitcase',
        merchant: 'Amex Travel',
        valueCents: 120000,
        cadence: 'annual',
        anchor: 'calendar',
        redemptionSteps: [
          'Spend $250,000 on eligible purchases in a calendar year',
          'In the following calendar year, book flights on AmexTravel.com with the card',
        ],
        notes:
          'High-spend conditional benefit. Enrollment requirement not confirmed in sources, so enrollmentRequired is omitted.',
      },
      {
        name: 'American Express One AP Credit ($250K spend unlock)',
        description:
          'Up to $2,400 in credits on One AP monthly fees next calendar year, unlocked by $250,000 spend this calendar year.',
        category: 'fee_credit',
        icon: 'receipt',
        merchant: 'Amex One AP',
        valueCents: 240000,
        cadence: 'annual',
        anchor: 'calendar',
        redemptionSteps: [
          'Spend $250,000 on eligible purchases in a calendar year',
          'Use American Express One AP in the following calendar year; monthly fees are credited',
        ],
        notes:
          'High-spend conditional benefit. Enrollment requirement not confirmed in sources, so enrollmentRequired is omitted.',
      },
    ],
  },
  {
    id: 'amex-delta-skymiles-reserve',
    issuer: 'American Express',
    product: 'Delta SkyMiles Reserve',
    network: 'amex',
    annualFeeCents: 65000,
    benefits: [
      {
        name: 'Resy Credit',
        description:
          'Up to $20 back each month on eligible purchases at U.S. Resy restaurants (up to $240 per year).',
        category: 'dining',
        icon: 'fork-knife',
        merchant: 'Resy',
        valueCents: 2000,
        cadence: 'monthly',
        anchor: 'calendar',
        enrollmentRequired: true,
        redemptionSteps: [
          'Enroll the card in the Resy credit benefit in your Amex account',
          'Pay at an eligible U.S. Resy restaurant with the Delta Reserve card',
          'Statement credit posts automatically',
        ],
        notes: 'Monthly credit; Upgraded Points describes it as $240 per calendar year.',
      },
      {
        name: 'Rideshare Credit',
        description:
          'Up to $10 back each month on U.S. rideshare purchases with select providers (up to $120 per year).',
        category: 'rideshare',
        icon: 'car',
        valueCents: 1000,
        cadence: 'monthly',
        anchor: 'calendar',
        enrollmentRequired: true,
        redemptionSteps: [
          'Enroll the card in the rideshare credit benefit in your Amex account',
          'Pay for a U.S. ride with a select provider (e.g., Uber, Lyft, Curb, Revel, Alto) using the card',
          'Statement credit posts automatically',
        ],
        notes: 'Eligible providers per Frequent Miler: Uber, Lyft, Curb, Revel, Alto.',
      },
      {
        name: 'Delta Stays Credit',
        description:
          'Up to $200 back per calendar year on prepaid hotels or vacation rentals booked through Delta Stays.',
        category: 'lodging',
        icon: 'bed',
        merchant: 'Delta Stays',
        valueCents: 20000,
        cadence: 'annual',
        anchor: 'calendar',
        enrollmentRequired: false,
        redemptionSteps: [
          'Book a prepaid hotel or vacation rental at delta.com/stays',
          'Pay with the Delta Reserve card (basic or additional card)',
          'Statement credit typically posts within 6-8 weeks',
        ],
        notes:
          'Must be a prepaid booking via Delta Stays; Delta Vacations and direct hotel bookings do not qualify (Upgraded Points).',
      },
      {
        name: 'Global Entry / TSA PreCheck Fee Credit',
        description:
          'Statement credit for the Global Entry ($120) or TSA PreCheck (up to $85) application fee.',
        category: 'fee_credit',
        icon: 'identification-card',
        merchant: 'Global Entry / TSA PreCheck',
        valueCents: 12000,
        cadence: 'manual',
        anchor: 'anniversary',
        enrollmentRequired: false,
        redemptionSteps: [
          'Pay the Global Entry or TSA PreCheck (official enrollment provider) fee with the card',
          'Statement credit posts automatically',
        ],
        notes:
          "Global Entry credit every 4 years ($120); TSA PreCheck up to $85 for a five-year membership through an official enrollment provider. Rolling window from last credit; 'anniversary' used as closest fit.",
      },
    ],
  },
  {
    id: 'amex-gold',
    issuer: 'American Express',
    product: 'Gold',
    network: 'amex',
    annualFeeCents: 32500,
    benefits: [
      {
        name: 'Dining Credit',
        description:
          'Up to $10 back each month at Grubhub/Seamless, Buffalo Wild Wings, Five Guys, The Cheesecake Factory and Wonder.',
        category: 'dining',
        icon: 'fork-knife',
        valueCents: 1000,
        cadence: 'monthly',
        anchor: 'calendar',
        enrollmentRequired: true,
        redemptionSteps: [
          'Enroll in the benefit',
          'Pay with the Gold Card at an eligible dining partner (U.S.)',
        ],
        notes:
          '$120/yr. Buffalo Wild Wings and Wonder added April 30, 2026; Goldbelly and Wine.com removed after June 30, 2026.',
      },
      {
        name: 'Uber Cash',
        description: '$10 in Uber Cash each month for U.S. Uber rides or Uber Eats orders.',
        category: 'rideshare',
        icon: 'car',
        merchant: 'Uber',
        valueCents: 1000,
        cadence: 'monthly',
        anchor: 'calendar',
        enrollmentRequired: true,
        redemptionSteps: [
          'Add the Gold Card to your Uber account',
          'Use Uber Cash on U.S. rides or Uber Eats orders before month end',
        ],
        notes:
          '$120/yr. enrollmentRequired=true because the card must be linked in the Uber app. Unused Uber Cash does not roll over.',
      },
      {
        name: 'Resy Credit',
        description: 'Up to $50 back each half-year at U.S. Resy restaurants.',
        category: 'dining',
        icon: 'fork-knife',
        merchant: 'Resy',
        valueCents: 5000,
        cadence: 'semiannual',
        anchor: 'calendar',
        enrollmentRequired: true,
        redemptionSteps: [
          'Enroll in the benefit',
          'Dine at a qualifying U.S. Resy restaurant and pay with the Gold Card',
        ],
        notes: '$100/yr split as $50 January-June and $50 July-December.',
      },
      {
        name: "Dunkin' Credit",
        description: "Up to $7 back each month at U.S. Dunkin' locations.",
        category: 'dining',
        icon: 'coffee',
        merchant: "Dunkin'",
        valueCents: 700,
        cadence: 'monthly',
        anchor: 'calendar',
        enrollmentRequired: true,
        redemptionSteps: [
          'Enroll in the benefit',
          "Pay with the Gold Card at a U.S. Dunkin' location",
        ],
        notes: '$84/yr.',
      },
    ],
  },
  {
    id: 'amex-hilton-honors-aspire',
    issuer: 'American Express',
    product: 'Hilton Honors Aspire',
    network: 'amex',
    annualFeeCents: 55000,
    benefits: [
      {
        name: 'Hilton Resort Credit',
        description:
          'Up to $200 back each half-year on eligible purchases directly with participating Hilton Resorts.',
        category: 'lodging',
        icon: 'bed',
        merchant: 'Hilton',
        valueCents: 20000,
        cadence: 'semiannual',
        anchor: 'calendar',
        enrollmentRequired: false,
        redemptionSteps: [
          "Stay at a participating Hilton Resort (see Hilton's resort-credit eligible list)",
          'Charge room/incidentals to the room and pay at the property with the Aspire card',
        ],
        notes:
          "$400/yr split $200 January-June and $200 July-December. Nonrefundable/advance-purchase prepaid rates do not count; only properties on Hilton's eligible list trigger the credit.",
      },
      {
        name: 'Flight Credit',
        description:
          'Up to $50 back each quarter on flights booked directly with airlines or via Amex Travel.',
        category: 'airline',
        icon: 'airplane',
        valueCents: 5000,
        cadence: 'quarterly',
        anchor: 'calendar',
        enrollmentRequired: false,
        redemptionSteps: [
          'Buy airfare directly from an airline or on AmexTravel.com with the Aspire card',
        ],
        notes:
          '$200/yr. Quarters are Jan-Mar, Apr-Jun, Jul-Sep, Oct-Dec. Any airline. Anchor and enrollment rely on Upgraded Points (tier 3); Amex page shows no enrollment language; no DoC/FM/USCCG 2026 Aspire page was retrievable.',
      },
      {
        name: 'CLEAR+ Credit',
        description: 'Up to $219 per calendar year toward a CLEAR+ membership.',
        category: 'travel',
        icon: 'fingerprint',
        merchant: 'CLEAR',
        valueCents: 21900,
        cadence: 'annual',
        anchor: 'calendar',
        enrollmentRequired: false,
        redemptionSteps: ['Pay for an auto-renewing CLEAR+ membership with the Aspire card'],
      },
    ],
  },
  {
    id: 'amex-hilton-honors-surpass',
    issuer: 'American Express',
    product: 'Hilton Honors Surpass',
    network: 'amex',
    annualFeeCents: 15000,
    benefits: [
      {
        name: 'Hilton Credit',
        description:
          'Up to $50 back each quarter on purchases made directly with a Hilton portfolio property (up to $200 per year).',
        category: 'lodging',
        icon: 'bed',
        merchant: 'Hilton',
        valueCents: 5000,
        cadence: 'quarterly',
        anchor: 'calendar',
        redemptionSteps: [
          'Book directly with Hilton (hilton.com or app) or charge incidentals to the room at a Hilton property',
          'Pay with the Surpass card',
          'Statement credit posts automatically after the eligible charge',
        ],
        notes:
          "Quarters are Jan-Mar, Apr-Jun, Jul-Sep, Oct-Dec. Third-party bookings do not qualify. Enrollment requirement not found in issuer or secondary sources; field omitted. Issuer page shows no enrollment language (unlike Amex credits it marks 'enrolled'), suggesting none is needed, but this is unconfirmed.",
      },
    ],
  },
  {
    id: 'amex-marriott-bonvoy-brilliant',
    issuer: 'American Express',
    product: 'Marriott Bonvoy Brilliant',
    network: 'amex',
    annualFeeCents: 65000,
    benefits: [
      {
        name: 'Brilliant Dining Credit',
        description:
          'Up to $25 back each month on eligible restaurant purchases worldwide (up to $300 per calendar year).',
        category: 'dining',
        icon: 'fork-knife',
        valueCents: 2500,
        cadence: 'monthly',
        anchor: 'calendar',
        enrollmentRequired: true,
        redemptionSteps: [
          'Enroll the card in the benefit via the Amex account/benefits page if prompted',
          'Pay for an eligible restaurant purchase with the Brilliant card',
          "Statement credit posts automatically; the month is based on the purchase's processed date",
        ],
        notes:
          'Resets each calendar month; $300 annual max per calendar year. Rollover of unused monthly amount is not addressed by sources (assume none). Month assignment is by processing date and credits can take weeks to post (OMAAT).',
      },
      {
        name: 'Global Entry / TSA PreCheck Fee Credit',
        description:
          'Statement credit for the Global Entry ($120) or TSA PreCheck (up to $85) application fee.',
        category: 'fee_credit',
        icon: 'identification-card',
        merchant: 'Global Entry / TSA PreCheck',
        valueCents: 12000,
        cadence: 'manual',
        anchor: 'anniversary',
        enrollmentRequired: false,
        redemptionSteps: [
          'Pay the Global Entry or TSA PreCheck application fee with the Brilliant card',
          'Statement credit posts automatically',
        ],
        notes:
          "One credit per 4-year period for whichever program fee is charged first. $120 for Global Entry; up to $85 for TSA PreCheck. Anchor is a rolling 4-year window from the last credit, not calendar or cardmember year; 'anniversary' used as closest fit.",
      },
    ],
  },
  {
    id: 'amex-platinum',
    issuer: 'American Express',
    product: 'Platinum',
    network: 'amex',
    annualFeeCents: 89500,
    benefits: [
      {
        name: 'Hotel Credit (Fine Hotels + Resorts / The Hotel Collection)',
        description:
          'Up to $300 back on prepaid FHR or Hotel Collection bookings via Amex Travel in each half of the year.',
        category: 'lodging',
        icon: 'bed',
        merchant: 'Amex Travel',
        valueCents: 30000,
        cadence: 'semiannual',
        anchor: 'calendar',
        enrollmentRequired: false,
        redemptionSteps: [
          'Book a prepaid Fine Hotels + Resorts or The Hotel Collection stay on AmexTravel.com or the Amex app',
          'Pay with the Platinum Card',
          'Credit posts to statement; Hotel Collection requires a 2-night minimum',
        ],
        notes:
          '$600/yr total split as $300 January-June and $300 July-December. Represented as one semiannual entry because both halves are equal.',
      },
      {
        name: 'Resy Credit',
        description:
          'Up to $100 back each quarter on eligible Resy purchases (U.S. Resy restaurants).',
        category: 'dining',
        icon: 'fork-knife',
        merchant: 'Resy',
        valueCents: 10000,
        cadence: 'quarterly',
        anchor: 'calendar',
        enrollmentRequired: true,
        redemptionSteps: [
          'Enroll in the benefit in your Amex account',
          'Pay with the Platinum Card at U.S. Resy restaurants or eligible Resy purchases',
        ],
        notes:
          '$400/yr total. Quarters are calendar quarters per Frequent Miler / US Credit Card Guide.',
      },
      {
        name: 'Digital Entertainment Credit',
        description: 'Up to $25 back each month on eligible streaming/news subscriptions.',
        category: 'streaming',
        icon: 'television',
        valueCents: 2500,
        cadence: 'monthly',
        anchor: 'calendar',
        enrollmentRequired: true,
        redemptionSteps: [
          'Enroll in the benefit',
          'Pay for Disney+, ESPN, Hulu, The New York Times, Paramount+, Peacock, Wall Street Journal, YouTube Premium or YouTube TV with the card',
        ],
        notes: '$300/yr total.',
      },
      {
        name: 'lululemon Credit',
        description: 'Up to $75 back each quarter at U.S. lululemon stores and lululemon.com.',
        category: 'shopping',
        icon: 't-shirt',
        merchant: 'lululemon',
        valueCents: 7500,
        cadence: 'quarterly',
        anchor: 'calendar',
        enrollmentRequired: true,
        redemptionSteps: [
          'Enroll in the benefit',
          'Pay with the card at U.S. lululemon retail stores (excluding outlets) or lululemon.com',
        ],
        notes: '$300/yr total.',
      },
      {
        name: 'Uber Cash (monthly)',
        description: '$15 in Uber Cash each month for U.S. Uber rides or Uber Eats orders.',
        category: 'rideshare',
        icon: 'car',
        merchant: 'Uber',
        valueCents: 1500,
        cadence: 'monthly',
        anchor: 'calendar',
        enrollmentRequired: true,
        redemptionSteps: [
          'Add the Platinum Card to your Uber account',
          'Uber Cash deposits monthly; use on U.S. rides or Uber Eats before month end',
        ],
        notes:
          '$200/yr total split as $15 every month plus a $20 December bonus (see separate entry). enrollmentRequired=true because the card must be linked to the Uber account. Unused Uber Cash does not roll over.',
      },
      {
        name: 'Uber Cash (December bonus)',
        description: 'Extra $20 in Uber Cash in December.',
        category: 'rideshare',
        icon: 'car',
        merchant: 'Uber',
        valueCents: 2000,
        cadence: 'annual',
        anchor: 'calendar',
        enrollmentRequired: true,
        redemptionSteps: [
          'Keep the Platinum Card linked to your Uber account',
          'Bonus arrives with December Uber Cash; use by Dec 31',
        ],
        notes:
          'December-only bonus that brings December to $35; split from the $15 monthly entry per spec.',
      },
      {
        name: 'Uber One Membership Credit',
        description:
          'Up to $120 per calendar year in statement credits for an auto-renewing Uber One membership.',
        category: 'rideshare',
        icon: 'car',
        merchant: 'Uber',
        valueCents: 12000,
        cadence: 'annual',
        anchor: 'calendar',
        enrollmentRequired: false,
        redemptionSteps: [
          'Purchase an auto-renewing Uber One membership (monthly or annual) with the Platinum Card',
          'Statement credits post as charged, up to $120 per calendar year',
        ],
        notes: 'Monthly Uber One billing is reimbursed as charged; cap is annual.',
      },
      {
        name: 'Walmart+ Membership Credit',
        description: 'Statement credit covering a monthly Walmart+ membership.',
        category: 'shopping',
        icon: 'storefront',
        merchant: 'Walmart',
        valueCents: 1295,
        cadence: 'monthly',
        anchor: 'calendar',
        enrollmentRequired: false,
        redemptionSteps: [
          'Pay for a monthly Walmart+ membership with the Platinum Card',
          'Credit posts each month',
        ],
        notes:
          'Amex page states up to $12.95 per month (asterisked, plus applicable taxes per Frequent Miler); annual Walmart+ plans do not qualify. Value excludes tax.',
      },
      {
        name: 'Airline Fee Credit',
        description: 'Up to $200 per calendar year for incidental fees on one selected airline.',
        category: 'airline',
        icon: 'airplane',
        valueCents: 20000,
        cadence: 'annual',
        anchor: 'calendar',
        enrollmentRequired: true,
        redemptionSteps: [
          'Select one qualifying airline in your Amex account',
          'Charge incidental fees (bags, seat fees, lounge day passes, etc.) with that airline to the card',
        ],
        notes: 'Airfare itself is not eligible.',
      },
      {
        name: 'Oura Ring Credit',
        description: 'Up to $200 per calendar year on Oura Ring purchases at ouraring.com.',
        category: 'wellness',
        icon: 'heartbeat',
        merchant: 'Oura',
        valueCents: 20000,
        cadence: 'annual',
        anchor: 'calendar',
        enrollmentRequired: true,
        redemptionSteps: [
          'Enroll in the benefit',
          'Buy an Oura Ring at ouraring.com with the Platinum Card',
        ],
        notes: 'Applies to ring hardware purchases.',
      },
      {
        name: 'Equinox Credit',
        description: 'Up to $300 per calendar year on Equinox club or Equinox+ digital membership.',
        category: 'wellness',
        icon: 'barbell',
        merchant: 'Equinox',
        valueCents: 30000,
        cadence: 'annual',
        anchor: 'calendar',
        enrollmentRequired: true,
        redemptionSteps: [
          'Enroll in the benefit',
          'Pay for an Equinox club or Equinox+ membership with the card',
        ],
      },
      {
        name: 'CLEAR+ Credit',
        description: 'Up to $219 per calendar year toward a CLEAR+ membership.',
        category: 'travel',
        icon: 'fingerprint',
        merchant: 'CLEAR',
        valueCents: 21900,
        cadence: 'annual',
        anchor: 'calendar',
        enrollmentRequired: false,
        redemptionSteps: ['Sign up for CLEAR+ and pay with the Platinum Card'],
      },
      {
        name: 'Global Entry / TSA PreCheck Credit',
        description:
          'Statement credit for Global Entry ($120) or TSA PreCheck (up to $85) application fee.',
        category: 'fee_credit',
        icon: 'identification-card',
        merchant: 'Global Entry / TSA PreCheck',
        valueCents: 12000,
        cadence: 'manual',
        anchor: 'anniversary',
        enrollmentRequired: false,
        redemptionSteps: [
          'Pay the Global Entry or TSA PreCheck application fee with the Platinum Card',
        ],
        notes:
          'Global Entry $120 once every 4 years, or TSA PreCheck up to $85 (five-year membership) once every 4.5 years. valueCents is the max (Global Entry). Interval is rolling from last use; no calendar/anniversary reset evidence, so anchor omitted.',
      },
    ],
  },
  {
    id: 'bofa-premium-rewards-elite',
    issuer: 'Bank of America',
    product: 'Premium Rewards Elite',
    network: 'visa',
    annualFeeCents: 55000,
    benefits: [
      {
        name: 'Airline Incidental Credit',
        description:
          'Up to $300 per calendar year in statement credits for airline incidentals like seat upgrades, bag fees, lounge fees and in-flight services.',
        category: 'airline',
        icon: 'airplane',
        valueCents: 30000,
        cadence: 'annual',
        anchor: 'calendar',
        enrollmentRequired: false,
        redemptionSteps: [
          'Pay for qualifying airline incidentals (seat upgrades, bags, lounge fees, in-flight) with the card',
          'Statement credit posts automatically',
        ],
        notes: 'No airline selection step reported. Airfare itself generally not eligible.',
      },
      {
        name: 'Lifestyle Credit',
        description:
          'Up to $150 per calendar year in statement credits for streaming, food delivery, fitness subscriptions and rideshare.',
        category: 'other',
        icon: 'sparkle',
        valueCents: 15000,
        cadence: 'annual',
        anchor: 'calendar',
        enrollmentRequired: false,
        redemptionSteps: [
          'Pay qualifying merchants (e.g. Netflix, Hulu, DoorDash, Uber, Lyft, Peloton) with the card',
          'Statement credit posts in about 2-3 weeks',
        ],
        notes:
          'Eligibility is by merchant category code (4899, 5399, 5411, 5422, 5499, 5691, 5734, 5815-5818, 5921, 5940, 5964, 5968-5969, 5999, 7032, 7299, 7372, 7841, 7997, 7999). Some merchants (Spotify, Instacart) reported not to trigger.',
      },
      {
        name: 'Global Entry / TSA PreCheck Credit',
        description:
          'Up to $120 in statement credits for a Global Entry or TSA PreCheck application fee.',
        category: 'fee_credit',
        icon: 'identification-card',
        merchant: 'Global Entry / TSA PreCheck',
        valueCents: 12000,
        cadence: 'manual',
        anchor: 'anniversary',
        enrollmentRequired: false,
        redemptionSteps: [
          'Pay the Global Entry or TSA PreCheck application fee with the card',
          'Statement credit posts automatically',
        ],
        notes: 'Once every four years.',
      },
    ],
  },
  {
    id: 'capital-one-venture-x',
    issuer: 'Capital One',
    product: 'Venture X',
    network: 'visa',
    annualFeeCents: 39500,
    benefits: [
      {
        name: 'Capital One Travel Credit',
        description:
          '$300 annual credit for bookings made through Capital One Travel, applied at checkout.',
        category: 'travel',
        icon: 'suitcase',
        merchant: 'Capital One Travel',
        valueCents: 30000,
        cadence: 'annual',
        anchor: 'anniversary',
        enrollmentRequired: false,
        redemptionSteps: [
          'Book flights, hotels, or rental cars through Capital One Travel with the Venture X card.',
          'Select the travel credit at checkout; it can be split across multiple purchases.',
          'Use before the next account-open anniversary, when unused credit expires.',
        ],
        notes:
          "Since Sept 2023 it works as a checkout credit rather than a post-purchase statement credit; no miles earned on the credited portion; restored if a refundable booking is cancelled before expiry (Doctor of Credit). Capital One's own pages say 'annual' without naming the reset date.",
      },
      {
        name: 'Global Entry / TSA PreCheck Credit',
        description:
          'Statement credit up to $120 for a Global Entry or TSA PreCheck application fee, once every four years.',
        category: 'fee_credit',
        icon: 'identification-card',
        merchant: 'Global Entry / TSA PreCheck',
        valueCents: 12000,
        cadence: 'manual',
        anchor: 'anniversary',
        enrollmentRequired: false,
        redemptionSteps: [
          'Pay the Global Entry or TSA PreCheck application fee with the Venture X card.',
          'Statement credit posts automatically.',
        ],
        notes:
          'Interval: once every 4 years, per Frequent Miler; the Capital One article excerpt stated the $120 amount but not the interval. Anchor omitted.',
      },
    ],
  },
  {
    id: 'chase-ihg-one-rewards-premier',
    issuer: 'Chase',
    product: 'IHG One Rewards Premier',
    network: 'mastercard',
    annualFeeCents: 9900,
    benefits: [
      {
        name: 'United TravelBank Cash',
        description:
          '$25 in United TravelBank cash twice a year (up to $50 per calendar year) after registering the card with MileagePlus.',
        category: 'airline',
        icon: 'airplane',
        merchant: 'United',
        valueCents: 2500,
        cadence: 'semiannual',
        anchor: 'calendar',
        enrollmentRequired: true,
        redemptionSteps: [
          'Register the IHG Premier card with your MileagePlus account (Chase/United registration page).',
          'Receive $25 TravelBank cash deposits around January 5 and July 5.',
          'Apply TravelBank cash when booking on united.com or the United app.',
        ],
        notes:
          'Chase card page gives deposit dates of Jan 5 and Jul 5; Doctor of Credit (2022 launch post) said around Jan 1 / Jul 1. DoC reports each deposit expires at the end of its six-month window; not confirmed on issuer page.',
      },
      {
        name: '$20K Spend Statement Credit',
        description:
          '$100 statement credit (plus 10,000 bonus points) in each calendar year you spend $20,000 on the card.',
        category: 'other',
        icon: 'tag',
        valueCents: 10000,
        cadence: 'annual',
        anchor: 'calendar',
        enrollmentRequired: false,
        redemptionSteps: [
          'Spend at least $20,000 on purchases in a calendar year.',
          'The $100 statement credit and 10,000 bonus points post automatically.',
        ],
        notes:
          'Spend-conditional: only earned after $20,000 in calendar-year purchases. Included because it is a recurring dollar statement credit; downstream consumers may want to treat it separately from unconditional credits.',
      },
      {
        name: 'Global Entry / TSA PreCheck / NEXUS Credit',
        description:
          'Statement credit up to $120 for a Global Entry, TSA PreCheck, or NEXUS application fee once every four years.',
        category: 'fee_credit',
        icon: 'identification-card',
        merchant: 'Global Entry / TSA PreCheck',
        valueCents: 12000,
        cadence: 'manual',
        anchor: 'anniversary',
        enrollmentRequired: false,
        redemptionSteps: [
          'Pay the application fee with the IHG Premier card.',
          'Statement credit posts automatically (one every four years).',
        ],
        notes:
          'Interval: once every 4 years. Anchor omitted (no calendar/anniversary reset stated).',
      },
    ],
  },
  {
    id: 'chase-sapphire-preferred',
    issuer: 'Chase',
    product: 'Sapphire Preferred',
    network: 'visa',
    annualFeeCents: 9500,
    benefits: [
      {
        name: 'Chase Travel Hotel Credit',
        description:
          'Up to $100 in statement credits each account anniversary year on hotel stays booked through Chase Travel.',
        category: 'lodging',
        icon: 'bed',
        merchant: 'Chase Travel',
        valueCents: 10000,
        cadence: 'annual',
        anchor: 'anniversary',
        enrollmentRequired: false,
        redemptionSteps: [
          'Book a hotel stay through Chase Travel (chase.com or the Chase app).',
          'Pay with the Sapphire Preferred card; the statement credit posts automatically up to $100 per anniversary year.',
        ],
        notes:
          'Increased from $50 to $100 effective June 15, 2026 for new and existing cardmembers (Chase press release). For bookings made on/after 6/15/2026, the credit is clawed back if the reservation is cancelled (Doctor of Credit, 2026-06-20).',
      },
      {
        name: 'DoorDash Non-Restaurant Monthly Promo',
        description:
          'Up to $10 off one non-restaurant DoorDash order (grocery, convenience, retail) each calendar month for cardmembers with the complimentary DashPass.',
        category: 'shopping',
        icon: 'moped',
        merchant: 'DoorDash',
        valueCents: 1000,
        cadence: 'monthly',
        anchor: 'calendar',
        enrollmentRequired: true,
        redemptionSteps: [
          'Activate the complimentary DashPass with the Sapphire Preferred card (activation deadline 12/31/2027).',
          'Each month, place one qualifying non-restaurant DoorDash order paid with the card.',
          'Select the $10 discount from the DoorDash promotion wallet at checkout.',
        ],
        notes:
          'Applied as a checkout discount in DoorDash, not a Chase statement credit. Single-use per month; unused remainder is forfeited and does not roll over. Frequent Miler (2026-04-17) reports a $20 minimum order; that minimum was not visible in the Chase terms excerpt reviewed. Complimentary DashPass membership itself is listed under nonCreditPerks.',
      },
      {
        name: 'Global Entry / TSA PreCheck / NEXUS Credit',
        description:
          'Statement credit up to $120 for a Global Entry, TSA PreCheck, or NEXUS application fee once every four years.',
        category: 'fee_credit',
        icon: 'identification-card',
        merchant: 'Global Entry / TSA PreCheck',
        valueCents: 12000,
        cadence: 'manual',
        anchor: 'anniversary',
        enrollmentRequired: false,
        redemptionSteps: [
          'Pay the Global Entry, TSA PreCheck, or NEXUS application fee with the Sapphire Preferred card.',
          'Statement credit posts automatically (one credit every four years).',
        ],
        notes:
          'New benefit added in the June 15, 2026 refresh. Interval: once every 4 years. Anchor omitted: the issuer ties the 4-year window to the prior credit and states no calendar or anniversary reset.',
      },
    ],
  },
  {
    id: 'chase-sapphire-reserve',
    issuer: 'Chase',
    product: 'Sapphire Reserve',
    network: 'visa',
    annualFeeCents: 79500,
    benefits: [
      {
        name: 'Annual Travel Credit',
        description:
          'Up to $300 in statement credits for travel purchases each account anniversary year.',
        category: 'travel',
        icon: 'suitcase',
        valueCents: 30000,
        cadence: 'annual',
        anchor: 'anniversary',
        enrollmentRequired: false,
        redemptionSteps: [
          'Charge any travel purchase to the card',
          'Statement credits post automatically until $300 is reached for the account anniversary year',
        ],
        notes: 'Broad travel category; applies automatically.',
      },
      {
        name: 'The Edit Hotel Credit',
        description:
          'Up to $250 back on each prepaid The Edit booking via Chase Travel (2-night minimum), up to $500 per calendar year.',
        category: 'lodging',
        icon: 'bed',
        merchant: 'The Edit',
        valueCents: 50000,
        cadence: 'annual',
        anchor: 'calendar',
        enrollmentRequired: false,
        redemptionSteps: [
          'Book a prepaid stay of at least 2 nights at a property in The Edit through Chase Travel',
          'Pay with the Sapphire Reserve card',
          'Receive up to $250 statement credit per booking, maximum two bookings/$500 per calendar year',
        ],
        notes:
          'Since 1/1/2026 the two $250 credits can be used any time in the calendar year (previously split Jan-Jun and Jul-Dec). Per-booking cap is $250, so $500 requires two separate prepaid bookings.',
      },
      {
        name: 'Dining Credit (Sapphire Reserve Exclusive Tables)',
        description:
          'Up to $150 back for dining at Sapphire Reserve Exclusive Tables restaurants on OpenTable, January through June.',
        category: 'dining',
        icon: 'fork-knife',
        merchant: 'OpenTable',
        valueCents: 15000,
        cadence: 'semiannual',
        anchor: 'calendar',
        enrollmentRequired: true,
        redemptionSteps: [
          'Link/enroll the card with OpenTable to access Sapphire Reserve Exclusive Tables',
          'Dine at a participating Exclusive Tables restaurant and pay with the card',
          'Statement credit posts, typically within days (up to about 4 weeks)',
        ],
        notes: 'Unused amount does not carry into the second half.',
      },
      {
        name: 'StubHub / viagogo Credit',
        description: 'Up to $150 back on StubHub and viagogo purchases, January through June.',
        category: 'entertainment',
        icon: 'ticket',
        merchant: 'StubHub',
        valueCents: 15000,
        cadence: 'semiannual',
        anchor: 'calendar',
        enrollmentRequired: true,
        redemptionSteps: [
          'Activate the benefit once on Chase.com or the Chase Mobile app',
          'Buy tickets on StubHub or viagogo with the card',
          'Statement credit posts automatically',
        ],
        notes: 'Benefit available through 12/31/2027.',
      },
      {
        name: 'DoorDash Restaurant Promo',
        description: '$5 off one qualifying DoorDash restaurant order each calendar month.',
        category: 'dining',
        icon: 'moped',
        merchant: 'DoorDash',
        valueCents: 500,
        cadence: 'monthly',
        anchor: 'calendar',
        enrollmentRequired: true,
        redemptionSteps: [
          'Activate complimentary DashPass with the Sapphire Reserve card (by 12/31/2027)',
          'Pay with the card on a qualifying DoorDash restaurant order',
          'Discount applies at checkout',
        ],
        notes:
          'In-app promo (discount at checkout), not a statement credit. Available through 12/31/2027. Part of the $25/month DoorDash promo package ($5 restaurant + two $10 non-restaurant).',
      },
      {
        name: 'DoorDash Non-Restaurant Promos',
        description:
          'Two $10-off discounts each calendar month on non-restaurant (grocery, retail) DoorDash orders.',
        category: 'shopping',
        icon: 'moped',
        merchant: 'DoorDash',
        valueCents: 2000,
        cadence: 'monthly',
        anchor: 'calendar',
        enrollmentRequired: true,
        redemptionSteps: [
          'Activate complimentary DashPass with the Sapphire Reserve card (by 12/31/2027)',
          'Place a qualifying non-restaurant DoorDash order (grocery, retail) with the card',
          'Each $10 discount applies at checkout; two per calendar month',
        ],
        notes:
          'valueCents = two $10 promos combined ($20/month); each promo is a separate $10 discount on a separate order. Order minimums were not confirmed. Available through 12/31/2027.',
      },
      {
        name: 'Lyft Credit',
        description: '$10 Lyft in-app credit each calendar month.',
        category: 'rideshare',
        icon: 'car',
        merchant: 'Lyft',
        valueCents: 1000,
        cadence: 'monthly',
        anchor: 'calendar',
        enrollmentRequired: true,
        redemptionSteps: [
          'Add the Sapphire Reserve card as a payment method in the Lyft app',
          'The $10 in-app credit is issued each calendar month and applied to rides',
        ],
        notes:
          'In-app credit, not a statement credit. Available through 9/30/2027. Marked enrollmentRequired because the card must be linked in the Lyft app.',
      },
      {
        name: 'Peloton Membership Credit',
        description: 'Up to $10 in statement credits per month on eligible Peloton memberships.',
        category: 'wellness',
        icon: 'bicycle',
        merchant: 'Peloton',
        valueCents: 1000,
        cadence: 'monthly',
        anchor: 'calendar',
        enrollmentRequired: true,
        redemptionSteps: [
          'Activate once at onepeloton.com/digital/promotions/chase',
          'Pay for an eligible Peloton membership with the Sapphire Reserve card',
          'Credit posts monthly, up to $10',
        ],
        notes:
          "Available through 12/31/2027; max $120 per year. Calendar-month anchor inferred from 'per month' language, not explicitly stated.",
      },
      {
        name: 'Global Entry / TSA PreCheck / NEXUS Fee Credit',
        description: 'One statement credit of up to $120 every four years for the application fee.',
        category: 'fee_credit',
        icon: 'identification-card',
        merchant: 'Global Entry / TSA PreCheck',
        valueCents: 12000,
        cadence: 'manual',
        anchor: 'anniversary',
        enrollmentRequired: false,
        redemptionSteps: [
          'Pay the Global Entry, TSA PreCheck or NEXUS application fee with the card',
          'Statement credit posts automatically',
        ],
        notes:
          "Once every 4 years. Rolling window from the last credit; 'anniversary' used as closest fit.",
      },
    ],
  },
  {
    id: 'chase-united-quest',
    issuer: 'Chase',
    product: 'United Quest',
    network: 'visa',
    annualFeeCents: 35000,
    benefits: [
      {
        name: 'United TravelBank Cash',
        description:
          '$200 in United TravelBank cash after account opening and on each account anniversary, for United- or United Express-operated flights.',
        category: 'airline',
        icon: 'airplane',
        merchant: 'United',
        valueCents: 20000,
        cadence: 'annual',
        anchor: 'anniversary',
        enrollmentRequired: false,
        redemptionSteps: [
          'TravelBank cash is deposited automatically into the linked MileagePlus account after account opening and each anniversary.',
          'Apply TravelBank cash at checkout when booking a United- or United Express-operated flight on united.com or the United app.',
        ],
        notes:
          'Deposited as TravelBank cash, not a statement credit. Frequent Miler reports it expires 12 months after deposit (not confirmed on issuer page).',
      },
      {
        name: 'Renowned Hotels and Resorts Credit',
        description:
          "Up to $150 back each anniversary year on hotel stays prepaid through United's Renowned Hotels and Resorts program.",
        category: 'lodging',
        icon: 'bed',
        merchant: 'United Hotels',
        valueCents: 15000,
        cadence: 'annual',
        anchor: 'anniversary',
        enrollmentRequired: false,
        redemptionSteps: [
          'Book and prepay a stay directly through Renowned Hotels and Resorts with the United Quest card.',
          'Statement credit posts up to $150 per anniversary year.',
        ],
      },
      {
        name: 'JSX Credit',
        description:
          'Up to $150 back as a statement credit each anniversary year on flights booked directly with JSX.',
        category: 'airline',
        icon: 'airplane-tilt',
        merchant: 'JSX',
        valueCents: 15000,
        cadence: 'annual',
        anchor: 'anniversary',
        enrollmentRequired: false,
        redemptionSteps: [
          'Book JSX flights directly with JSX (jsx.com or app) using the United Quest card.',
          'Statement credit posts up to $150 per anniversary year.',
        ],
      },
      {
        name: 'Avis/Budget Rental TravelBank Credit',
        description:
          '$40 in United TravelBank cash for each of the first two Avis or Budget rentals per anniversary year (up to $80).',
        category: 'travel',
        icon: 'car-profile',
        merchant: 'Avis Budget',
        valueCents: 8000,
        cadence: 'annual',
        anchor: 'anniversary',
        enrollmentRequired: false,
        redemptionSteps: [
          'Book an Avis or Budget rental through cars.united.com and pay with the United Quest card.',
          'Receive $40 in United TravelBank cash for each of the 1st and 2nd rentals in the anniversary year.',
        ],
        notes:
          'Released as two $40 TravelBank deposits (one per rental), capped at $80 per anniversary year; valueCents is the annual cap. Frequent Miler notes a 2-day minimum rental; not confirmed on issuer page.',
      },
      {
        name: 'Rideshare Credit (monthly base)',
        description: 'Up to $8 back each month on rideshare purchases after annual enrollment.',
        category: 'rideshare',
        icon: 'car',
        valueCents: 800,
        cadence: 'monthly',
        anchor: 'calendar',
        enrollmentRequired: true,
        redemptionSteps: [
          'Enroll in the rideshare benefit via Chase (required each calendar year).',
          'Pay for eligible rideshare with the United Quest card; up to $8 statement credit per month.',
        ],
        notes:
          'Uneven schedule split per spec: Chase gives $8/month Jan-Nov and up to $12 in December ($100/calendar year). Modeled as $8 monthly (all 12 months) plus a separate $4 December top-up entry. Credits begin the month after enrollment, so re-enroll early each January (Frequent Miler).',
      },
      {
        name: 'Rideshare Credit (December top-up)',
        description:
          'Extra $4 rideshare credit in December (December cap is $12 vs. $8 in other months).',
        category: 'rideshare',
        icon: 'car',
        valueCents: 400,
        cadence: 'annual',
        anchor: 'calendar',
        enrollmentRequired: true,
        redemptionSteps: [
          'Stay enrolled in the rideshare benefit for the calendar year.',
          'In December, spend up to $12 on eligible rideshare with the card; the $4 above the $8 base comes from this entry.',
        ],
        notes:
          'Companion to the $8 monthly entry; together they total $100 per calendar year ($8 x 11 + $12).',
      },
      {
        name: 'Instacart $10 Monthly Credit',
        description:
          '$10 Instacart credit on the first order each month for Instacart+ members paying with the card.',
        category: 'shopping',
        icon: 'shopping-cart',
        merchant: 'Instacart',
        valueCents: 1000,
        cadence: 'monthly',
        anchor: 'calendar',
        enrollmentRequired: true,
        redemptionSteps: [
          "Register the United Quest card on Instacart's Chase United page and activate the complimentary Instacart+ (3 months, then 50% off renewal).",
          'Keep an active Instacart+ membership and set the card as payment or backup payment.',
          'The $10 credit applies to the first order each month.',
        ],
        notes:
          'Split from the $10 + $5 monthly structure ($180/calendar year total). Requires active Instacart+ membership. Benefits end 12/31/2027. Credit applied in Instacart, not as a Chase statement credit.',
      },
      {
        name: 'Instacart $5 Monthly Credit',
        description:
          '$5 Instacart credit on the second order each month for Instacart+ members paying with the card.',
        category: 'shopping',
        icon: 'shopping-cart',
        merchant: 'Instacart',
        valueCents: 500,
        cadence: 'monthly',
        anchor: 'calendar',
        enrollmentRequired: true,
        redemptionSteps: [
          'Same setup as the $10 credit (registered card, active Instacart+).',
          'The $5 credit applies to the second order each month.',
        ],
        notes: 'Second half of the $10 + $5 monthly Instacart benefit. Benefits end 12/31/2027.',
      },
      {
        name: 'Global Entry / TSA PreCheck / NEXUS Credit',
        description:
          'Statement credit up to $120 for a Global Entry, TSA PreCheck, or NEXUS application fee once every four years.',
        category: 'fee_credit',
        icon: 'identification-card',
        merchant: 'Global Entry / TSA PreCheck',
        valueCents: 12000,
        cadence: 'manual',
        anchor: 'anniversary',
        enrollmentRequired: false,
        redemptionSteps: [
          'Pay the application fee with the United Quest card.',
          'Statement credit posts automatically (one every four years).',
        ],
        notes:
          'Interval: once every 4 years. Anchor omitted (no calendar/anniversary reset stated).',
      },
    ],
  },
  {
    id: 'citi-aadvantage-executive',
    issuer: 'Citi',
    product: 'AAdvantage Executive',
    network: 'mastercard',
    annualFeeCents: 69500,
    benefits: [
      {
        name: 'Lyft Credit',
        description:
          '$15 Lyft credit after taking 3 eligible Lyft rides paid with the card in a calendar month (up to $180/yr).',
        category: 'rideshare',
        icon: 'car',
        merchant: 'Lyft',
        valueCents: 1500,
        cadence: 'monthly',
        anchor: 'calendar',
        enrollmentRequired: true,
        redemptionSteps: [
          'Add the card as payment method in the Lyft app',
          'Take 3 eligible rides paid with the card in a calendar month',
          'Receive a $15 Lyft credit in the Lyft account (expires ~30 days after issue)',
        ],
        notes:
          'Increased from $10 to $15 per month on Aug 23, 2026. This is a Lyft in-app credit, not a statement credit. Enrollment=true reflects the need to link/add the card in the Lyft account.',
      },
      {
        name: 'Avis / Budget Car Rental Credit',
        description:
          'Up to $120 back per calendar year on eligible prepaid Avis or Budget rentals booked directly.',
        category: 'travel',
        icon: 'car-profile',
        merchant: 'Avis Budget',
        valueCents: 12000,
        cadence: 'annual',
        anchor: 'calendar',
        enrollmentRequired: false,
        redemptionSteps: [
          'Book a prepaid rental directly on avis.com or budget.com',
          'Pay with the card; statement credit posts afterward',
        ],
        notes: 'Pay-later bookings and third-party bookings (including aa.com/cars) are excluded.',
      },
      {
        name: 'American Airlines Vacations Credit',
        description:
          'Up to $250 back per half-year ($500/yr) on eligible American Airlines Vacations package purchases.',
        category: 'travel',
        icon: 'island',
        merchant: 'American Airlines Vacations',
        valueCents: 25000,
        cadence: 'semiannual',
        anchor: 'calendar',
        enrollmentRequired: false,
        redemptionSteps: [
          'Book a package with 2+ components (e.g. flight + hotel) on aavacations.com',
          'Pay with the card; statement credit posts automatically',
        ],
        notes:
          'New Aug 23, 2026. Even split: up to $250 Jan-Jun and up to $250 Jul-Dec; unused amounts do not roll over.',
      },
      {
        name: 'Inflight & Admirals Club Credit',
        description:
          'Up to $100 back per calendar year on American Airlines inflight purchases and eligible Admirals Club purchases.',
        category: 'airline',
        icon: 'airplane',
        merchant: 'American Airlines',
        valueCents: 10000,
        cadence: 'annual',
        anchor: 'calendar',
        enrollmentRequired: false,
        redemptionSteps: [
          'Pay for AA inflight food/beverage/Wi-Fi or eligible Admirals Club purchases with the card',
          'Statement credit posts automatically',
        ],
        notes:
          'New Aug 23, 2026; replaces the 25% inflight food/beverage savings (which existing members keep through Sep 30, 2026).',
      },
      {
        name: 'Grubhub Credit (existing cardmembers only)',
        description:
          'Up to $10 per monthly billing statement on eligible Grubhub purchases; legacy benefit being phased out.',
        category: 'dining',
        icon: 'hamburger',
        merchant: 'Grubhub',
        valueCents: 1000,
        cadence: 'monthly',
        anchor: 'calendar',
        enrollmentRequired: false,
        redemptionSteps: [
          'Pay for Grubhub orders with the card',
          'Statement credit up to $10 per billing statement posts automatically',
        ],
        notes:
          'Removed in the Aug 23, 2026 refresh for new cardmembers; existing cardmembers retain it through Aug 31, 2027 (TPG). Terms tie it to monthly billing statements, so anchor is billing-cycle based and left out.',
      },
      {
        name: 'Global Entry / TSA PreCheck Credit',
        description:
          'Up to $120 statement credit for a Global Entry or TSA PreCheck application fee.',
        category: 'fee_credit',
        icon: 'identification-card',
        merchant: 'Global Entry / TSA PreCheck',
        valueCents: 12000,
        cadence: 'manual',
        anchor: 'anniversary',
        enrollmentRequired: false,
        redemptionSteps: [
          'Pay the Global Entry or TSA PreCheck application fee with the card',
          'Credit posts within 1-2 billing cycles',
        ],
        notes: 'One credit per account every 4 years (per Citi).',
      },
    ],
  },
  {
    id: 'citi-strata-elite',
    issuer: 'Citi',
    product: 'Strata Elite',
    network: 'mastercard',
    annualFeeCents: 59500,
    benefits: [
      {
        name: 'Hotel Benefit',
        description: 'Up to $300 off a hotel stay of 2+ nights booked through Citi Travel.',
        category: 'lodging',
        icon: 'bed',
        merchant: 'Citi Travel',
        valueCents: 30000,
        cadence: 'annual',
        anchor: 'calendar',
        enrollmentRequired: false,
        redemptionSteps: [
          'Book a hotel stay of 2 or more nights on cititravel.com',
          'Pay with the Strata Elite card; discount/credit applies to the booking',
        ],
        notes:
          'Minimum 2-night stay. Applied via the Citi Travel portal rather than as a merchant-agnostic statement credit.',
      },
      {
        name: 'Splurge Credit',
        description:
          'Up to $200 in statement credits at up to 2 selected brands: 1stDibs, American Airlines, Best Buy, Future Personal Training, Live Nation.',
        category: 'shopping',
        icon: 'shopping-bag',
        valueCents: 20000,
        cadence: 'annual',
        anchor: 'calendar',
        enrollmentRequired: true,
        redemptionSteps: [
          'Log in to Citi account and open the Splurge Credit dashboard',
          "Click 'Select brand' and choose up to 2 of the 5 eligible brands",
          'Pay at the selected brand(s) with the card; credit posts within 1-2 billing cycles',
        ],
        notes:
          'Brands must be selected before purchase; selections can be changed online or by phone. Exclusions apply for American Airlines and Live Nation.',
      },
      {
        name: 'Blacklane Credit',
        description:
          'Up to $100 per half-year ($200/yr) in statement credits for Blacklane chauffeur rides.',
        category: 'rideshare',
        icon: 'car',
        merchant: 'Blacklane',
        valueCents: 10000,
        cadence: 'semiannual',
        anchor: 'calendar',
        enrollmentRequired: false,
        redemptionSteps: [
          'Book a Blacklane ride and pay with the Strata Elite card',
          'Statement credit posts automatically (often at statement close)',
        ],
        notes:
          'Even split: up to $100 Jan-Jun and up to $100 Jul-Dec, so recorded as one semiannual entry. Charge posts after the ride is completed, which determines which half it counts toward.',
      },
      {
        name: 'Global Entry / TSA PreCheck Credit',
        description: 'Up to $120 reimbursement for a Global Entry or TSA PreCheck application fee.',
        category: 'fee_credit',
        icon: 'identification-card',
        merchant: 'Global Entry / TSA PreCheck',
        valueCents: 12000,
        cadence: 'manual',
        anchor: 'anniversary',
        enrollmentRequired: false,
        redemptionSteps: [
          'Pay the Global Entry or TSA PreCheck application fee with the card',
          'Statement credit posts automatically',
        ],
        notes: 'Available once every 4 years. Anchor not applicable (interval-based).',
      },
    ],
  },
  {
    id: 'wells-fargo-autograph-journey',
    issuer: 'Wells Fargo',
    product: 'Autograph Journey',
    network: 'visa',
    annualFeeCents: 9500,
    benefits: [
      {
        name: 'Annual Airline Credit',
        description:
          'One-time $50 statement credit on the first airline purchase of at least $50 each card year.',
        category: 'airline',
        icon: 'airplane',
        valueCents: 5000,
        cadence: 'annual',
        anchor: 'anniversary',
        enrollmentRequired: false,
        redemptionSteps: [
          'Make an airline purchase of $50 or more with the card (airline merchant category)',
          'Credit posts within 60 days',
        ],
        notes:
          'First year available at account opening; thereafter the 12-month period begins the first day of the month after the annual fee is assessed (e.g. fee Nov 10 -> period starts Dec 1). Anniversary-like, offset to month start.',
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
