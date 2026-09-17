import { useNavigate } from '@solidjs/router'
import { createResource, createSignal, For, Show } from 'solid-js'
import { formatMoney } from '../domain/format.ts'
import { defaultLadder } from '../domain/ladder.ts'
import type { Cadence } from '../domain/types.ts'
import {
  notificationSupport,
  publishSchedule,
  readSchedule,
  requestPeriodicSync,
  requestPermission,
  requiresInstallFirst,
  showTestNotification,
  subscribeToPush,
} from '../services/notifications.ts'
import { useApp } from '../stores/app.tsx'
import { Ph } from '../ui/Ph.tsx'
import { useSnackbar } from '../ui/Snackbar.tsx'
import { Switch } from '../ui/Switch.tsx'
import { TopBar } from '../ui/TopBar.tsx'
import './Settings.css'
import { useScreenTitle } from '../ui/useScreenTitle.ts'

const CADENCES: Cadence[] = ['monthly', 'quarterly', 'semiannual', 'annual']

export function Settings() {
  const app = useApp()
  useScreenTitle(() => 'Settings')
  const navigate = useNavigate()
  const snackbar = useSnackbar()

  const [permission, setPermission] = createSignal(notificationSupport())
  const [schedule, { refetch }] = createResource(readSchedule)
  let fileInput: HTMLInputElement | undefined

  const notifications = () => app.data.settings.notifications

  /**
   * Turning reminders on is a three-step negotiation with the browser: ask for
   * permission, subscribe to push where a server is configured, and request
   * periodic background sync. Only the first can fail in a way the user needs
   * to hear about — the other two degrade to service-worker replay.
   */
  async function enableNotifications() {
    if (requiresInstallFirst()) {
      snackbar.show(
        'On iOS, add HelpMe Reward to your Home Screen first — then reminders can arrive.',
      )
      return
    }

    const result = await requestPermission()
    setPermission(result)

    if (result !== 'granted') {
      snackbar.show(
        result === 'denied'
          ? 'Your browser is blocking notifications for this site. Re-allow them in site settings.'
          : 'Reminders stay off until notifications are allowed.',
      )
      return
    }

    app.updateNotificationSettings({ enabled: true })
    await subscribeToPush().catch(() => null)
    const periodic = await requestPeriodicSync()
    await publishSchedule(app.data)
    void refetch()

    snackbar.show(
      periodic
        ? 'Reminders on. They will arrive even when the app is closed.'
        : 'Reminders on. Anything due while the app was closed arrives when you next open it.',
    )
  }

  function disableNotifications() {
    app.updateNotificationSettings({ enabled: false })
    void publishSchedule({
      ...app.data,
      settings: { ...app.data.settings, notifications: { ...notifications(), enabled: false } },
    })
    void refetch()
    snackbar.show('Reminders off.')
  }

  function exportData() {
    const blob = new Blob([app.exportJson()], { type: 'application/json' })
    const url = URL.createObjectURL(blob)
    const link = document.createElement('a')
    link.href = url
    link.download = `cardvantage-${app.today()}.json`
    link.click()
    URL.revokeObjectURL(url)
  }

  async function importData(file: File) {
    try {
      app.importJson(await file.text())
      snackbar.show('Imported.')
    } catch (error) {
      snackbar.show(error instanceof Error ? error.message : 'That file could not be read.')
    }
  }

  return (
    <>
      <TopBar title="Settings" onBack={() => navigate(-1)} />

      <div class="screen__pad stack stack--loose">
        <section class="stack">
          <h2 class="section-title">Reminders</h2>

          <div class="panel row row--between">
            <span class="grow">
              <span style={{ display: 'block', 'font-size': '12px' }}>Send me reminders</span>
              <span class="section-note">
                <Show
                  when={permission() !== 'unsupported'}
                  fallback="This browser cannot show notifications."
                >
                  {permission() === 'denied'
                    ? 'Blocked in your browser settings.'
                    : 'A tiered ladder per credit, grouped so you get one alert, not twelve.'}
                </Show>
              </span>
            </span>
            <Switch
              label="Send me reminders"
              disabled={permission() === 'unsupported' || permission() === 'denied'}
              checked={notifications().enabled && permission() === 'granted'}
              onChange={(next) => (next ? void enableNotifications() : disableNotifications())}
            />
          </div>

          <Show when={requiresInstallFirst()}>
            <div class="panel row" style={{ 'align-items': 'flex-start' }}>
              <Ph name="device-mobile" size={15} color="var(--tone-locked-fg)" />
              <p class="grow section-note">
                iOS only delivers notifications to apps on the Home Screen. Tap Share, then{' '}
                <strong>Add to Home Screen</strong>, and open HelpMe Reward from there.
              </p>
            </div>
          </Show>

          <Show when={notifications().enabled}>
            <div class="field">
              <label class="field__label" for="time-of-day">
                Send them at
              </label>
              <input
                id="time-of-day"
                class="input numeric"
                type="time"
                value={notifications().timeOfDay}
                onInput={(e) => {
                  app.updateNotificationSettings({ timeOfDay: e.currentTarget.value })
                  void publishSchedule(app.data).then(() => refetch())
                }}
              />
            </div>

            <div class="field">
              <label class="field__label" for="min-value">
                Ignore anything under
              </label>
              <input
                id="min-value"
                class="input numeric"
                type="number"
                min="0"
                step="1"
                value={(notifications().minValueCents / 100).toString()}
                onInput={(e) =>
                  app.updateNotificationSettings({
                    minValueCents: Math.round(Number(e.currentTarget.value || 0) * 100),
                  })
                }
              />
            </div>

            <div class="panel row row--between">
              <span class="grow">
                <span style={{ display: 'block', 'font-size': '12px' }}>
                  Nudge me about locked credits
                </span>
                <span class="section-note">
                  Credits stuck behind an enrolment box. Off means silence about money you cannot
                  yet spend.
                </span>
              </span>
              <Switch
                label="Nudge me about locked credits"
                checked={notifications().enrollmentReminder}
                onChange={(next) => app.updateNotificationSettings({ enrollmentReminder: next })}
              />
            </div>

            <button
              type="button"
              class="btn btn--block"
              onClick={() => void showTestNotification()}
            >
              <Ph name="bell-ringing" size={14} />
              Send a test notification
            </button>

            <Show when={schedule()}>
              {(current) => (
                <p class="section-note">
                  {current().reminders.length} reminders scheduled.
                  <Show when={current().reminders[0]}>
                    {(next) => (
                      <>
                        {' '}
                        Next on {new Date(next().fireAt).toLocaleDateString()} for{' '}
                        {formatMoney(next().totalCents)}.
                      </>
                    )}
                  </Show>
                </p>
              )}
            </Show>
          </Show>
        </section>

        <section class="stack">
          <h2 class="section-title">The ladder</h2>
          <p class="section-note">
            Each cadence gets rungs sized to its window, easing from a permissive heads-up to a last
            call. A single credit can be set to last-call-only from its own sheet.
          </p>
          <div class="stack stack--tight">
            <For each={CADENCES}>
              {(cadence) => (
                <div class="ladder-preset">
                  <span class="ladder-preset__name">{cadence}</span>
                  <span class="ladder-preset__rungs">
                    <For each={defaultLadder(cadence)}>
                      {(rung) => (
                        <span class={`ladder-preset__rung ladder-preset__rung--${rung.tone}`}>
                          {rung.daysBefore === 0 ? 'last day' : `${rung.daysBefore}d`}
                        </span>
                      )}
                    </For>
                  </span>
                </div>
              )}
            </For>
          </div>
        </section>

        <section class="stack">
          <h2 class="section-title">Appearance</h2>
          <div class="seg">
            <For each={['system', 'dark', 'light'] as const}>
              {(theme) => (
                <button
                  type="button"
                  class="seg__opt"
                  aria-pressed={app.data.settings.theme === theme}
                  onClick={() => app.updateSettings({ theme })}
                >
                  {theme[0]?.toUpperCase()}
                  {theme.slice(1)}
                </button>
              )}
            </For>
          </div>
          <p class="section-note">
            Nocturne is a dark system; the light theme lifts the same ramps rather than inventing a
            second palette.
          </p>
        </section>

        <section class="stack">
          <h2 class="section-title">Your data</h2>
          <p class="section-note">
            Everything lives on this device. Nothing is uploaded, and there is no account — so an
            export is the only backup.
          </p>
          <button type="button" class="btn btn--block" onClick={exportData}>
            <Ph name="download-simple" size={14} />
            Export a backup
          </button>
          <button type="button" class="btn btn--block" onClick={() => fileInput?.click()}>
            <Ph name="upload-simple" size={14} />
            Import a backup
          </button>
          <input
            ref={fileInput}
            type="file"
            accept="application/json"
            class="visually-hidden"
            onChange={(e) => {
              const file = e.currentTarget.files?.[0]
              if (file) void importData(file)
              e.currentTarget.value = ''
            }}
          />
        </section>
      </div>
    </>
  )
}
