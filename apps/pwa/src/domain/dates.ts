import type { IsoDate } from './types.ts'

/**
 * Calendar-date arithmetic.
 *
 * Everything here operates on `YYYY-MM-DD` strings and computes via `Date.UTC`,
 * which has no DST transitions. Using local-time `Date` objects for calendar
 * maths silently shifts dates by a day twice a year in most timezones.
 */

const ISO_DATE = /^(\d{4})-(\d{2})-(\d{2})$/

export interface DateParts {
  year: number
  /** 1-12, unlike `Date.getMonth()`. */
  month: number
  /** 1-31. */
  day: number
}

export function parseIsoDate(iso: IsoDate): DateParts {
  const match = ISO_DATE.exec(iso)
  if (!match) throw new RangeError(`Not an ISO calendar date: ${iso}`)
  const [, y, m, d] = match as unknown as [string, string, string, string]
  const parts = { year: Number(y), month: Number(m), day: Number(d) }
  if (parts.month < 1 || parts.month > 12) throw new RangeError(`Bad month in ${iso}`)
  if (parts.day < 1 || parts.day > daysInMonth(parts.year, parts.month)) {
    throw new RangeError(`Bad day in ${iso}`)
  }
  return parts
}

export function formatIsoDate({ year, month, day }: DateParts): IsoDate {
  const mm = String(month).padStart(2, '0')
  const dd = String(day).padStart(2, '0')
  return `${String(year).padStart(4, '0')}-${mm}-${dd}`
}

export function daysInMonth(year: number, month: number): number {
  // Day 0 of the next month is the last day of this one.
  return new Date(Date.UTC(year, month, 0)).getUTCDate()
}

function toUtcMillis(iso: IsoDate): number {
  const { year, month, day } = parseIsoDate(iso)
  return Date.UTC(year, month - 1, day)
}

function fromUtcMillis(ms: number): IsoDate {
  const d = new Date(ms)
  return formatIsoDate({
    year: d.getUTCFullYear(),
    month: d.getUTCMonth() + 1,
    day: d.getUTCDate(),
  })
}

const MS_PER_DAY = 86_400_000

export function addDays(iso: IsoDate, days: number): IsoDate {
  return fromUtcMillis(toUtcMillis(iso) + days * MS_PER_DAY)
}

/**
 * Adds calendar months, clamping the day to the target month's length so that
 * `2026-01-31 + 1 month` is `2026-02-28` rather than rolling into March.
 */
export function addMonths(iso: IsoDate, months: number): IsoDate {
  const { year, month, day } = parseIsoDate(iso)
  const zeroBased = year * 12 + (month - 1) + months
  const targetYear = Math.floor(zeroBased / 12)
  const targetMonth = (zeroBased % 12) + 1
  return formatIsoDate({
    year: targetYear,
    month: targetMonth,
    day: Math.min(day, daysInMonth(targetYear, targetMonth)),
  })
}

/** Whole days from `from` to `to`; negative when `to` is earlier. */
export function daysBetween(from: IsoDate, to: IsoDate): number {
  return Math.round((toUtcMillis(to) - toUtcMillis(from)) / MS_PER_DAY)
}

export function compareIsoDate(a: IsoDate, b: IsoDate): number {
  // ISO calendar dates are zero-padded, so lexical order is chronological.
  return a < b ? -1 : a > b ? 1 : 0
}

export function minIsoDate(a: IsoDate, b: IsoDate): IsoDate {
  return compareIsoDate(a, b) <= 0 ? a : b
}

export function maxIsoDate(a: IsoDate, b: IsoDate): IsoDate {
  return compareIsoDate(a, b) >= 0 ? a : b
}

/** True when `iso` falls within `[start, end]`, both inclusive. */
export function isWithin(iso: IsoDate, start: IsoDate, end: IsoDate): boolean {
  return compareIsoDate(iso, start) >= 0 && compareIsoDate(iso, end) <= 0
}

/**
 * The user's current calendar date, read from their local clock. Benefit
 * windows are the issuer's calendar dates, and the user experiences them
 * locally, so "today" is deliberately local rather than UTC.
 */
export function todayIso(now: Date = new Date()): IsoDate {
  return formatIsoDate({
    year: now.getFullYear(),
    month: now.getMonth() + 1,
    day: now.getDate(),
  })
}

/** Local midnight at the start of `iso`, as a real instant. */
export function startOfDayLocal(iso: IsoDate): Date {
  const { year, month, day } = parseIsoDate(iso)
  return new Date(year, month - 1, day, 0, 0, 0, 0)
}

/** Local `HH:MM` on `iso`, as a real instant. Used to schedule reminders. */
export function atLocalTime(iso: IsoDate, timeOfDay: string): Date {
  const [h, m] = timeOfDay.split(':')
  const date = startOfDayLocal(iso)
  date.setHours(Number(h ?? 9), Number(m ?? 0), 0, 0)
  return date
}
