import type { Page } from '@playwright/test'
import { expect, test } from './fixtures.ts'

/**
 * The keyboard-only sweep: from the skip link, Tab and Enter alone complete
 * the app's main actions. The swipe gestures and the sheet's drag handle are
 * accelerators with keyboard routes; this proves the routes. Runs on the
 * 402px shell project in playwright.config.ts.
 */

/** Presses Tab until the focused element matches, or gives up. */
async function tabTo(page: Page, matches: (el: Element) => boolean, limit = 80) {
  for (let i = 0; i < limit; i += 1) {
    await page.keyboard.press('Tab')
    const hit = await page.evaluate((fn) => {
      const el = document.activeElement
      // biome-ignore lint/security/noGlobalEval: the predicate is test code, serialised to run in the page.
      return el ? (eval(fn) as (e: Element) => boolean)(el) : false
    }, matches.toString())
    if (hit) return
  }
  throw new Error(`nothing matching ${matches} reached in ${limit} tabs`)
}

const focusedText = (page: Page) =>
  page.evaluate(() => {
    const el = document.activeElement as HTMLElement | null
    return `${el?.getAttribute('aria-label') ?? ''} ${el?.textContent?.trim() ?? ''}`.trim()
  })

async function start(page: Page, path: string) {
  await page.goto(path)
  await expect(page.locator('#main').getByText('Loading your cards')).toBeHidden()
  // The skip link comes first, and Enter on it puts the next Tab into main.
  await page.keyboard.press('Tab')
  await expect(page.locator('.skip-link')).toBeFocused()
  await page.keyboard.press('Enter')
}

test.beforeEach(async ({ viewport }) => {
  test.skip(viewport?.width !== 402, 'one width is enough for a keyboard sweep')
})

// @lat: [[pwa-tests#Accessibility tests#Tab and Enter alone complete the five actions]]
test('logs a claim from a row through the sheet', async ({ page }) => {
  await start(page, '/')
  await tabTo(page, (el) => el.classList.contains('row-card__main'))
  await page.keyboard.press('Enter')
  await expect(page.getByRole('dialog')).toBeVisible()
  await tabTo(page, (el) => /mark the full/i.test(el.textContent ?? ''))
  await page.keyboard.press('Enter')
  await expect(page.getByRole('dialog')).toBeHidden()
  await expect(page.getByRole('status')).toContainText(/logged/i)
  // Focus comes back to a row, not to the body, even though the list changed.
  expect(await page.evaluate(() => document.activeElement?.className ?? '')).toContain('row-card')
})

// @lat: [[pwa-tests#Accessibility tests#Tab and Enter alone complete the five actions]]
test('silences a credit from its row', async ({ page }) => {
  await start(page, '/')
  await tabTo(page, (el) => /^silence reminders/i.test(el.getAttribute('aria-label') ?? ''))
  await page.keyboard.press('Enter')
  await expect(page.getByRole('status')).toContainText(/silenced/i)
  expect(await focusedText(page)).toMatch(/^unsilence/i)
})

// @lat: [[pwa-tests#Accessibility tests#Tab and Enter alone complete the five actions]]
test('adds a card from the catalogue', async ({ page }) => {
  await start(page, '/cards')
  await tabTo(page, (el) => /add a card from the catalogue/i.test(el.textContent ?? ''))
  await page.keyboard.press('Enter')
  await expect(page).toHaveURL(/\/cards\/new$/)
  await tabTo(page, (el) => el.classList.contains('catalog'))
  await page.keyboard.press('Enter')
  // The holder defaults to the household's first name, so nothing to type.
  await tabTo(page, (el) => /add this card/i.test(el.textContent ?? ''))
  await page.keyboard.press('Enter')
  await expect(page).toHaveURL(/\/cards\/[^/]+$/)
  await expect(page.getByRole('status')).toContainText(/added/i)
})

// @lat: [[pwa-tests#Accessibility tests#Tab and Enter alone complete the five actions]]
test('edits a benefit from the card editor', async ({ page }) => {
  await start(page, '/cards/card-0001')
  await tabTo(page, (el) => el.classList.contains('benefit-link'))
  await page.keyboard.press('Enter')
  await expect(page).toHaveURL(/\/benefit\//)
  const toggle = page.getByRole('switch', { name: 'Track this credit' })
  const before = await toggle.getAttribute('aria-checked')
  await tabTo(page, (el) => el.getAttribute('aria-label') === 'Track this credit')
  await page.keyboard.press('Enter')
  await expect(toggle).toHaveAttribute('aria-checked', before === 'true' ? 'false' : 'true')
})

// @lat: [[pwa-tests#Accessibility tests#Tab and Enter alone complete the five actions]]
test('changes the theme in Settings', async ({ page }) => {
  await start(page, '/settings')
  await tabTo(page, (el) => el.classList.contains('seg__opt') && el.textContent?.trim() === 'Light')
  await page.keyboard.press('Enter')
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'light')
})
