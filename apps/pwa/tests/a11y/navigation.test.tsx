import { screen, waitFor } from '@solidjs/testing-library'
import { describe, expect, it } from 'vitest'
import { mountRoute } from './mount.tsx'

/**
 * WCAG 2.4.2 (page titled), 2.4.3 (focus order) and 2.4.6 (headings).
 *
 * A single-page app has one document, so titles and focus are the app's job:
 * without them a screen reader user hears "HelpMe Reward" on every screen and
 * lands on <body> after every navigation.
 */

// Ids come from samples/sample-household.json.
const TITLES: ReadonlyArray<[path: string, title: string]> = [
  ['/', 'Today · HelpMe Reward'],
  ['/credits', 'Credits · HelpMe Reward'],
  ['/cards', 'Cards · HelpMe Reward'],
  ['/cards/new', 'Add a card · HelpMe Reward'],
  ['/cards/card-0001', 'American Express Platinum — Jim · HelpMe Reward'],
  ['/benefit/ben-0003', 'Uber Cash · HelpMe Reward'],
  ['/value', 'Value · HelpMe Reward'],
  ['/settings', 'Settings · HelpMe Reward'],
  ['/nowhere', 'Not found · HelpMe Reward'],
]

describe('document titles', () => {
  for (const [path, title] of TITLES) {
    // @lat: [[pwa-tests#Accessibility tests#Every route sets a document title]]
    it(`${path} is titled "${title}"`, async () => {
      document.title = ''
      await mountRoute(path)
      await waitFor(() => expect(document.title).toBe(title))
    })
  }
})

describe('focus on navigation', () => {
  // @lat: [[pwa-tests#Accessibility tests#Navigation moves focus to the new heading]]
  it('lands on the new screen heading, and on the old one going back', async () => {
    const { history } = await mountRoute('/cards')
    await screen.findByRole('heading', { level: 1, name: 'Cards' })

    history.set({ value: '/cards/new' })
    const added = await screen.findByRole('heading', { level: 1, name: 'Add a card' })
    await waitFor(() => expect(document.activeElement).toBe(added))

    history.back()
    const cards = await screen.findByRole('heading', { level: 1, name: 'Cards' })
    await waitFor(() => expect(document.activeElement).toBe(cards))
  })

  // @lat: [[pwa-tests#Accessibility tests#A tab press keeps focus on the tab]]
  it('leaves focus on a tab the user pressed', async () => {
    await mountRoute('/')
    const tab = await screen.findByRole('button', { name: 'Credits' })
    tab.focus()
    tab.click()
    await screen.findByRole('heading', { level: 1, name: 'All credits' })
    // Give any focus move a chance to happen, then assert it did not.
    await new Promise((resolve) => setTimeout(resolve, 20))
    expect(document.activeElement).toBe(tab)
  })
})
