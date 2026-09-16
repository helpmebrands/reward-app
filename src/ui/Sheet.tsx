import { createEffect, createSignal, type JSX, onCleanup, Show } from 'solid-js'
import { Portal } from 'solid-js/web'
import './Sheet.css'

/**
 * A modal bottom sheet.
 *
 * Material's sheet behaviour on Nocturne's surfaces: a drag handle that
 * actually drags, dismissal by flick or by distance, a scrim that closes on
 * tap, Escape to close, and a focus trap so a keyboard user cannot tab out into
 * the screen behind.
 *
 * The drag listens on the handle area only. Dragging from anywhere would fight
 * the sheet's own scrolling, which matters here because the credit sheet is
 * taller than the screen.
 */

interface SheetProps {
  open: boolean
  onClose: () => void
  /** Announced as the dialog's name. */
  title: string
  children: JSX.Element
}

/** Drag distance past which releasing dismisses. */
const DISMISS_DISTANCE = 110
/** px/ms downward flick that dismisses regardless of distance. */
const DISMISS_VELOCITY = 0.5

export function Sheet(props: SheetProps) {
  const [dragOffset, setDragOffset] = createSignal(0)
  const [dragging, setDragging] = createSignal(false)
  let panel: HTMLDivElement | undefined
  let previouslyFocused: HTMLElement | null = null

  let startY = 0
  let lastY = 0
  let lastTime = 0
  let velocity = 0

  function onHandleDown(event: PointerEvent) {
    startY = event.clientY
    lastY = event.clientY
    lastTime = event.timeStamp
    velocity = 0
    setDragging(true)
    ;(event.currentTarget as HTMLElement).setPointerCapture(event.pointerId)
  }

  function onHandleMove(event: PointerEvent) {
    if (!dragging()) return
    const elapsed = event.timeStamp - lastTime
    if (elapsed > 0) velocity = (event.clientY - lastY) / elapsed
    lastY = event.clientY
    lastTime = event.timeStamp
    // Downward only: dragging up would detach the sheet from its own edge.
    setDragOffset(Math.max(0, event.clientY - startY))
  }

  function onHandleUp() {
    if (!dragging()) return
    setDragging(false)
    const dismissed = dragOffset() > DISMISS_DISTANCE || velocity > DISMISS_VELOCITY
    setDragOffset(0)
    if (dismissed) props.onClose()
  }

  function onKeyDown(event: KeyboardEvent) {
    if (event.key === 'Escape') {
      event.stopPropagation()
      props.onClose()
      return
    }
    if (event.key !== 'Tab' || !panel) return

    // Focus trap: wrap at both ends of the sheet's own focusable elements.
    const focusable = panel.querySelectorAll<HTMLElement>(
      'a[href], button:not([disabled]), input:not([disabled]), select, textarea, [tabindex]:not([tabindex="-1"])',
    )
    const first = focusable[0]
    const last = focusable[focusable.length - 1]
    if (!first || !last) return

    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault()
      last.focus()
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault()
      first.focus()
    }
  }

  createEffect(() => {
    if (!props.open) return
    previouslyFocused = document.activeElement as HTMLElement | null
    // Stop the screen behind from scrolling under the sheet.
    const previousOverflow = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    // Move focus in so a screen reader lands on the sheet, not the page.
    queueMicrotask(() => panel?.focus())

    onCleanup(() => {
      document.body.style.overflow = previousOverflow
      previouslyFocused?.focus()
    })
  })

  return (
    <Show when={props.open}>
      <Portal>
        <div
          class="sheet"
          role="dialog"
          aria-modal="true"
          aria-label={props.title}
          onKeyDown={onKeyDown}
        >
          <button
            type="button"
            class="sheet__scrim"
            aria-label="Close"
            onClick={() => props.onClose()}
          />
          <div
            ref={panel}
            class="sheet__panel"
            classList={{ 'sheet__panel--dragging': dragging() }}
            style={{ transform: `translateY(${dragOffset()}px)` }}
            tabindex={-1}
          >
            <div
              class="sheet__grip"
              onPointerDown={onHandleDown}
              onPointerMove={onHandleMove}
              onPointerUp={onHandleUp}
              onPointerCancel={onHandleUp}
            >
              <span class="sheet__handle" />
            </div>
            <div class="sheet__body">{props.children}</div>
          </div>
        </div>
      </Portal>
    </Show>
  )
}
