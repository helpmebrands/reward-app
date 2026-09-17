import { expect, test } from './fixtures.ts'

/**
 * A phone on its side: 667×375, the compact layout at its shortest.
 *
 * WCAG 1.3.4 says the app must not lock orientation, which means landscape
 * has to actually work: the first thing on every screen is visible without
 * scrolling, nothing scrolls sideways, and the credit sheet still opens,
 * scrolls and closes with a 58px tab bar and safe areas eating the height.
 * Runs only on the landscape project in playwright.config.ts.
 */

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

for (const [name, path] of ROUTES) {
  // @lat: [[tests#Accessibility tests#Landscape keeps the first row on screen]]
  test(`${name} fits a landscape phone`, async ({ page }) => {
    await page.goto(path)
    await expect(page.locator('#main').getByText('Loading your cards')).toBeHidden()

    const layout = await page.evaluate(() => {
      const main = document.querySelector('#main')
      if (!main) throw new Error('no main')
      const first = main.querySelector('.row-card') ?? main.querySelector('h1, p')
      if (!first) throw new Error('no first row or heading')
      const m = main.getBoundingClientRect()
      const f = first.getBoundingClientRect()
      return {
        pageScrollsSideways:
          document.documentElement.scrollWidth > document.documentElement.clientWidth,
        mainScrollsSideways: main.scrollWidth > main.clientWidth,
        firstRow: { top: f.top, bottom: f.bottom, text: first.textContent?.trim().slice(0, 40) },
        main: { top: m.top, bottom: m.bottom },
      }
    })

    expect(layout.pageScrollsSideways, 'page scrolls horizontally').toBe(false)
    expect(layout.mainScrollsSideways, 'main scrolls horizontally').toBe(false)
    expect(
      layout.firstRow.top,
      `first row "${layout.firstRow.text}" clipped at top`,
    ).toBeGreaterThanOrEqual(layout.main.top)
    expect(
      layout.firstRow.bottom,
      `first row "${layout.firstRow.text}" clipped at bottom`,
    ).toBeLessThanOrEqual(layout.main.bottom)
  })
}

// @lat: [[tests#Accessibility tests#The credit sheet works in landscape]]
test('the credit sheet opens, scrolls and closes', async ({ page, viewport }) => {
  await page.goto('/')
  await expect(page.locator('#main').getByText('Loading your cards')).toBeHidden()

  await page.locator('.row-card__main').first().click()
  const dialog = page.getByRole('dialog')
  await expect(dialog).toBeVisible()

  const panel = await dialog.locator('.sheet__panel').boundingBox()
  if (!panel || !viewport) throw new Error('no panel or viewport')
  expect(panel.height, 'sheet leaves the screen behind visible').toBeLessThanOrEqual(
    viewport.height * 0.85 + 1,
  )
  expect(panel.y + panel.height, 'sheet bottom is on screen').toBeLessThanOrEqual(
    viewport.height + 1,
  )

  const body = dialog.locator('.sheet__body')
  const scrolled = await body.evaluate((el) => {
    const canScroll = el.scrollHeight > el.clientHeight
    el.scrollTop = 200
    return { canScroll, scrollTop: el.scrollTop }
  })
  expect(scrolled.canScroll, 'sheet body scrolls inside the panel').toBe(true)
  expect(scrolled.scrollTop).toBeGreaterThan(0)

  await page.keyboard.press('Escape')
  await expect(dialog).toBeHidden()
})

// @lat: [[tests#PWA manifest#Built manifest has no orientation key]]
test('the built manifest does not lock orientation', async ({ page }) => {
  const response = await page.request.get('/manifest.webmanifest')
  expect(response.ok()).toBe(true)
  const manifest = (await response.json()) as Record<string, unknown>
  expect(manifest).not.toHaveProperty('orientation')
})
