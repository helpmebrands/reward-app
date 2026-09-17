# Reminders

Reminder timing is the product. Each cadence has its own ladder of warnings, everything due on one day is grouped into one notification, and delivery works with or without a push server.

The schedule is computed purely in `src/domain/reminders.ts`, written to IndexedDB, and replayed by the service worker. That split keeps the timing rules testable and means the worker needs no domain knowledge.

## The ladder

A monthly $15 credit and an annual $300 one cannot share a schedule, so each cadence gets its own rungs, defined in `src/domain/ladder.ts`.

Warn about the monthly one 90 days out and it is noise; warn about the annual one on the last day and it is too late to book anything.

| Cadence | Rungs (days before the window shuts) |
| --- | --- |
| Monthly | 23 · 7 · last day |
| Quarterly | 30 · 14 · 3 |
| Semi-annual | 60 · 21 · 7 |
| Annual | 180 · 90 · 30 · 7 |
| Manual | one rung, "Tracked manually", never scheduled |

The tone climbs along the rungs, from `permissive` ("You can use me") through `notice` to `urgent` (last call). Tone drives both the row styling and the notification copy; Nocturne carries urgency as a saturated ground and a filled glyph, never an alarm colour.

- [[src/domain/ladder.ts#ladderFor]] returns a credit's rungs, collapsing to the final rung alone when `lastCallOnly` is set.
- [[src/domain/ladder.ts#currentRung]] reports which rung a credit is standing on given days remaining, or null before the first.
- [[src/domain/ladder.ts#ladderSummary]] renders the table above for Settings.

## Schedule construction

[[src/domain/reminders.ts#buildSchedule]] turns `AppData` into a sorted list of reminders over a 200-day horizon. It is recomputed on every data change, so a stale schedule is never more than one write away from correct.

A credit is skipped when reminders are disabled, the credit is inactive or manual, the credit or its card is muted, the credit's value is below `minValueCents`, or it is locked and enrolment reminders are off. For each remaining cycle in the horizon with money still unclaimed, each rung fires at `cycle.end - daysBefore`, at the user's `timeOfDay` in local time. Rungs already in the past are dropped.

### Grouping

Reminders are grouped by the day and tone they fire on, not emitted per credit. A household with two premium cards can have a dozen credits lapsing in one week, and a dozen separate alerts is how an app gets muted.

The group key `${fireOn}|${tone}` becomes the reminder's `id` and notification `tag`. Ids are therefore stable across recomputes: the worker dedupes on them, and a reminder that changed identity every launch would fire again each time. Items within a group sort by remaining value, biggest first, and a group whose total falls below the minimum-value floor is dropped.

### Notification copy

One decision per notification. The title leads with the total at stake and the rung's urgency; the body leads with the single biggest loss.

- When more than half the money in a group is locked, the title becomes "$X is still locked": telling someone to spend money they cannot reach is worse than silence.
- `permissive` reads "$X just opened"; `notice` reads "$X on the line — one week left"; `urgent` reads "$X expires tonight" on the last day.
- A single-item body names the credit, merchant and holder; a multi-item body names the largest and counts the rest.

## Delivery paths

No single delivery mechanism works everywhere, so there are two. The app is fully usable with only the second.

1. **Web Push** reaches a user whose browser is closed. It needs a server holding the VAPID private key: the client subscribes ([[src/services/notifications.ts#subscribeToPush]]) and ships the subscription to `VITE_PUSH_API` ([[src/services/notifications.ts#registerSubscription]]). Without `VITE_VAPID_PUBLIC_KEY` both are no-ops. The backend is not in this repository.
2. **Service-worker replay** needs no server. See [[reminders#Service-worker replay]].

Enabling reminders in Settings is a three-step negotiation: ask notification permission, subscribe to push where configured, and request Periodic Background Sync ([[src/services/notifications.ts#requestPeriodicSync]], Chromium-only, installed apps only, 12-hour minimum interval). Only the first can fail in a way the user needs to hear about.

**iOS** only delivers notifications to apps added to the Home Screen. [[src/services/notifications.ts#requiresInstallFirst]] detects an iOS browser that is not standalone, and Settings says so before asking for permission. Periodic Sync is unavailable on iOS, so replay on launch is the path there.

## Service-worker replay

The app writes the computed schedule to IndexedDB under `reminder-schedule` ([[src/services/notifications.ts#publishSchedule]]) and pings the worker. The worker fires anything that came due whenever it is woken, by Periodic Sync, by a push, or simply by the app being opened.

[[src/sw.ts#deliverDueReminders]] runs on `activate`, `periodicsync`, `sync`, on `schedule-updated` and `check-reminders` messages, and on a push with no payload. A reminder is due ([[src/sw.ts#isDue]]) when it has not been shown, its `fireAt` has passed, and it is less than 36 hours old. Anything older is dropped: the device slept through it, the deadline has moved, and the schedule has been rebuilt. The pure equivalent, [[src/domain/reminders.ts#dueReminders]], is what the tests cover.

Shown ids are recorded under `reminders-shown` and pruned after 14 days: long enough to prevent repeats, short enough not to grow forever.

Other behaviours the worker owns:

- Notifications worth $50 or more set `requireInteraction`. Expiring money is worth a buzz; the user can turn reminders off.
- The app badge shows the count of reminders whose time has passed, where the Badging API exists.
- "Remind me tomorrow" ([[src/sw.ts#snoozeUntilTomorrow]]) pushes one reminder 24 hours out and clears its shown mark, without touching the rest of the schedule.
- Tapping a notification focuses an existing window and posts a `navigate` message rather than opening another, because on Android the app is usually already open behind the shade.

### Push with a payload

A server-sent push carrying JSON is shown as-is. The payload is a ready-made notification so the worker never re-derives anything; a push without a payload is a nudge to replay the local schedule.

## Nudge preview

Notification permission is a big ask on faith. The "Preview nudge" button on Today shows the next real reminder from the stored schedule, with the user's own numbers, in-app and without permission.

When nothing is scheduled yet, [[src/ui/NudgePreview.tsx#sampleReminder]] builds a stand-in from the claimable total.
