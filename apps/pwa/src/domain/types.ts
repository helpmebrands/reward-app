/**
 * Core domain types for HelpMe Reward.
 *
 * The shape follows the design's premise: this is a *household* deadline
 * manager. The hard case is not two different cards with clashing offers — it
 * is the same card held twice by two people, where every credit exists twice
 * and a single booking cannot draw on both.
 *
 * Dates are calendar dates (`YYYY-MM-DD`), not timestamps: "September 2026" is
 * a calendar concept and must not shift when the user crosses a timezone.
 * Instants (when a claim was recorded) use full ISO-8601 strings.
 */

/** A calendar date, `YYYY-MM-DD`. */
export type IsoDate = string

/** An instant, ISO-8601 with timezone, e.g. `2026-09-16T14:03:00.000Z`. */
export type IsoInstant = string

export type Uuid = string

/**
 * How often a credit refreshes.
 *
 * `manual` covers credits no cycle can track — Global Entry every four to four
 * and a half years — which are listed but never counted as at risk.
 */
export type Cadence = 'monthly' | 'quarterly' | 'semiannual' | 'annual' | 'manual'

/**
 * What a recurring cycle is measured from.
 * - `calendar`: the Gregorian calendar (Jan 1, quarter starts, month starts).
 * - `anniversary`: the card's account anniversary — the "cardmember year".
 *
 * Getting this wrong is the commonest way people lose a credit, so it is
 * recorded per benefit rather than inferred from the cadence.
 */
export type CycleAnchor = 'calendar' | 'anniversary'

export type BenefitCategory =
  | 'travel'
  | 'dining'
  | 'shopping'
  | 'entertainment'
  | 'rideshare'
  | 'wellness'
  | 'lodging'
  | 'airline'
  | 'streaming'
  | 'fee_credit'
  | 'other'

export type CardNetwork = 'amex' | 'visa' | 'mastercard' | 'discover' | 'other'

export interface Card {
  id: Uuid
  /** e.g. "American Express". */
  issuer: string
  /** e.g. "Platinum". */
  product: string
  /**
   * Who in the household holds this card. Two people holding the same product
   * is the case the app exists for, so this is what distinguishes them.
   */
  holder: string
  /** User-supplied label that wins over `issuer product` in the UI. */
  nickname?: string
  network: CardNetwork
  /** Display only; never a full PAN. */
  last4?: string
  annualFeeCents: number
  /**
   * Account open / renewal date. Anchors `anniversary` cycles and the annual
   * fee countdown. Only the month and day matter for recurrence.
   */
  anniversaryOn: IsoDate
  /** Silences every credit on this card without losing their state. */
  muted: boolean
  archived: boolean
  createdAt: IsoInstant
  updatedAt: IsoInstant
}

export interface Benefit {
  id: Uuid
  cardId: Uuid
  name: string
  description?: string
  category: BenefitCategory
  /** Phosphor icon name, e.g. `car-profile`. */
  icon?: string
  /** Where it must be spent, e.g. "Uber", "Resy". Used to detect overlaps. */
  merchant?: string
  /** Value released per cycle, in cents. */
  valueCents: number
  cadence: Cadence
  anchor: CycleAnchor
  /**
   * True when the credit must be activated on the issuer's benefits page
   * before a cent of it can be spent. Until {@link enrolledAt} is set the
   * credit is `locked` — visible, counted separately, and never dunned as if
   * it were merely unspent.
   */
  enrollmentRequired: boolean
  enrolledAt?: IsoInstant
  /** Why it is blocked, shown on the locked rows. */
  enrollmentNote?: string
  enrollmentUrl?: string
  /**
   * Spend the issuer asks for in a year before the credit opens, in cents.
   * Until {@link spendMetAt} falls inside the current year the credit is
   * `locked` for spend, excluded from value totals and never reminded about.
   */
  spendThresholdCents?: number
  /** When the user said the threshold was reached; cleared by revoking. */
  spendMetAt?: IsoInstant
  /**
   * The last day the credit can be used, for credits the issuer has announced
   * an end to. The final window is clamped to this day and nothing follows
   * it; afterwards the credit is skipped the way an inactive one is.
   */
  endsOn?: IsoDate
  /** Numbered "How to redeem" steps shown in the detail sheet. */
  redemptionSteps: string[]
  notes?: string
  /** Silences this credit's reminders; the bell on every row toggles it. */
  muted: boolean
  /**
   * Opts this credit out of its cadence's default reminder ladder in favour of
   * a single alert on the last day.
   */
  lastCallOnly: boolean
  /** Set false to keep history but stop tracking. */
  active: boolean
  createdAt: IsoInstant
  updatedAt: IsoInstant
}

/**
 * A concrete window during which a {@link Benefit} can be used.
 * Derived, never stored — see `src/domain/cycles.ts`.
 */
export interface Cycle {
  /** Stable per-benefit identity for the window; equal to {@link start}. */
  key: IsoDate
  /** First day the credit is usable, inclusive. */
  start: IsoDate
  /** Last day the credit is usable, inclusive. */
  end: IsoDate
  /** Human label for the period, e.g. "Sep 2026", "Q3 2026", "H2 2026". */
  label: string
}

/** A recorded use of a credit within one cycle. Partial claims are normal. */
export interface Claim {
  id: Uuid
  benefitId: Uuid
  /** {@link Cycle.key} this claim belongs to. */
  cycleKey: IsoDate
  amountCents: number
  claimedAt: IsoInstant
  note?: string
}

/**
 * The status ladder, taken from the design.
 *
 * `locked` and `manual` are deliberately *not* variants of "unclaimed": Today's
 * headline excludes both, because money behind an unticked enrolment box is not
 * money you are failing to spend.
 */
export type BenefitStatus =
  /** Enrolment required and not yet confirmed. Nothing is spendable. */
  | 'locked'
  /** No cycle tracks it; the user reviews it by hand. */
  | 'manual'
  /** Open, and the window closes within {@link USE_SOON_DAYS}. */
  | 'use_soon'
  /** Open, with more than a month of runway. */
  | 'available'
  /** Fully used this cycle. */
  | 'captured'
  /** The window closed with value left on the table. */
  | 'missed'

/** The boundary between "Use soon" and "Available", in days. */
export const USE_SOON_DAYS = 30

/**
 * A benefit resolved against a specific date: the window it is in, what has
 * been claimed, and where it sits on the ladder. This is what every screen
 * renders.
 */
export interface BenefitInstance {
  benefit: Benefit
  card: Card
  cycle: Cycle
  status: BenefitStatus
  /** Cents already claimed in this cycle. */
  claimedCents: number
  /** Cents still available in this cycle; zero when locked is irrelevant. */
  remainingCents: number
  /** Whole days until the cycle closes; 0 means it closes today. */
  daysRemaining: number
  /** 0..1 progress through the cycle window, for the period bars. */
  cycleProgress: number
  /** True when reminders are silenced, by the credit or by its card. */
  muted: boolean
}

/** One rung of a cadence's reminder ladder. */
export interface LadderRung {
  /** Days before the window closes that this rung fires. */
  daysBefore: number
  /** Shown in the detail sheet, e.g. "One week left". */
  label: string
  /**
   * How hard it pushes. `permissive` is a "you can use me" with no urgency;
   * `urgent` is the last call. Nocturne carries urgency as a saturated ground
   * and a filled glyph, never an alarm colour.
   */
  tone: 'permissive' | 'notice' | 'urgent'
}

export interface NotificationSettings {
  enabled: boolean
  /** Local time of day for reminders, `HH:MM` (24h). */
  timeOfDay: string
  /** Suppress reminders for cycles worth less than this. */
  minValueCents: number
  /** Remind before the annual fee posts. */
  annualFeeReminder: boolean
  /** Remind about credits that are locked behind enrolment. */
  enrollmentReminder: boolean
}

export interface Settings {
  notifications: NotificationSettings
  /** Horizon in days for Today's "Use soon" band. */
  useSoonDays: number
  theme: 'system' | 'light' | 'dark'
  /** Filters Today and Credits to one household member; empty means everyone. */
  holderFilter: string
}

/** The entire persisted state. Snapshotted to IndexedDB as one record. */
export interface AppData {
  version: number
  cards: Card[]
  benefits: Benefit[]
  claims: Claim[]
  settings: Settings
}
