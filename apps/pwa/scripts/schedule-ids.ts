/**
 * Dumps the reminder group ids the PWA's `buildSchedule` produces for the
 * sample household on 16 September 2026 at 08:00 local, with reminders
 * switched on. The Dart port's `sample_household_test.dart` asserts it
 * produces the same list, so the fixture is regenerated from here whenever
 * the sample or the schedule rules change:
 *
 *   node --experimental-strip-types scripts/schedule-ids.ts \
 *     > ../../packages/domain/test/fixtures/sample-schedule-ids.json
 */
import { readFileSync } from 'node:fs'
import { buildSchedule } from '../src/domain/reminders.ts'
import type { AppData } from '../src/domain/types.ts'

const data = JSON.parse(
  readFileSync(new URL('../samples/sample-household.json', import.meta.url), 'utf8'),
) as AppData
data.settings.notifications.enabled = true

const schedule = buildSchedule(data, new Date(2026, 8, 16, 8, 0, 0))
console.log(
  JSON.stringify(
    schedule.reminders.map((reminder) => reminder.id),
    null,
    2,
  ),
)
