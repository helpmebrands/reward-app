# Reminder delivery

How the PWA gets a reminder from the computed schedule ([[reminders#Schedule construction]]) to the user: Web Push where a server exists, and service-worker replay everywhere.

## Delivery paths

No single delivery mechanism works everywhere, so there are two. The app is fully usable with only the second.

1. **Web Push** reaches a user whose browser is closed. It needs a server holding the VAPID private key: the client subscribes ([[apps/pwa/src/services/notifications.ts#subscribeToPush]]) and ships the subscription to `VITE_PUSH_API` ([[apps/pwa/src/services/notifications.ts#registerSubscription]]). Without `VITE_VAPID_PUBLIC_KEY` both are no-ops. The backend is not in this repository.
2. **Service-worker replay** needs no server. See [[delivery#Service-worker replay]].

Enabling reminders in Settings is a three-step negotiation: ask notification permission, subscribe to push where configured, and request Periodic Background Sync ([[apps/pwa/src/services/notifications.ts#requestPeriodicSync]], Chromium-only, installed apps only, 12-hour minimum interval). Only the first can fail in a way the user needs to hear about.

**iOS** only delivers notifications to apps added to the Home Screen. [[apps/pwa/src/services/notifications.ts#requiresInstallFirst]] detects an iOS browser that is not standalone, and Settings says so before asking for permission. Periodic Sync is unavailable on iOS, so replay on launch is the path there.

## Service-worker replay

The app writes the computed schedule to IndexedDB under `reminder-schedule` ([[apps/pwa/src/services/notifications.ts#publishSchedule]]) and pings the worker. The worker fires anything that came due whenever it is woken, by Periodic Sync, by a push, or simply by the app being opened.

[[apps/pwa/src/sw.ts#deliverDueReminders]] runs on `activate`, `periodicsync`, `sync`, on `schedule-updated` and `check-reminders` messages, and on a push with no payload. A reminder is due ([[apps/pwa/src/sw.ts#isDue]]) when it has not been shown, its `fireAt` has passed, and it is less than 36 hours old. Anything older is dropped: the device slept through it, the deadline has moved, and the schedule has been rebuilt. The pure equivalent, [[apps/pwa/src/domain/reminders.ts#dueReminders]], is what the tests cover.

Shown ids are recorded under `reminders-shown` and pruned after 14 days: long enough to prevent repeats, short enough not to grow forever.

Other behaviours the worker owns:

- Notifications worth $50 or more set `requireInteraction`. Expiring money is worth a buzz; the user can turn reminders off.
- The app badge shows the count of reminders whose time has passed, where the Badging API exists.
- "Remind me tomorrow" ([[apps/pwa/src/sw.ts#snoozeUntilTomorrow]]) pushes one reminder 24 hours out and clears its shown mark, without touching the rest of the schedule.
- Tapping a notification focuses an existing window and posts a `navigate` message rather than opening another, because on Android the app is usually already open behind the shade.

### Push with a payload

A server-sent push carrying JSON is shown as-is. The payload is a ready-made notification so the worker never re-derives anything; a push without a payload is a nudge to replay the local schedule.
