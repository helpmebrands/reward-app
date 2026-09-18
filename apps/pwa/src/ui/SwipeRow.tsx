import { createSignal, type JSX, onCleanup, Show } from 'solid-js'
import './SwipeRow.css'

/**
 * A row with swipe actions.
 *
 * Material's swipe-to-act pattern, with the behaviours that make it usable on a
 * real phone rather than only on a trackpad:
 *
 *   - **Direction locking.** The gesture only becomes a swipe once horizontal
 *     movement clearly beats vertical, so a fast flick down the list never
 *     half-opens a row.
 *   - **Rubber-banding** past the action width, so the row feels attached to
 *     the finger instead of hitting a wall.
 *   - **Commit on velocity or distance**, because a quick flick is a deliberate
 *     act even when it is short.
 *   - **A visible resting state.** Releasing past the threshold parks the row
 *     open with the button exposed, rather than firing on release: an
 *     irreversible action should not be one accidental flick away.
 *
 * Pointer Events cover touch, pen and mouse in one path. Every action is also
 * reachable without the gesture — the detail sheet carries the same buttons —
 * because swipe is an accelerator, never the only route.
 */

export interface SwipeAction {
  label: string
  /** Phosphor icon name. */
  icon: string
  /** `accent` for the constructive action, `quiet` for a reversible one. */
  tone?: 'accent' | 'quiet' | 'locked'
  onAct: () => void
}

interface SwipeRowProps {
  children: JSX.Element
  /** Revealed by swiping right (row moves right). */
  leading?: SwipeAction
  /** Revealed by swiping left (row moves left). */
  trailing?: SwipeAction
  /** Disables the gesture, e.g. for rows with nothing to act on. */
  disabled?: boolean
  class?: string
}

/** How far the row travels to fully expose an action. */
const ACTION_WIDTH = 84
/** Horizontal movement needed before the gesture counts as a swipe. */
const DIRECTION_LOCK = 10
/** Past this fraction of the action width, releasing parks the row open. */
const COMMIT_RATIO = 0.55
/** px/ms past which a short flick still commits. */
const FLICK_VELOCITY = 0.45

export function SwipeRow(props: SwipeRowProps) {
  const [offset, setOffset] = createSignal(0)
  const [dragging, setDragging] = createSignal(false)

  let startX = 0
  let startY = 0
  let lastX = 0
  let lastTime = 0
  let velocity = 0
  let axis: 'none' | 'horizontal' | 'vertical' = 'none'
  let pointerId: number | null = null

  const openWidth = () => Math.abs(offset())
  const direction = () => (offset() > 0 ? 'leading' : offset() < 0 ? 'trailing' : null)

  function reset() {
    setOffset(0)
    axis = 'none'
    pointerId = null
  }

  function available(delta: number): boolean {
    return delta > 0 ? Boolean(props.leading) : Boolean(props.trailing)
  }

  /** Resistance past the action width, so the row never feels unbounded. */
  function rubberBand(delta: number): number {
    const limit = ACTION_WIDTH
    if (Math.abs(delta) <= limit) return delta
    const excess = Math.abs(delta) - limit
    return Math.sign(delta) * (limit + excess * 0.28)
  }

  function onPointerDown(event: PointerEvent) {
    if (props.disabled || event.pointerType === 'mouse') return
    startX = event.clientX
    startY = event.clientY
    lastX = event.clientX
    lastTime = event.timeStamp
    velocity = 0
    axis = 'none'
    pointerId = event.pointerId
  }

  function onPointerMove(event: PointerEvent) {
    if (pointerId !== event.pointerId) return

    const dx = event.clientX - startX
    const dy = event.clientY - startY

    if (axis === 'none') {
      if (Math.abs(dy) > DIRECTION_LOCK && Math.abs(dy) > Math.abs(dx)) {
        // A vertical scroll: bow out entirely and let the list take it.
        axis = 'vertical'
        return
      }
      if (Math.abs(dx) < DIRECTION_LOCK) return
      axis = 'horizontal'
      setDragging(true)
      // Capture only once the swipe is committed, so scrolling is never stolen.
      ;(event.currentTarget as HTMLElement).setPointerCapture(event.pointerId)
    }

    if (axis !== 'horizontal') return

    const elapsed = event.timeStamp - lastTime
    if (elapsed > 0) velocity = (event.clientX - lastX) / elapsed
    lastX = event.clientX
    lastTime = event.timeStamp

    // Subtract the lock distance so the row starts moving from the finger.
    const travel = dx - Math.sign(dx) * DIRECTION_LOCK
    setOffset(available(travel) ? rubberBand(travel) : 0)
  }

  function onPointerUp(event: PointerEvent) {
    if (pointerId !== event.pointerId) return
    const wasHorizontal = axis === 'horizontal'
    setDragging(false)

    if (!wasHorizontal) {
      reset()
      return
    }

    const travelled = offset()
    const flicked =
      Math.abs(velocity) > FLICK_VELOCITY && Math.sign(velocity) === Math.sign(travelled)
    const committed = Math.abs(travelled) > ACTION_WIDTH * COMMIT_RATIO || flicked

    // Park open rather than firing: an action a flick away should still need a
    // deliberate tap.
    setOffset(committed && available(travelled) ? Math.sign(travelled) * ACTION_WIDTH : 0)
    axis = 'none'
    pointerId = null
  }

  function act(action: SwipeAction) {
    action.onAct()
    reset()
  }

  // A tap anywhere else closes an open row, matching every native list.
  function onDocumentPointerDown(event: PointerEvent) {
    if (offset() === 0) return
    const target = event.target as HTMLElement | null
    if (target?.closest('[data-swipe-open="true"]')) return
    reset()
  }

  document.addEventListener('pointerdown', onDocumentPointerDown, true)
  onCleanup(() => document.removeEventListener('pointerdown', onDocumentPointerDown, true))

  return (
    <div
      class={`swipe${props.class ? ` ${props.class}` : ''}`}
      data-swipe-open={offset() !== 0 ? 'true' : 'false'}
    >
      <Show when={props.leading}>
        {(action) => (
          <button
            type="button"
            class={`swipe__action swipe__action--leading swipe__action--${
              action().tone ?? 'accent'
            }`}
            style={{ width: `${Math.max(openWidth(), ACTION_WIDTH)}px` }}
            aria-hidden={direction() !== 'leading'}
            tabindex={direction() === 'leading' ? 0 : -1}
            onClick={() => act(action())}
          >
            <i class={`ph-fill ph-${action().icon}`} aria-hidden="true" />
            <span>{action().label}</span>
          </button>
        )}
      </Show>

      <Show when={props.trailing}>
        {(action) => (
          <button
            type="button"
            class={`swipe__action swipe__action--trailing swipe__action--${
              action().tone ?? 'quiet'
            }`}
            style={{ width: `${Math.max(openWidth(), ACTION_WIDTH)}px` }}
            aria-hidden={direction() !== 'trailing'}
            tabindex={direction() === 'trailing' ? 0 : -1}
            onClick={() => act(action())}
          >
            <i class={`ph-fill ph-${action().icon}`} aria-hidden="true" />
            <span>{action().label}</span>
          </button>
        )}
      </Show>

      <div
        class="swipe__content"
        classList={{ 'swipe__content--dragging': dragging() }}
        style={{ transform: `translate3d(${offset()}px, 0, 0)` }}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerUp}
        onPointerCancel={onPointerUp}
      >
        {props.children}
      </div>
    </div>
  )
}
