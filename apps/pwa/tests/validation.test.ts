import { describe, expect, it } from 'vitest'
import {
  anniversaryError,
  enrollmentUrlError,
  moneyError,
  positiveMoneyError,
  requiredError,
} from '../src/domain/validation.ts'

/**
 * Form rules, as pure functions. Each returns the sentence the field shows,
 * or null, so the editors never carry validation logic of their own.
 */
describe('form rules', () => {
  // @lat: [[tests#Form rules#A required field must not be blank]]
  it('rejects a blank or whitespace holder and says what to enter', () => {
    expect(requiredError('', 'Enter whose card this is.')).toBe('Enter whose card this is.')
    expect(requiredError('   ', 'Enter whose card this is.')).toBe('Enter whose card this is.')
    expect(requiredError('Jim', 'Enter whose card this is.')).toBeNull()
  })

  // @lat: [[tests#Form rules#Money must be a number, and a value must be above zero]]
  it('rejects a fee that is not a number and a value at or below zero', () => {
    expect(moneyError('')).toMatch(/number/)
    expect(moneyError('abc')).toMatch(/number/)
    expect(moneyError('-5')).toMatch(/number/)
    expect(moneyError('0')).toBeNull()
    expect(moneyError('695')).toBeNull()
    expect(moneyError('12.50')).toBeNull()

    expect(positiveMoneyError('0')).toMatch(/above zero/)
    expect(positiveMoneyError('-1')).toMatch(/above zero/)
    expect(positiveMoneyError('x')).toMatch(/above zero/)
    expect(positiveMoneyError('0.01')).toBeNull()
  })

  // @lat: [[tests#Form rules#An anniversary must be a calendar date]]
  it('rejects a missing or malformed anniversary', () => {
    expect(anniversaryError('')).toMatch(/date/)
    expect(anniversaryError('2026-13-01')).toMatch(/date/)
    expect(anniversaryError('14/03/2021')).toMatch(/date/)
    expect(anniversaryError('2021-03-14')).toBeNull()
  })

  // @lat: [[tests#Form rules#An end date is optional but must be a calendar date]]
  it('allows no end date, and rejects one that is not a calendar date', () => {
    expect(endsOnError('')).toBeNull()
    expect(endsOnError('   ')).toBeNull()
    expect(endsOnError('2026-13-01')).toMatch(/date/)
    expect(endsOnError('31/12/2026')).toMatch(/date/)
    expect(endsOnError('2026-12-31')).toBeNull()
  })

  // @lat: [[tests#Form rules#An enrolment page must be a web address]]
  it('rejects an enrolment page that is not an http(s) URL, and allows none', () => {
    expect(enrollmentUrlError('')).toBeNull()
    expect(enrollmentUrlError('amex.com/enrol')).toMatch(/https:\/\//)
    expect(enrollmentUrlError('ftp://amex.com')).toMatch(/https:\/\//)
    expect(enrollmentUrlError('https://amex.com/enrol')).toBeNull()
    expect(enrollmentUrlError('http://amex.com/enrol')).toBeNull()
  })
})
