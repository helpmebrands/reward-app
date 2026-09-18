import { daysBetween, parseIsoDate, todayIso } from './dates.ts'
import type { IsoDate } from './types.ts'

const wholeDollars = new Intl.NumberFormat(undefined, {
  style: 'currency',
  currency: 'USD',
  maximumFractionDigits: 0,
})

const withCents = new Intl.NumberFormat(undefined, {
  style: 'currency',
  currency: 'USD',
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
})

/**
 * Money for display. Cents are dropped when the amount is whole, because most
 * credits are round numbers and "$15" reads faster than "$15.00" in a list.
 */
export function formatMoney(cents: number): string {
  const dollars = cents / 100
  return cents % 100 === 0 ? wholeDollars.format(dollars) : withCents.format(dollars)
}

/** Always shows cents. Use in inputs and totals where precision matters. */
export function formatMoneyExact(cents: number): string {
  return withCents.format(cents / 100)
}

export function parseMoneyToCents(input: string): number | null {
  const cleaned = input.replace(/[^0-9.]/g, '')
  if (cleaned === '') return null
  const value = Number.parseFloat(cleaned)
  if (!Number.isFinite(value) || value < 0) return null
  return Math.round(value * 100)
}

const weekdayShort = new Intl.DateTimeFormat(undefined, {
  weekday: 'short',
  day: 'numeric',
  month: 'short',
})
const dayMonthLong = new Intl.DateTimeFormat(undefined, { day: 'numeric', month: 'long' })
const monthDay = new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric' })
const monthDayYear = new Intl.DateTimeFormat(undefined, {
  month: 'short',
  day: 'numeric',
  year: 'numeric',
})

function toLocalDate(iso: IsoDate): Date {
  const { year, month, day } = parseIsoDate(iso)
  return new Date(year, month - 1, day)
}

/** `Sep 30`, or `Sep 30, 2027` when the date is outside the current year. */
export function formatDate(iso: IsoDate, on: IsoDate = todayIso()): string {
  const date = toLocalDate(iso)
  return parseIsoDate(iso).year === parseIsoDate(on).year
    ? monthDay.format(date)
    : monthDayYear.format(date)
}

/** `Sep 1 – Sep 30`, the window a credit is usable in. */
export function formatRange(start: IsoDate, end: IsoDate, on: IsoDate = todayIso()): string {
  return `${formatDate(start, on)} – ${formatDate(end, on)}`
}

/**
 * How long is left, in the words a person would use. The urgent end is
 * deliberately blunt — "Today" and "Tomorrow" beat "in 0 days".
 */
export function formatDaysRemaining(days: number): string {
  if (days < 0) return 'Expired'
  if (days === 0) return 'Today'
  if (days === 1) return 'Tomorrow'
  if (days < 7) return `${days} days`
  if (days < 14) return '1 week'
  if (days < 31) return `${Math.round(days / 7)} weeks`
  if (days < 60) return '1 month'
  if (days < 365) return `${Math.round(days / 30)} months`
  return `${Math.round(days / 365)} year${days >= 730 ? 's' : ''}`
}

/** Screen-reader friendly version of {@link formatDaysRemaining}. */
export function describeDeadline(days: number, end: IsoDate): string {
  if (days < 0) return `Expired on ${formatDate(end)}`
  if (days === 0) return `Expires today, ${formatDate(end)}`
  if (days === 1) return `Expires tomorrow, ${formatDate(end)}`
  return `Expires in ${days} days, on ${formatDate(end)}`
}

export function formatRelativeFromToday(iso: IsoDate, on: IsoDate = todayIso()): string {
  return formatDaysRemaining(daysBetween(on, iso))
}

/** Initials for a card avatar, e.g. "American Express" -> "AE". */
export function initials(text: string): string {
  const words = text.trim().split(/\s+/).filter(Boolean)
  if (words.length === 0) return '?'
  if (words.length === 1) return (words[0] ?? '').slice(0, 2).toUpperCase()
  return `${words[0]?.[0] ?? ''}${words[1]?.[0] ?? ''}`.toUpperCase()
}

/** `Tue, 15 Sep` — the date beside the app name in the header. */
export function formatHeaderDate(iso: IsoDate): string {
  return weekdayShort.format(toLocalDate(iso))
}

/** `30 September` — a reset date read as a sentence rather than a label. */
export function formatResetDate(iso: IsoDate): string {
  return dayMonthLong.format(toLocalDate(iso))
}

/**
 * Money split into its symbol and digits, so the headline can set them at
 * different sizes the way the design does.
 */
export function moneyParts(cents: number): { symbol: string; digits: string } {
  const formatted = formatMoney(cents)
  const match = /^([^\d-]*)(.*)$/.exec(formatted)
  return { symbol: match?.[1] ?? '$', digits: match?.[2] ?? formatted }
}
