import { createEffect, onCleanup, Show } from 'solid-js'
import { formatMoney } from '../domain/format.ts'
import type { Reminder } from '../domain/reminders.ts'
import { Ph } from './Ph.tsx'
import './NudgePreview.css'

/**
 * An in-app preview of the next reminder.
 *
 * Reminders are the app's whole reason to exist, and most people will not grant
 * notification permission on faith. Showing exactly what one looks like — with
 * the user's own numbers — is the honest way to ask.
 */

interface NudgePreviewProps {
  reminder: Reminder | null
  onDismiss: () => void
  onOpen: () => void
}

export function NudgePreview(props: NudgePreviewProps) {
  createEffect(() => {
    if (!props.reminder) return
    const timer = setTimeout(props.onDismiss, 6000)
    onCleanup(() => clearTimeout(timer))
  })

  return (
    <Show when={props.reminder}>
      {(reminder) => (
        <div class="nudge" role="status">
          <button type="button" class="nudge__body" onClick={props.onOpen}>
            <span class="nudge__glyph">
              <Ph
                name={reminder().tone === 'urgent' ? 'warning' : 'hourglass-high'}
                fill={reminder().tone === 'urgent'}
                size={17}
              />
            </span>
            <span class="grow">
              <span class="nudge__meta">
                <span>Cardvantage</span>
                <span class="muted">preview</span>
              </span>
              <span class="nudge__title">{reminder().title}</span>
              <span class="nudge__text">{reminder().body}</span>
            </span>
          </button>
          <button
            type="button"
            class="icon-btn nudge__close"
            aria-label="Dismiss preview"
            onClick={props.onDismiss}
          >
            <Ph name="x" size={13} />
          </button>
        </div>
      )}
    </Show>
  )
}

/** A stand-in used when nothing is actually scheduled yet. */
export function sampleReminder(claimableCents: number): Reminder {
  return {
    id: 'preview',
    fireAt: Date.now(),
    tag: 'preview',
    url: '/',
    tone: 'notice',
    totalCents: claimableCents,
    items: [],
    title:
      claimableCents > 0
        ? `${formatMoney(claimableCents)} on the line — one week left`
        : 'Nothing expiring yet',
    body:
      claimableCents > 0
        ? 'This is the shape of the nudge: one alert for the day, leading with the credit you stand to lose most on.'
        : 'Add a card and this is where the week-out warning will appear.',
  }
}
