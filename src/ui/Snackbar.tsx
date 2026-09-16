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
  onAct: () => void
}

interface SnackbarMessage {
  id: number
  text: string
  action?: SnackbarAction
}

interface SnackbarApi {
  /** Shows a message. `action` is usually an undo. */
  show(text: string, action?: SnackbarAction): void
  current: Accessor<SnackbarMessage | null>
}

const SnackbarContext = createContext<SnackbarApi>()

/** How long a snackbar with an action stays up, per Material's long duration. */
const DURATION_WITH_ACTION = 6000
const DURATION_PLAIN = 3500

export function SnackbarProvider(props: ParentProps) {
  const [current, setCurrent] = createSignal<SnackbarMessage | null>(null)
  let nextId = 0
  let timer: ReturnType<typeof setTimeout> | undefined

  function dismiss() {
    clearTimeout(timer)
    setCurrent(null)
  }

  const api: SnackbarApi = {
    current,
    show(text, action) {
      clearTimeout(timer)
      const message: SnackbarMessage = { id: nextId++, text, ...(action ? { action } : {}) }
      setCurrent(message)
      timer = setTimeout(dismiss, action ? DURATION_WITH_ACTION : DURATION_PLAIN)
    },
  }

  onCleanup(() => clearTimeout(timer))

  return (
    <SnackbarContext.Provider value={api}>
      {props.children}
      <Portal>
        <Show when={current()}>
          {(message) => (
            <div class="snackbar" role="status" aria-live="polite">
              <span class="snackbar__text">{message().text}</span>
              <Show when={message().action}>
                {(action) => (
                  <button
                    type="button"
                    class="snackbar__action"
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
