import type { Benefit, Cadence, LadderRung } from './types.ts'

/**
 * The tiered reminder ladder.
 *
 * A monthly $15 credit and an annual $300 one cannot share a reminder schedule:
 * warn about the monthly one 90 days out and it is noise, warn about the annual
 * one only on the last day and it is too late to book anything. So each cadence
 * gets its own rungs, and the tone climbs along them — the first rung is a
 * permissive "you can use me", the last is a last call.
 *
 * These are the presets from the design. A user can opt one credit out with
 * {@link Benefit.lastCallOnly}.
 */
const LADDERS: Record<Cadence, LadderRung[]> = {
  monthly: [
    // Day 7 of a ~30-day window, expressed as days remaining.
    { daysBefore: 23, label: 'You can use me', tone: 'permissive' },
    { daysBefore: 7, label: 'One week left', tone: 'notice' },
    { daysBefore: 0, label: 'Expires tonight', tone: 'urgent' },
  ],
  quarterly: [
    { daysBefore: 30, label: 'You can use me', tone: 'permissive' },
    { daysBefore: 14, label: 'Two weeks left', tone: 'notice' },
    { daysBefore: 3, label: 'Expires this week', tone: 'urgent' },
  ],
  semiannual: [
    { daysBefore: 60, label: 'You can use me', tone: 'permissive' },
    { daysBefore: 21, label: 'Three weeks left', tone: 'notice' },
    { daysBefore: 7, label: 'Final week', tone: 'urgent' },
  ],
  annual: [
    { daysBefore: 180, label: 'Half the year gone', tone: 'permissive' },
    { daysBefore: 90, label: 'Plan it now', tone: 'notice' },
    { daysBefore: 30, label: 'Urgent', tone: 'urgent' },
    { daysBefore: 7, label: 'Final week', tone: 'urgent' },
  ],
  // A rolling credit has no deadline until the user claims it, so it gets one
  // rung and is never scheduled.
  rolling: [{ daysBefore: 0, label: 'Restarts when claimed', tone: 'permissive' }],
  // Untracked credits get one rung and it is the user's own review, not a
  // deadline the app invented.
  manual: [{ daysBefore: 0, label: 'Tracked manually', tone: 'permissive' }],
}

/** The rungs that apply to one credit. */
export function ladderFor(benefit: Benefit): LadderRung[] {
  if (benefit.lastCallOnly) {
    const rungs = LADDERS[benefit.cadence]
    const last = rungs[rungs.length - 1]
    return last ? [last] : []
  }
  return LADDERS[benefit.cadence]
}

/** The default ladder for a cadence, for the settings screen's preview. */
export function defaultLadder(cadence: Cadence): LadderRung[] {
  return LADDERS[cadence]
}

/** A short description of a cadence's ladder, e.g. "30 · 14 · 3 days out". */
export function ladderSummary(cadence: Cadence): string {
  return LADDERS[cadence]
    .map((rung) => (rung.daysBefore === 0 ? 'last day' : String(rung.daysBefore)))
    .join(' · ')
}

/**
 * Which rung a credit is currently standing on, or `null` before the first one
 * has been reached. Drives the tone of the row and of the notification copy.
 */
export function currentRung(benefit: Benefit, daysRemaining: number): LadderRung | null {
  let reached: LadderRung | null = null
  for (const rung of ladderFor(benefit)) {
    if (daysRemaining <= rung.daysBefore) reached = rung
  }
  return reached
}
