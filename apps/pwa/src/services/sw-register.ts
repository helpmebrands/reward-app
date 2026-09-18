import { registerSW } from 'virtual:pwa-register'

/**
 * Service-worker registration.
 *
 * Reminders are time-critical: a tab left open for a week on an old worker
 * would keep replaying a stale schedule. So a waiting update is activated
 * straight away rather than waiting for every tab to close. There is no
 * server-side state to be out of step with, and the app re-reads its data from
 * IndexedDB on load, so an immediate swap is safe.
 */
export function registerServiceWorker(): void {
  if (import.meta.env.DEV && !import.meta.env.VITE_ENABLE_SW) return

  const updateSW = registerSW({
    immediate: true,
    onNeedRefresh() {
      void updateSW(true)
    },
    onRegisteredSW(_url, registration) {
      // Ask the worker to fire anything that came due while the app was shut.
      registration?.active?.postMessage({ type: 'check-reminders' })
    },
    onRegisterError(error) {
      console.error('Service worker registration failed', error)
    },
  })
}
