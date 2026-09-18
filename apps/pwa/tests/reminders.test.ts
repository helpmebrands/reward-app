import { describe, expect, it } from 'vitest'
import { currentRung, defaultLadder, ladderFor, ladderSummary } from '../src/domain/ladder.ts'
import { buildSchedule, dueReminders } from '../src/domain/reminders.ts'
import type { AppData } from '../src/domain/types.ts'
import { makeBenefit, makeCard, makeClaim, makeData } from './factories.ts'

/** 16 Sep 2026, 08:00 local — before the 09:00 reminder time. */
const NOW = new Date(2026, 8, 16, 8, 0, 0)

function withNotifications(
  data: AppData,
  patch: Partial<AppData['settings']['notifications']> = {},
) {
  return {
    ...data,
    settings: {
      ...data.settings,
      notifications: { ...data.settings.notifications, enabled: true, ...patch },
    },
  }
}

describe('the ladder', () => {
  it('gives each cadence rungs proportional to its window', () => {
    expect(defaultLadder('monthly').map((r) => r.daysBefore)).toEqual([23, 7, 0])
    expect(defaultLadder('quarterly').map((r) => r.daysBefore)).toEqual([30, 14, 3])
    expect(defaultLadder('semiannual').map((r) => r.daysBefore)).toEqual([60, 21, 7])
    expect(defaultLadder('annual').map((r) => r.daysBefore)).toEqual([180, 90, 30, 7])
  })

  it('opens permissively and ends urgent', () => {
    const rungs = defaultLadder('quarterly')
    expect(rungs[0]?.tone).toBe('permissive')
    expect(rungs.at(-1)?.tone).toBe('urgent')
  })

  it('reduces to a single last call when the user opts out', () => {
    const rungs = ladderFor(makeBenefit('annual', { lastCallOnly: true }))
    expect(rungs).toHaveLength(1)
    expect(rungs[0]?.daysBefore).toBe(7)
  })

  it('reports the rung a credit is standing on', () => {
    const monthly = makeBenefit('monthly')
    expect(currentRung(monthly, 28)).toBeNull()
    expect(currentRung(monthly, 23)?.tone).toBe('permissive')
    expect(currentRung(monthly, 7)?.tone).toBe('notice')
    expect(currentRung(monthly, 0)?.tone).toBe('urgent')
  })

  it('summarises a cadence for the settings screen', () => {
    expect(ladderSummary('quarterly')).toBe('30 · 14 · 3')
    expect(ladderSummary('monthly')).toBe('23 · 7 · last day')
  })
})

describe('buildSchedule', () => {
  it('produces nothing while reminders are switched off', () => {
    expect(buildSchedule(makeData(), NOW).reminders).toHaveLength(0)
  })

  it('schedules a rung at the reminder time on the right day', () => {
    // A monthly credit closing 30 Sep fires its 7-day rung on 23 Sep at 09:00.
    const data = withNotifications(makeData({ benefits: [makeBenefit('monthly')] }))
    const fired = buildSchedule(data, NOW).reminders.map((r) => new Date(r.fireAt))
    const sept23 = fired.find((d) => d.getDate() === 23 && d.getMonth() === 8)
    expect(sept23).toBeDefined()
    expect(sept23?.getHours()).toBe(9)
  })

  it('never schedules a rung in the past', () => {
    const data = withNotifications(makeData({ benefits: [makeBenefit('monthly')] }))
    for (const reminder of buildSchedule(data, NOW).reminders) {
      expect(reminder.fireAt).toBeGreaterThan(NOW.getTime())
    }
  })

  it('groups credits that fire on the same day into one notification', () => {
    // Twelve separate alerts on one morning is how an app gets muted.
    const data = withNotifications(
      makeData({
        benefits: [
          makeBenefit('monthly', { id: 'a', name: 'Uber Cash', valueCents: 1500 }),
          makeBenefit('monthly', { id: 'b', name: 'Walmart+', valueCents: 1295 }),
          makeBenefit('monthly', { id: 'c', name: 'Entertainment', valueCents: 2500 }),
        ],
      }),
    )
    const sameDay = buildSchedule(data, NOW).reminders.filter((r) => r.id === '2026-09-23|notice')
    expect(sameDay).toHaveLength(1)
    expect(sameDay[0]?.items).toHaveLength(3)
    expect(sameDay[0]?.totalCents).toBe(5295)
  })

  it('leads the copy with the single biggest loss', () => {
    const data = withNotifications(
      makeData({
        benefits: [
          makeBenefit('monthly', { id: 'a', name: 'Uber Cash', valueCents: 1500 }),
          makeBenefit('monthly', { id: 'b', name: 'Resy', valueCents: 10_000 }),
        ],
      }),
    )
    const reminder = buildSchedule(data, NOW).reminders.find((r) => r.id === '2026-09-23|notice')
    expect(reminder?.body).toContain('Resy')
    expect(reminder?.title).toContain('$115')
  })

  it('leads with the blocker when most of the money is locked', () => {
    // Telling someone to spend money they cannot reach is worse than silence.
    const data = withNotifications(
      makeData({
        benefits: [
          makeBenefit('monthly', { id: 'a', name: 'Uber Cash', valueCents: 1500 }),
          makeBenefit('monthly', {
            id: 'b',
            name: 'Equinox',
            valueCents: 30_000,
            enrollmentRequired: true,
          }),
        ],
      }),
    )
    const reminder = buildSchedule(data, NOW).reminders.find((r) => r.id === '2026-09-23|notice')
    expect(reminder?.title).toContain('locked')
  })

  it('stays silent about locked credits when that reminder is switched off', () => {
    const data = withNotifications(
      makeData({ benefits: [makeBenefit('monthly', { enrollmentRequired: true })] }),
      { enrollmentReminder: false },
    )
    expect(buildSchedule(data, NOW).reminders).toHaveLength(0)
  })

  it('skips a credit the user has muted, and every credit on a muted card', () => {
    const muted = withNotifications(
      makeData({ benefits: [makeBenefit('monthly', { muted: true })] }),
    )
    expect(buildSchedule(muted, NOW).reminders).toHaveLength(0)

    const mutedCard = withNotifications(makeData({ cards: [makeCard({ muted: true })] }))
    expect(buildSchedule(mutedCard, NOW).reminders).toHaveLength(0)
  })

  it('skips a cycle that has already been fully claimed', () => {
    const data = withNotifications(
      makeData({
        benefits: [makeBenefit('monthly', { valueCents: 2500 })],
        claims: [makeClaim({ amountCents: 2500 })],
      }),
    )
    const september = buildSchedule(data, NOW).reminders.filter(
      (r) => new Date(r.fireAt).getMonth() === 8,
    )
    expect(september).toHaveLength(0)
  })

  it('still reminds about the balance of a partly used credit', () => {
    const data = withNotifications(
      makeData({
        benefits: [makeBenefit('monthly', { valueCents: 2500 })],
        claims: [makeClaim({ amountCents: 1000 })],
      }),
    )
    const reminder = buildSchedule(data, NOW).reminders.find((r) => r.id === '2026-09-23|notice')
    expect(reminder?.totalCents).toBe(1500)
  })

  it('ignores untracked credits, which have no deadline to warn about', () => {
    const data = withNotifications(makeData({ benefits: [makeBenefit('manual')] }))
    expect(buildSchedule(data, NOW).reminders).toHaveLength(0)
  })

  it('respects the minimum-value floor', () => {
    const data = withNotifications(
      makeData({ benefits: [makeBenefit('monthly', { valueCents: 50 })] }),
      { minValueCents: 100 },
    )
    expect(buildSchedule(data, NOW).reminders).toHaveLength(0)
  })

  it('gives every reminder a stable, unique id so recomputing cannot duplicate', () => {
    // Ids must survive a recompute: the service worker dedupes on them, and a
    // reminder that changed identity every launch would fire again each time.
    const data = withNotifications(makeData({ benefits: [makeBenefit('quarterly')] }))
    const later = new Date(2026, 8, 16, 10, 0, 0)
    const first = buildSchedule(data, NOW).reminders
    const second = buildSchedule(data, later).reminders

    expect(new Set(first.map((r) => r.id)).size).toBe(first.length)
    // Rungs that passed between the two runs drop out; every one still ahead
    // keeps the id it had.
    expect(second.map((r) => r.id)).toEqual(
      first.filter((r) => r.fireAt > later.getTime()).map((r) => r.id),
    )
  })

  it('returns reminders in the order they will fire', () => {
    const data = withNotifications(
      makeData({
        benefits: [makeBenefit('monthly', { id: 'm' }), makeBenefit('annual', { id: 'a' })],
      }),
    )
    const times = buildSchedule(data, NOW).reminders.map((r) => r.fireAt)
    expect(times).toEqual([...times].sort((a, b) => a - b))
  })
})

describe('dueReminders', () => {
  const schedule = {
    generatedAt: 0,
    reminders: [
      { id: 'past', fireAt: 1_000, tone: 'notice' } as never,
      { id: 'future', fireAt: 100_000 } as never,
    ],
  }

  it('returns only what has come due and has not been shown', () => {
    expect(dueReminders(schedule, 2_000, new Set()).map((r) => r.id)).toEqual(['past'])
    expect(dueReminders(schedule, 2_000, new Set(['past']))).toHaveLength(0)
  })

  it('drops a reminder the device slept through for days', () => {
    // By then the deadline has moved and the schedule has been rebuilt.
    const threeDays = 3 * 24 * 60 * 60 * 1000
    expect(dueReminders(schedule, threeDays, new Set())).toHaveLength(0)
  })
})
