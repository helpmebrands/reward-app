import { render, screen } from '@solidjs/testing-library'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { type SnackbarApi, SnackbarProvider, useSnackbar } from '../src/ui/Snackbar.tsx'

/**
 * WCAG 2.2.1: the undo snackbar is a time limit, so it must be long enough
 * and must not run out while the user is on it.
 */
function mountSnackbar(): SnackbarApi {
  let api: SnackbarApi | undefined
  function Probe() {
    api = useSnackbar()
    return null
  }
  render(() => (
    <SnackbarProvider>
      <Probe />
    </SnackbarProvider>
  ))
  if (!api) throw new Error('snackbar did not mount')
  return api
}

const visible = () => screen.queryByRole('status') !== null

describe('undo snackbar timing', () => {
  beforeEach(() => vi.useFakeTimers())
  afterEach(() => vi.useRealTimers())

  // @lat: [[tests#Snackbar timing#An undo stays up for twenty seconds]]
  it('stays up for 20 seconds when it carries an action', () => {
    const api = mountSnackbar()
    api.show('Logged $10 on Uber Cash.', { label: 'Undo', onAct: () => undefined })
    vi.advanceTimersByTime(19_000)
    expect(visible()).toBe(true)
    vi.advanceTimersByTime(2_000)
    expect(visible()).toBe(false)
  })

  // @lat: [[tests#Snackbar timing#Focus pauses the timer and leaving restarts it]]
  it('pauses while the button has focus and restarts the full time on leave', () => {
    const api = mountSnackbar()
    api.show('Logged $10 on Uber Cash.', { label: 'Undo', onAct: () => undefined })
    vi.advanceTimersByTime(5_000)
    screen.getByRole('button', { name: /undo/i }).focus()
    vi.advanceTimersByTime(25_000) // t = 30s, well past the plain limit
    expect(visible()).toBe(true)
    screen.getByRole('button', { name: /undo/i }).blur()
    vi.advanceTimersByTime(19_000) // t = 49s
    expect(visible()).toBe(true)
    vi.advanceTimersByTime(2_000) // t = 51s
    expect(visible()).toBe(false)
  })

  // @lat: [[tests#Snackbar timing#The undo button says what it undoes]]
  it('names what the undo undoes', () => {
    const api = mountSnackbar()
    api.show('Logged $10 on Uber Cash.', {
      label: 'Undo',
      ariaLabel: 'Undo logging Uber Cash',
      onAct: () => undefined,
    })
    expect(screen.getByRole('button', { name: 'Undo logging Uber Cash' })).toHaveTextContent('Undo')
  })
})
