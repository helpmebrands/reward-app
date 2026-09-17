import { screen, waitFor } from '@solidjs/testing-library'
import { afterEach, describe, expect, it } from 'vitest'
import { mountRoute } from './mount.tsx'

/**
 * The sheet's presentation follows the breakpoint. jsdom has no layout, so
 * the media query is mocked: matching `(min-width: 600px)` is a tablet.
 */
const realMatchMedia = window.matchMedia

function mockWidth(matches: (query: string) => boolean) {
  window.matchMedia = (query: string): MediaQueryList => ({
    matches: matches(query),
    media: query,
    onchange: null,
    addListener: () => undefined,
    removeListener: () => undefined,
    addEventListener: () => undefined,
    removeEventListener: () => undefined,
    dispatchEvent: () => false,
  })
}

afterEach(() => {
  window.matchMedia = realMatchMedia
})

describe('sheet presentation', () => {
  // @lat: [[tests#Accessibility tests#The sheet is a dialog from 600px]]
  it('is a centred dialog with no grip at a medium width', async () => {
    mockWidth((query) => query.includes('600px'))
    const { ui } = await mountRoute('/')
    ui.openCredit('ben-0003')
    const dialog = await screen.findByRole('dialog')
    expect(dialog.querySelector('.sheet__grip')).toBeNull()
    const panel = dialog.querySelector<HTMLElement>('.sheet__panel')
    expect(panel?.style.transform ?? '').toBe('')
    await waitFor(() => expect(dialog.contains(document.activeElement)).toBe(true))
  })

  // @lat: [[tests#Accessibility tests#The sheet is a dialog from 600px]]
  it('keeps the grip and the drag transform on a phone', async () => {
    const { ui } = await mountRoute('/')
    ui.openCredit('ben-0003')
    const dialog = await screen.findByRole('dialog')
    expect(dialog.querySelector('.sheet__grip')).not.toBeNull()
    const panel = dialog.querySelector<HTMLElement>('.sheet__panel')
    expect(panel?.style.transform).toBe('translateY(0px)')
  })
})
