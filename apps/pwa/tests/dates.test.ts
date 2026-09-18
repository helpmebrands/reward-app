import { describe, expect, it } from 'vitest'
import { addDays, addMonths, daysBetween, isWithin, todayIso } from '../src/domain/dates.ts'

describe('addMonths', () => {
  it('clamps to the end of a shorter target month', () => {
    expect(addMonths('2026-01-31', 1)).toBe('2026-02-28')
    expect(addMonths('2026-08-31', 1)).toBe('2026-09-30')
  })

  it('handles leap years', () => {
    expect(addMonths('2024-01-31', 1)).toBe('2024-02-29')
    expect(addMonths('2024-02-29', 12)).toBe('2025-02-28')
  })

  it('crosses year boundaries in both directions', () => {
    expect(addMonths('2026-11-15', 3)).toBe('2027-02-15')
    expect(addMonths('2026-02-15', -3)).toBe('2025-11-15')
  })
})

describe('addDays', () => {
  it('does not drift across a DST transition', () => {
    // US DST starts 2026-03-08; naive local-time arithmetic loses an hour here
    // and can roll the date back a day.
    expect(addDays('2026-03-07', 1)).toBe('2026-03-08')
    expect(addDays('2026-03-08', 1)).toBe('2026-03-09')
    expect(addDays('2026-11-01', 1)).toBe('2026-11-02')
  })

  it('steps backwards over month ends', () => {
    expect(addDays('2026-03-01', -1)).toBe('2026-02-28')
  })
})

describe('daysBetween', () => {
  it('counts whole days and signs the direction', () => {
    expect(daysBetween('2026-09-16', '2026-09-16')).toBe(0)
    expect(daysBetween('2026-09-16', '2026-09-30')).toBe(14)
    expect(daysBetween('2026-09-30', '2026-09-16')).toBe(-14)
  })

  it('spans a full non-leap year', () => {
    expect(daysBetween('2026-01-01', '2027-01-01')).toBe(365)
  })
})

describe('isWithin', () => {
  it('treats both bounds as inclusive', () => {
    expect(isWithin('2026-09-01', '2026-09-01', '2026-09-30')).toBe(true)
    expect(isWithin('2026-09-30', '2026-09-01', '2026-09-30')).toBe(true)
    expect(isWithin('2026-08-31', '2026-09-01', '2026-09-30')).toBe(false)
  })
})

describe('todayIso', () => {
  it('reads the local calendar date, not the UTC one', () => {
    // 2026-09-16T23:30 local is already the 17th in UTC for eastern offsets;
    // the user still thinks of it as the 16th.
    expect(todayIso(new Date(2026, 8, 16, 23, 30))).toBe('2026-09-16')
    expect(todayIso(new Date(2026, 0, 1, 0, 1))).toBe('2026-01-01')
  })
})
