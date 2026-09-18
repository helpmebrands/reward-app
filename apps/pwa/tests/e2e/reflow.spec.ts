import { expect, test } from './fixtures.ts'

/**
 * WCAG 1.4.10 (reflow) and 1.4.12 (text spacing), at 320px: the narrowest
 * width the guideline names, which is also a desktop window at 400% zoom.
 * Runs only on the reflow project in playwright.config.ts.
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

/** The text-spacing overrides WCAG 1.4.12 says a page must survive. */
const TEXT_SPACING_CSS = `
  * { line-height: 1.5 !important; letter-spacing: 0.12em !important; word-spacing: 0.16em !important; }
  p { margin-bottom: 2em !important; }
`

function sidewaysScroll() {
  const root = document.documentElement
  const main = document.querySelector('#main')
  return {
    page: root.scrollWidth - root.clientWidth,
    main: main ? main.scrollWidth - main.clientWidth : 0,
  }
}

/**
 * Elements that hide their overflow and would clip text: any whose content
 * is taller than the box. `.truncate` is the audited allowlist (the full
 * text is one tap away), `.visually-hidden` is off-screen by design, and
 * one-pixel boxes are the icon-only tab labels.
 */
function clippedElements() {
  const clipped: string[] = []
  for (const el of document.querySelectorAll<HTMLElement>('body *')) {
    const style = getComputedStyle(el)
    if (style.overflowY !== 'hidden' && style.overflow !== 'hidden') continue
    if (el.matches('.truncate, .visually-hidden') || el.clientHeight <= 1) continue
    if (el.scrollHeight > el.clientHeight + 1) {
      clipped.push(`${el.tagName.toLowerCase()}.${el.className.toString().split(' ')[0]}`)
    }
  }
  return clipped
}

for (const [name, path] of ROUTES) {
  // @lat: [[pwa-tests#Accessibility tests#Nothing scrolls sideways at 320px]]
  test(`${name} does not scroll sideways at 320px`, async ({ page }) => {
    await page.goto(path)
    await expect(page.locator('#main').getByText('Loading your cards')).toBeHidden()
    expect(await page.evaluate(sidewaysScroll)).toEqual({ page: 0, main: 0 })
  })

  // @lat: [[pwa-tests#Accessibility tests#Text spacing overrides clip nothing]]
  test(`${name} survives the text-spacing overrides`, async ({ page }, testInfo) => {
    await page.goto(path)
    await expect(page.locator('#main').getByText('Loading your cards')).toBeHidden()
    await page.addStyleTag({ content: TEXT_SPACING_CSS })
    await testInfo.attach(`${name} with text spacing`, {
      body: await page.screenshot({ fullPage: false }),
      contentType: 'image/png',
    })
    expect(await page.evaluate(clippedElements)).toEqual([])
    expect(await page.evaluate(sidewaysScroll)).toEqual({ page: 0, main: 0 })
  })
}

// @lat: [[pwa-tests#Accessibility tests#Nothing scrolls sideways at 320px]]
test('the credit and compare sheets fit 320px', async ({ page }) => {
  await page.goto('/')
  await expect(page.locator('#main').getByText('Loading your cards')).toBeHidden()

  await page.locator('.row-card__main').first().click()
  await expect(page.getByRole('dialog')).toBeVisible()
  expect(await page.evaluate(sidewaysScroll)).toEqual({ page: 0, main: 0 })
  await page.keyboard.press('Escape')
  await expect(page.getByRole('dialog')).toBeHidden()

  await page.locator('.today__overlap').first().click()
  await expect(page.getByRole('dialog')).toBeVisible()
  expect(await page.evaluate(sidewaysScroll)).toEqual({ page: 0, main: 0 })
})
