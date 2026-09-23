/**
 * Form rules, as pure functions.
 *
 * Each returns the sentence the field shows under itself, or null when the
 * value is fine. The sentence says what to enter rather than what went
 * wrong, because the person reading it is about to type (WCAG 3.3.3). The
 * editors own no rules of their own; they call these on blur and on submit.
 */

/** A text field that must not be blank. `message` says what to enter. */
export function requiredError(value: string, message: string): string | null {
  return value.trim().length > 0 ? null : message
}

/** An amount of money that may be zero, such as an annual fee. */
export function moneyError(raw: string): string | null {
  const cents = parseMoney(raw)
  return cents !== null && cents >= 0 ? null : 'Enter the amount as a number, like 695.'
}

/** An amount of money that must be worth something, such as a credit's value. */
export function positiveMoneyError(raw: string): string | null {
  const cents = parseMoney(raw)
  return cents !== null && cents > 0 ? null : 'Enter a value above zero.'
}

/** The cardmember year start, as a calendar date. */
export function anniversaryError(value: string): string | null {
  return isCalendarDate(value) ? null : 'Enter the date the cardmember year starts.'
}

/** The last day a credit can be used, if it has one, as a calendar date. */
export function endsOnError(value: string): string | null {
  if (value.trim() === '') return null
  return isCalendarDate(value)
    ? null
    : 'Enter the last day it can be used as a date, or leave it blank.'
}

function isCalendarDate(value: string): boolean {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value)
  if (!match) return false
  const [, y, m, d] = match
  const date = new Date(Date.UTC(Number(y), Number(m) - 1, Number(d)))
  return date.getUTCMonth() === Number(m) - 1 && date.getUTCDate() === Number(d)
}

/** An enrolment page, if given, must be somewhere a browser can open. */
export function enrollmentUrlError(value: string): string | null {
  if (value.trim() === '') return null
  try {
    const url = new URL(value)
    if (url.protocol === 'https:' || url.protocol === 'http:') return null
  } catch {
    // fall through
  }
  return 'Enter a full web address, starting with https://.'
}

/** Whole cents from what was typed, or null when it is not a number. */
export function parseMoney(raw: string): number | null {
  const trimmed = raw.trim()
  if (trimmed === '' || !/^-?\d*(\.\d*)?$/.test(trimmed)) return null
  const value = Number(trimmed)
  return Number.isFinite(value) ? Math.round(value * 100) : null
}
