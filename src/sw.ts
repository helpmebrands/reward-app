/// <reference lib="webworker" />
import { createStore, get, set } from 'idb-keyval'
import {
  cleanupOutdatedCaches,
  createHandlerBoundToURL,
  precacheAndRoute,
} from 'workbox-precaching'
import { NavigationRoute, registerRoute } from 'workbox-routing'
import type { Reminder, ReminderSchedule } from './domain/reminders.ts'

declare const self: ServiceWorkerGlobalScope & {
  __WB_MANIFEST: Array<{ url: string; revision: string | null }>
}

/**
 * Cardvantage service worker.
 *
 * Beyond the usual precache, this worker owns reminder delivery. The app writes
 * a computed schedule to IndexedDB; the worker replays anything that has come
 * due whenever it is woken — by Periodic Background Sync, by a push, or simply
 * by the app being opened.
 */

precacheAndRoute(self.__WB_MANIFEST)
cleanupOutdatedCaches()

// Single-page app: every navigation resolves to the shell, which then routes
// client-side. Excludes API paths so a future push backend is not swallowed.
registerRoute(
  new NavigationRoute(createHandlerBoundToURL('index.html'), {
    denylist: [/^\/api\//],
  }),
)

const DB_NAME = 'cardvantage'
const STORE_NAME = 'state'
const SCHEDULE_KEY = 'reminder-schedule'
const SHOWN_KEY = 'reminders-shown'
const SYNC_TAG = 'cardvantage-reminders'

const store = createStore(DB_NAME, STORE_NAME)

const ICON = '/icons/icon-192.png'
const BADGE = '/icons/badge-72.png'

self.addEventListener('install', () => {
  // Reminders are time-critical; a worker waiting behind an old one can miss a
  // day, so new versions take over immediately.
  void self.skipWaiting()
})

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      await self.clients.claim()
      await deliverDueReminders()
    })(),
  )
})

interface ShownRecord {
  /** Reminder id -> when it was shown, so old entries can be pruned. */
  [id: string]: number
}

async function readShown(): Promise<ShownRecord> {
  return (await get<ShownRecord>(SHOWN_KEY, store)) ?? {}
}

async function markShown(ids: string[]): Promise<void> {
  const shown = await readShown()
  const now = Date.now()
  for (const id of ids) shown[id] = now
  // Keep a fortnight of history: long enough to prevent repeats, short enough
  // that the record cannot grow without bound.
  const cutoff = now - 14 * 24 * 60 * 60 * 1000
  for (const [id, at] of Object.entries(shown)) {
    if (at < cutoff) delete shown[id]
  }
  await set(SHOWN_KEY, shown, store)
}

function isDue(reminder: Reminder, now: number, shown: ShownRecord): boolean {
  if (shown[reminder.id]) return false
  if (reminder.fireAt > now) return false
  // Never surface something the device slept through for more than a day and a
  // half — by then the deadline has moved and the schedule has been rebuilt.
  return now - reminder.fireAt < 36 * 60 * 60 * 1000
}

async function deliverDueReminders(): Promise<number> {
  const schedule = await get<ReminderSchedule>(SCHEDULE_KEY, store)
  if (!schedule) return 0

  const now = Date.now()
  const shown = await readShown()
  const due = schedule.reminders.filter((reminder) => isDue(reminder, now, shown))
  if (due.length === 0) return 0

  for (const reminder of due) {
    await self.registration.showNotification(reminder.title, {
      body: reminder.body,
      tag: reminder.tag,
      icon: ICON,
      badge: BADGE,
      // Expiring money is worth a buzz; the user can turn reminders off.
      requireInteraction: reminder.totalCents >= 5000,
      data: { url: reminder.url, reminderId: reminder.id, items: reminder.items },
      actions: [
        { action: 'open', title: 'Review' },
        { action: 'snooze', title: 'Remind me tomorrow' },
      ],
    } as NotificationOptions)
  }

  await markShown(due.map((reminder) => reminder.id))
  await updateBadge(schedule, now)
  return due.length
}

/** Shows the count of currently-open reminders on the app icon, where supported. */
async function updateBadge(schedule: ReminderSchedule, now: number): Promise<void> {
  const navigatorWithBadge = self.navigator as Navigator & {
    setAppBadge?: (count?: number) => Promise<void>
    clearAppBadge?: () => Promise<void>
  }
  if (!navigatorWithBadge.setAppBadge) return
  const pending = schedule.reminders.filter((r) => r.fireAt <= now).length
  await (pending > 0
    ? navigatorWithBadge.setAppBadge(pending)
    : navigatorWithBadge.clearAppBadge?.()
  )?.catch(() => undefined)
}

self.addEventListener('periodicsync', (event) => {
  const syncEvent = event as ExtendableEvent & { tag?: string }
  if (syncEvent.tag !== SYNC_TAG) return
  syncEvent.waitUntil(deliverDueReminders())
})

self.addEventListener('sync', (event) => {
  const syncEvent = event as ExtendableEvent & { tag?: string }
  if (syncEvent.tag !== SYNC_TAG) return
  syncEvent.waitUntil(deliverDueReminders())
})

self.addEventListener('message', (event) => {
  const data = event.data as { type?: string } | undefined
  if (data?.type === 'schedule-updated' || data?.type === 'check-reminders') {
    event.waitUntil(deliverDueReminders())
  }
  if (data?.type === 'skip-waiting') void self.skipWaiting()
})

/**
 * Server-sent push. The payload is a ready-made notification so the worker does
 * not need to re-derive anything; a push with no payload is treated as a nudge
 * to replay the local schedule.
 */
self.addEventListener('push', (event) => {
  event.waitUntil(
    (async () => {
      if (!event.data) {
        await deliverDueReminders()
        return
      }

      let payload: { title?: string; body?: string; url?: string; tag?: string } = {}
      try {
        payload = event.data.json()
      } catch {
        payload = { body: event.data.text() }
      }

      await self.registration.showNotification(payload.title ?? 'Cardvantage', {
        body: payload.body ?? 'You have credits expiring soon.',
        tag: payload.tag ?? 'cardvantage-push',
        icon: ICON,
        badge: BADGE,
        data: { url: payload.url ?? '/' },
        actions: [{ action: 'open', title: 'Review' }],
      } as NotificationOptions)
    })(),
  )
})

self.addEventListener('notificationclick', (event) => {
  event.notification.close()
  const data = (event.notification.data ?? {}) as { url?: string; reminderId?: string }

  if (event.action === 'snooze') {
    event.waitUntil(snoozeUntilTomorrow(data.reminderId))
    return
  }

  const target = new URL(data.url ?? '/', self.location.origin).href
  event.waitUntil(
    (async () => {
      const clients = await self.clients.matchAll({ type: 'window', includeUncontrolled: true })
      // Focus an existing window rather than stacking new ones — on Android the
      // app is usually already open behind the notification shade.
      for (const client of clients) {
        if (client.url.startsWith(self.location.origin)) {
          await client.focus()
          client.postMessage({ type: 'navigate', url: data.url ?? '/' })
          return
        }
      }
      await self.clients.openWindow(target)
    })(),
  )
})

/** Pushes one reminder 24 hours out without touching the rest of the schedule. */
async function snoozeUntilTomorrow(reminderId: string | undefined): Promise<void> {
  if (!reminderId) return
  const schedule = await get<ReminderSchedule>(SCHEDULE_KEY, store)
  if (!schedule) return

  const reminder = schedule.reminders.find((r) => r.id === reminderId)
  if (!reminder) return
  reminder.fireAt = Date.now() + 24 * 60 * 60 * 1000

  const shown = await readShown()
  delete shown[reminderId]
  await set(SHOWN_KEY, shown, store)
  await set(SCHEDULE_KEY, schedule, store)
}
