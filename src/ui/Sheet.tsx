import { createEffect, createSignal, type JSX, onCleanup, Show } from 'solid-js'
import { Portal } from 'solid-js/web'
import { createBreakpoint } from './useBreakpoint.ts'
import './Sheet.css'

/**
 * A modal sheet, in the shape the width calls for.
 *
 * On a phone it is Material's bottom sheet on Nocturne's surfaces: a drag
 * handle that actually drags, dismissal by flick or by distance, a scrim that
 * closes on tap. From 600px it is a centred dialog, and from 1024px it can be
 * a panel docked on the trailing edge so the list beside it stays usable.
 * All three keep role="dialog", aria-modal, Escape to close, a focus trap so
 * a keyboard user cannot tab out into the screen behind, and focus returned
 * on close; only the geometry and the drag handle change.
 *
 * The drag listens on the handle area only. Dragging from anywhere would fight
 * the sheet's own scrolling, which matters here because the credit sheet is
 * taller than the screen.
 */

export type SheetPresentation = 'bottom' | 'dialog' | 'panel'

interface SheetProps {
  open: boolean
  onClose: () => void
  /** Announced as the dialog's name. */
  title: string
  /** What the sheet becomes at expanded width. A dialog unless said otherwise. */
  wide?: 'dialog' | 'panel'
  children: JSX.Element
}

/** Drag distance past which releasing dismisses. */
const DISMISS_DISTANCE = 110
/** px/ms downward flick that dismisses regardless of distance. */
const DISMISS_VELOCITY = 0.5

export function Sheet(props: SheetProps) {
  const breakpoint = createBreakpoint()
  const presentation = (): SheetPresentation => {
    const at = breakpoint()
    if (at === 'compact') return 'bottom'
    if (at === 'expanded') return props.wide ?? 'dialog'
    return 'dialog'
  }
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

  // A docked panel takes a column of the shell, so the list beside it is
  // narrower rather than covered. The shell's grid reads this class.
  createEffect(() => {
    if (!(props.open && presentation() === 'panel')) return
    document.body.classList.add('has-panel')
    onCleanup(() => document.body.classList.remove('has-panel'))
  })

  return (
    <Show when={props.open}>
      <Portal>
        <div
          class={`sheet sheet--${presentation()}`}
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
            style={
              presentation() === 'bottom' ? { transform: `translateY(${dragOffset()}px)` } : {}
            }
            tabindex={-1}
          >
            {/* Only a bottom sheet has anything to drag. */}
            <Show when={presentation() === 'bottom'}>
              <div
                class="sheet__grip"
                onPointerDown={onHandleDown}
                onPointerMove={onHandleMove}
                onPointerUp={onHandleUp}
                onPointerCancel={onHandleUp}
              >
                <span class="sheet__handle" />
              </div>
            </Show>
            <div class="sheet__body">{props.children}</div>
          </div>
        </div>
      </Portal>
    </Show>
  )
}
