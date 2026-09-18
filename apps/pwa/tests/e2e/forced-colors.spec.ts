import { expect, test } from './fixtures.ts'

/**
 * Windows High Contrast, emulated with Chromium's forced-colors mode. Every
 * background is replaced by the system Canvas colour, so a control that
 * relied on a fill or a tonal difference disappears unless it has a border.
 * Runs on the forced-colours project in playwright.config.ts.
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
]

/**
 * Interactive controls with no visible boundary: no border on any side.
 * Three are left out on purpose: the off-screen file input behind "Import a
 * backup", the sheet's scrim (a backdrop, not a control to find), and a
 * row's main button, which fills its bordered card.
 */
function borderless() {
  const controls = document.querySelectorAll<HTMLElement>(
    'button, input, select, textarea, a.btn, [role="switch"], .switch__knob',
  )
  const out: string[] = []
  for (const el of controls) {
    if (el.getClientRects().length === 0) continue
    if (el.matches('.visually-hidden, .sheet__scrim, .row-card__main')) continue
    const style = getComputedStyle(el)
    if (style.visibility === 'hidden') continue
    const widths = [
      style.borderTopWidth,
      style.borderRightWidth,
      style.borderBottomWidth,
      style.borderLeftWidth,
    ].map((w) => Number.parseFloat(w))
    if (widths.every((w) => w === 0)) {
      out.push(
        `${el.tagName.toLowerCase()}.${el.className.toString().split(' ')[0]}${el.id ? `#${el.id}` : ''}`,
      )
    }
  }
  return [...new Set(out)]
}

for (const [name, path] of ROUTES) {
  // @lat: [[pwa-tests#Accessibility tests#Every control keeps a boundary in forced colours]]
  test(`${name} keeps a boundary on every control in forced colours`, async ({
    page,
  }, testInfo) => {
    await page.goto(path)
    await expect(page.locator('#main').getByText('Loading your cards')).toBeHidden()
    await testInfo.attach(`${name} in forced colours`, {
      body: await page.screenshot(),
      contentType: 'image/png',
    })
    expect(await page.evaluate(borderless)).toEqual([])
  })
}

// @lat: [[pwa-tests#Accessibility tests#Every control keeps a boundary in forced colours]]
test('the credit sheet keeps its boundaries in forced colours', async ({ page }) => {
  await page.goto('/')
  await expect(page.locator('#main').getByText('Loading your cards')).toBeHidden()
  await page.locator('.row-card__main').first().click()
  await expect(page.getByRole('dialog')).toBeVisible()
  expect(await page.evaluate(borderless)).toEqual([])
})
