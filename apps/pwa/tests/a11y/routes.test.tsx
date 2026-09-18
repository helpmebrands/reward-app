import { screen } from '@solidjs/testing-library'
import { describe, expect, it } from 'vitest'
import { axeViolations } from './axe.ts'
import { mountRoute } from './mount.tsx'

/**
 * Component-level accessibility gate.
 *
 * Every route is rendered with the sample household and handed to axe. jsdom
 * has no layout engine, so colour contrast is not judged here; the Playwright
 * suite covers that against the built app. Anything axe can see in the DOM —
 * names, roles, labels, landmarks, headings, ARIA validity — is judged here,
 * which is where a regression in a component is cheapest to catch.
 */

// Ids come from samples/sample-household.json.
const ROUTES: ReadonlyArray<[name: string, path: string]> = [
  ['Today', '/'],
  ['Credits', '/credits'],
  ['Cards', '/cards'],
  ['Add a card', '/cards/new'],
  ['Card editor', '/cards/card-0001'],
  ['Benefit editor', '/benefit/ben-0003'],
  ['Value', '/value'],
  ['Settings', '/settings'],
  ['Not found', '/nowhere'],
]

// axe over a full screen in jsdom takes a few seconds.
const TIMEOUT = 30_000

describe('axe on every route', () => {
  for (const [name, path] of ROUTES) {
    // @lat: [[pwa-tests#Accessibility tests#Every route passes axe in jsdom]]
    it(
      `${name} has no violations`,
      async () => {
        await mountRoute(path)
        expect(await axeViolations()).toEqual([])
      },
      TIMEOUT,
    )
  }

  // @lat: [[pwa-tests#Accessibility tests#The credit sheet passes axe]]
  it(
    'the credit sheet has no violations',
    async () => {
      const { ui } = await mountRoute('/')
      ui.openCredit('ben-0003')
      await screen.findByRole('dialog')
      expect(await axeViolations()).toEqual([])
    },
    TIMEOUT,
  )
})
