# Reminders

Reminder timing is the product. Each cadence has its own ladder of warnings, everything due on one day is grouped into one notification, and the schedule is a pure function of the household's data.

The schedule is computed from `AppData` alone (`apps/pwa/src/domain/reminders.ts` in the reference implementation) and handed to the platform to deliver ([[delivery]] for the PWA). That split keeps the timing rules testable and means delivery needs no domain knowledge.

## The ladder

A monthly $15 credit and an annual $300 one cannot share a schedule, so each cadence gets its own rungs, defined in `apps/pwa/src/domain/ladder.ts`.

Warn about the monthly one 90 days out and it is noise; warn about the annual one on the last day and it is too late to book anything.

| Cadence | Rungs (days before the window shuts) |
| --- | --- |
| Monthly | 23 · 7 · last day |
| Quarterly | 30 · 14 · 3 |
| Semi-annual | 60 · 21 · 7 |
| Annual | 180 · 90 · 30 · 7 |
| Manual | one rung, "Tracked manually", never scheduled |

The tone climbs along the rungs, from `permissive` ("You can use me") through `notice` to `urgent` (last call). Tone drives both the row styling and the notification copy; Nocturne carries urgency as a saturated ground and a filled glyph, never an alarm colour.

- [[apps/pwa/src/domain/ladder.ts#ladderFor]] returns a credit's rungs, collapsing to the final rung alone when `lastCallOnly` is set.
- [[apps/pwa/src/domain/ladder.ts#currentRung]] reports which rung a credit is standing on given days remaining, or null before the first.
- [[apps/pwa/src/domain/ladder.ts#ladderSummary]] renders the table above for Settings.

## Schedule construction

[[apps/pwa/src/domain/reminders.ts#buildSchedule]] turns `AppData` into a sorted list of reminders over a 200-day horizon. It is recomputed on every data change, so a stale schedule is never more than one write away from correct.

A credit is skipped when reminders are disabled, the credit is inactive or manual, the credit or its card is muted, the credit's value is below `minValueCents`, or it is locked and enrolment reminders are off. For each remaining cycle in the horizon with money still unclaimed, each rung fires at `cycle.end - daysBefore`, at the user's `timeOfDay` in local time. Rungs already in the past are dropped.

### Grouping

Reminders are grouped by the day and tone they fire on, not emitted per credit. A household with two premium cards can have a dozen credits lapsing in one week, and a dozen separate alerts is how an app gets muted.

The group key `${fireOn}|${tone}` becomes the reminder's `id` and notification `tag`. Ids are therefore stable across recomputes: the delivery layer dedupes on them, and a reminder that changed identity every launch would fire again each time. Items within a group sort by remaining value, biggest first, and a group whose total falls below the minimum-value floor is dropped.

### Notification copy

One decision per notification. The title leads with the total at stake and the rung's urgency; the body leads with the single biggest loss.

- When more than half the money in a group is locked, the title becomes "$X is still locked": telling someone to spend money they cannot reach is worse than silence.
- `permissive` reads "$X just opened"; `notice` reads "$X on the line — one week left"; `urgent` reads "$X expires tonight" on the last day.
- A single-item body names the credit, merchant and holder; a multi-item body names the largest and counts the rest.

## Nudge preview

Notification permission is a big ask on faith. The "Preview nudge" button on Today shows the next real reminder from the stored schedule, with the user's own numbers, in-app and without permission.

When nothing is scheduled yet, [[apps/pwa/src/ui/NudgePreview.tsx#sampleReminder]] builds a stand-in from the claimable total.
