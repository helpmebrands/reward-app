import { createStore, get, set } from 'idb-keyval'
import { buildSchedule, type ReminderSchedule } from '../domain/reminders.ts'
import type { AppData } from '../domain/types.ts'
import { DB_NAME, SCHEDULE_KEY, STORE_NAME } from './db.ts'

/**
 * Notification plumbing.
 *
 * Two delivery paths, because no single one works everywhere:
 *
 * 1. **Web Push** — the only path that reaches a user whose browser is closed.
 *    Requires a server holding the VAPID private key; the client just
 *    subscribes and hands the subscription over.
 * 2. **Service-worker replay** — the worker keeps the computed schedule and
 *    fires anything that came due while the app was closed, on the next
 *    Periodic Background Sync, push, or launch. This needs no server and is the
 *    fallback on iOS, where Periodic Sync is unavailable but the app is usually
 *    opened often enough for the catch-up to land.
 */

const store = createStore(DB_NAME, STORE_NAME)

export type PermissionState = NotificationPermission | 'unsupported'

export function notificationSupport(): PermissionState {
  if (typeof Notification === 'undefined' || !('serviceWorker' in navigator)) return 'unsupported'
  return Notification.permission
}

export function pushSupported(): boolean {
  return typeof PushManager !== 'undefined' && 'serviceWorker' in navigator
}

/**
 * iOS only allows notifications for apps added to the Home Screen, so the UI
 * needs to tell the user to install before asking for permission.
 */
export function requiresInstallFirst(): boolean {
  const isIos = /iPad|iPhone|iPod/.test(navigator.userAgent)
  const standalone =
    window.matchMedia('(display-mode: standalone)').matches ||
    ('standalone' in navigator && Boolean((navigator as { standalone?: boolean }).standalone))
  return isIos && !standalone
}

export async function requestPermission(): Promise<PermissionState> {
  if (notificationSupport() === 'unsupported') return 'unsupported'
  return await Notification.requestPermission()
}

/** Writes the schedule where the service worker can replay it. */
export async function publishSchedule(
  data: AppData,
  now: Date = new Date(),
): Promise<ReminderSchedule> {
  const schedule = buildSchedule(data, now)
  await set(SCHEDULE_KEY, schedule, store)
  const registration = await navigator.serviceWorker?.ready.catch(() => undefined)
  registration?.active?.postMessage({ type: 'schedule-updated' })
  return schedule
}

export async function readSchedule(): Promise<ReminderSchedule | undefined> {
  return await get<ReminderSchedule>(SCHEDULE_KEY, store)
}

/**
 * Asks for Periodic Background Sync, which lets the worker wake up daily and
 * fire due reminders without the app being open. Chromium-only, and only for
 * installed apps — failure here is expected and non-fatal.
 */
export async function requestPeriodicSync(): Promise<boolean> {
  try {
    const registration = await navigator.serviceWorker.ready
    const periodicSync = (
      registration as ServiceWorkerRegistration & {
        periodicSync?: {
          register(tag: string, options: { minInterval: number }): Promise<void>
        }
      }
    ).periodicSync
    if (!periodicSync) return false

    const status = await navigator.permissions
      .query({ name: 'periodic-background-sync' as PermissionName })
      .catch(() => undefined)
    if (status && status.state !== 'granted') return false

    await periodicSync.register('cardvantage-reminders', { minInterval: 12 * 60 * 60 * 1000 })
    return true
  } catch {
    return false
  }
}

function urlBase64ToUint8Array(base64: string): Uint8Array {
  const padded = base64.padEnd(base64.length + ((4 - (base64.length % 4)) % 4), '=')
  const raw = atob(padded.replace(/-/g, '+').replace(/_/g, '/'))
  return Uint8Array.from(raw, (char) => char.charCodeAt(0))
}

/**
 * Subscribes to Web Push. Returns the subscription so the caller can ship it to
 * a backend; without `VITE_VAPID_PUBLIC_KEY` configured this is a no-op and the
 * app falls back to service-worker replay.
 */
export async function subscribeToPush(): Promise<PushSubscription | null> {
  const publicKey = import.meta.env.VITE_VAPID_PUBLIC_KEY
  if (!publicKey || !pushSupported()) return null

  const registration = await navigator.serviceWorker.ready
  const existing = await registration.pushManager.getSubscription()
  if (existing) return existing

  return await registration.pushManager.subscribe({
    userVisibleOnly: true,
    applicationServerKey: urlBase64ToUint8Array(publicKey) as BufferSource,
  })
}

export async function unsubscribeFromPush(): Promise<void> {
  const registration = await navigator.serviceWorker.ready
  const subscription = await registration.pushManager.getSubscription()
  await subscription?.unsubscribe()
}

/**
 * Hands the subscription to the backend. Left as an explicit, failure-tolerant
 * step: the app is fully usable without a push server.
 */
export async function registerSubscription(subscription: PushSubscription): Promise<boolean> {
  const endpoint = import.meta.env.VITE_PUSH_API
  if (!endpoint) return false
  try {
    const response = await fetch(`${endpoint}/subscriptions`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(subscription),
    })
    return response.ok
  } catch {
    return false
  }
}

/** Fires a notification immediately, for the "send a test" affordance. */
export async function showTestNotification(): Promise<void> {
  const registration = await navigator.serviceWorker.ready
  await registration.showNotification('HelpMe Reward reminders are on', {
    body: 'This is what an expiring-credit alert will look like.',
    tag: 'cardvantage-test',
    icon: '/icons/icon-192.png',
    badge: '/icons/badge-72.png',
  })
}
