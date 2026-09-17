import {
  type Accessor,
  createContext,
  createSignal,
  onCleanup,
  type ParentProps,
  Show,
  useContext,
} from 'solid-js'
import { Portal } from 'solid-js/web'
import './Snackbar.css'

/**
 * Snackbars with an undo affordance.
 *
 * Logging a credit is the app's main destructive-feeling action, and it is far
 * more common than correcting one. So the flow is optimistic — the claim is
 * written immediately and the snackbar offers to take it back — rather than
 * asking "are you sure?" every time, which would tax the common case to protect
 * the rare one.
 */

export interface SnackbarAction {
  label: string
  /** Accessible name when the label alone ("Undo") does not say what it undoes. */
  ariaLabel?: string
  onAct: () => void
}

interface SnackbarMessage {
  id: number
  text: string
  action?: SnackbarAction
}

export interface SnackbarApi {
  /** Shows a message. `action` is usually an undo. */
  show(text: string, action?: SnackbarAction): void
  current: Accessor<SnackbarMessage | null>
}

const SnackbarContext = createContext<SnackbarApi>()

/**
 * How long a snackbar with an action stays up. Material says six seconds;
 * WCAG 2.2.1 says a time limit the user cannot adjust must be generous, so
 * an undo gets twenty, and the clock stops while the pointer or focus is on
 * it and restarts in full when they leave.
 */
const DURATION_WITH_ACTION = 20_000
const DURATION_PLAIN = 3500

export function SnackbarProvider(props: ParentProps) {
  const [current, setCurrent] = createSignal<SnackbarMessage | null>(null)
  let nextId = 0
  let timer: ReturnType<typeof setTimeout> | undefined

  function dismiss() {
    clearTimeout(timer)
    setCurrent(null)
  }

  function duration() {
    return current()?.action ? DURATION_WITH_ACTION : DURATION_PLAIN
  }

  function pause() {
    clearTimeout(timer)
  }

  function resume() {
    clearTimeout(timer)
    if (current()) timer = setTimeout(dismiss, duration())
  }

  const api: SnackbarApi = {
    current,
    show(text, action) {
      const message: SnackbarMessage = { id: nextId++, text, ...(action ? { action } : {}) }
      setCurrent(message)
      resume()
    },
  }

  onCleanup(() => clearTimeout(timer))

  return (
    <SnackbarContext.Provider value={api}>
      {props.children}
      <Portal>
        <Show when={current()}>
          {(message) => (
            <div
              class="snackbar"
              role="status"
              aria-live="polite"
              onMouseEnter={pause}
              onMouseLeave={resume}
              onFocusIn={pause}
              onFocusOut={resume}
            >
              <span class="snackbar__text">{message().text}</span>
              <Show when={message().action}>
                {(action) => (
                  <button
                    type="button"
                    class="snackbar__action"
                    aria-label={action().ariaLabel}
                    onClick={() => {
                      action().onAct()
                      dismiss()
                    }}
                  >
                    {action().label}
                  </button>
                )}
              </Show>
            </div>
          )}
        </Show>
      </Portal>
    </SnackbarContext.Provider>
  )
}

export function useSnackbar(): SnackbarApi {
  const api = useContext(SnackbarContext)
  if (!api) throw new Error('useSnackbar must be used inside <SnackbarProvider>')
  return api
}
