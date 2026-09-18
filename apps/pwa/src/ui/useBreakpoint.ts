import { type Accessor, createSignal, onCleanup } from 'solid-js'

export type Breakpoint = 'compact' | 'medium' | 'expanded'

/** The two widths from `tokens.css`; custom properties cannot be queried. */
const MEDIUM = '(min-width: 600px)'
const EXPANDED = '(min-width: 1024px)'

/**
 * Which of the three layouts the viewport is in, live.
 *
 * Components that change shape between breakpoints (the sheet) read this
 * rather than measuring themselves, so the breakpoints stay the ones the
 * token sheet defines.
 */
export function createBreakpoint(): Accessor<Breakpoint> {
  const medium = window.matchMedia(MEDIUM)
  const expanded = window.matchMedia(EXPANDED)
  const read = (): Breakpoint =>
    expanded.matches ? 'expanded' : medium.matches ? 'medium' : 'compact'

  const [breakpoint, setBreakpoint] = createSignal<Breakpoint>(read())
  const update = () => setBreakpoint(read())
  medium.addEventListener('change', update)
  expanded.addEventListener('change', update)
  onCleanup(() => {
    medium.removeEventListener('change', update)
    expanded.removeEventListener('change', update)
  })
  return breakpoint
}
