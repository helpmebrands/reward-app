import { cyclesBetween, hasEnded } from './cycles.ts'
import { addDays, atLocalTime, compareIsoDate, todayIso } from './dates.ts'
import { formatMoney } from './format.ts'
import { ladderFor } from './ladder.ts'
import { cardLabel, claimedIn, indexClaims, isLocked } from './selectors.ts'
import type { AppData, IsoDate, LadderRung } from './types.ts'

/**
 * Turning benefit cycles into a reminder schedule.
 *
 * Deliberately pure: the schedule is computed here, written to IndexedDB, and
 * replayed by the service worker. That keeps the timing rules testable and
 * means the worker needs no domain knowledge.
 */

export interface ReminderItem {
  benefitId: string
  cycleKey: IsoDate
  benefitName: string
  cardName: string
  holder: string
  merchant?: string
  remainingCents: number
  endsOn: IsoDate
  locked: boolean
}

export interface Reminder {
  /** Stable across recomputes, so re-scheduling does not duplicate alerts. */
  id: string
  /** When to show it, as epoch milliseconds. */
  fireAt: number
  title: string
  body: string
  /** A newer reminder with the same tag replaces the older one. */
  tag: string
  /** Where tapping the notification should land. */
  url: string
  items: ReminderItem[]
  totalCents: number
  tone: LadderRung['tone']
}

export interface ReminderSchedule {
  generatedAt: number
  reminders: Reminder[]
}

/** How far ahead to generate. Recomputed on each launch and daily in the SW. */
const HORIZON_DAYS = 200

/**
 * Builds the reminder schedule.
 *
 * Reminders are grouped by the day and rung they fire on, not emitted per
 * credit: a household with two premium cards can have a dozen credits lapsing
 * in the same week, and a dozen separate notifications is how an app gets
 * muted. The copy then leads with the single biggest loss — one decision per
 * notification.
 */
export function buildSchedule(
  data: AppData,
  now: Date = new Date(),
  horizonDays: number = HORIZON_DAYS,
): ReminderSchedule {
  const settings = data.settings.notifications
  const schedule: ReminderSchedule = { generatedAt: now.getTime(), reminders: [] }
  if (!settings.enabled) return schedule

  const from = todayIso(now)
  const until = addDays(from, horizonDays)
  const claims = indexClaims(data.claims)
  const cardsById = new Map(data.cards.map((card) => [card.id, card]))

  interface Group {
    fireAt: number
    rung: LadderRung
    items: ReminderItem[]
  }
  const groups = new Map<string, Group>()

  for (const benefit of data.benefits) {
    if (!benefit.active || benefit.cadence === 'manual' || hasEnded(benefit, from)) continue
    if (benefit.muted) continue
    const card = cardsById.get(benefit.cardId)
    if (!card || card.archived || card.muted) continue
    if (benefit.valueCents < settings.minValueCents) continue

    const locked = isLocked(benefit)
    // A locked credit cannot be spent, so it is only worth a nudge if the user
    // asked to be told about enrolment — otherwise it is an impossible chore.
    if (locked && !settings.enrollmentReminder) continue

    for (const cycle of cyclesBetween(benefit, card, from, until)) {
      const remainingCents = benefit.valueCents - claimedIn(claims, benefit.id, cycle.key)
      if (remainingCents <= 0) continue

      for (const rung of ladderFor(benefit)) {
        const fireOn = addDays(cycle.end, -rung.daysBefore)
        if (compareIsoDate(fireOn, from) < 0) continue

        const fireAt = atLocalTime(fireOn, settings.timeOfDay).getTime()
        if (fireAt <= now.getTime()) continue

        const key = `${fireOn}|${rung.tone}`
        const group = groups.get(key) ?? { fireAt, rung, items: [] }
        group.items.push({
          benefitId: benefit.id,
          cycleKey: cycle.key,
          benefitName: benefit.name,
          cardName: cardLabel(card),
          holder: card.holder,
          remainingCents,
          endsOn: cycle.end,
          locked,
          ...(benefit.merchant ? { merchant: benefit.merchant } : {}),
        })
        groups.set(key, group)
      }
    }
  }

  for (const [key, group] of groups) {
    const items = group.items.sort((a, b) => b.remainingCents - a.remainingCents)
    const totalCents = items.reduce((sum, item) => sum + item.remainingCents, 0)
    if (totalCents < settings.minValueCents) continue
    schedule.reminders.push({
      id: key,
      fireAt: group.fireAt,
      tag: `cardvantage-${key}`,
      url: '/?from=notification',
      title: titleFor(items, totalCents, group.rung),
      body: bodyFor(items, group.rung),
      items,
      totalCents,
      tone: group.rung.tone,
    })
  }

  schedule.reminders.sort((a, b) => a.fireAt - b.fireAt)
  return schedule
}

function titleFor(items: ReminderItem[], totalCents: number, rung: LadderRung): string {
  const money = formatMoney(totalCents)
  const locked = items.filter((item) => item.locked)

  // When most of the money is behind an enrolment box, lead with the blocker:
  // telling someone to spend money they cannot reach is worse than silence.
  if (locked.length > 0 && sum(locked) > totalCents / 2) {
    return `${formatMoney(sum(locked))} is still locked`
  }

  switch (rung.tone) {
    case 'permissive':
      return `${money} just opened`
    case 'notice':
      return `${money} on the line — ${rung.label.toLowerCase()}`
    case 'urgent':
      return rung.daysBefore === 0 ? `${money} expires tonight` : `${money} — ${rung.label}`
  }
}

function sum(items: ReminderItem[]): number {
  return items.reduce((total, item) => total + item.remainingCents, 0)
}

function bodyFor(items: ReminderItem[], rung: LadderRung): string {
  const first = items[0]
  if (!first) return ''

  const where = first.merchant ? ` at ${first.merchant}` : ''
  const whose = first.holder ? `${first.holder}’s` : 'your'

  if (items.length === 1) {
    if (first.locked) {
      return `${whose} ${first.benefitName} needs enrolment before you can spend a cent of it.`
    }
    return `${first.benefitName}${where} on ${whose} card. ${formatMoney(
      first.remainingCents,
    )} untouched.`
  }

  const rest = items.length - 1
  const tail = `and ${rest} other credit${rest === 1 ? '' : 's'}`
  if (rung.tone === 'permissive') {
    return `${first.benefitName} ${tail} reset overnight. Nothing is urgent yet.`
  }
  return `${whose} ${first.benefitName} is the largest untouched at ${formatMoney(
    first.remainingCents,
  )}, ${tail}.`
}

/** The reminders due now, given a schedule and the current time. */
export function dueReminders(
  schedule: ReminderSchedule,
  now: number,
  alreadyShown: ReadonlySet<string>,
  graceMs = 36 * 60 * 60 * 1000,
): Reminder[] {
  return schedule.reminders.filter(
    (reminder) =>
      !alreadyShown.has(reminder.id) &&
      reminder.fireAt <= now &&
      // Do not resurface something the device slept through for days.
      now - reminder.fireAt < graceMs,
  )
}
