import { writeFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { expect, test } from './fixtures.ts'

/**
 * The screens at medium and expanded widths: the same markup laid out on
 * the wider column with CSS grid, so the reading order never changes. Runs
 * on the shell projects in playwright.config.ts; skipped on phone widths.
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

/** Top edges of two elements, to say whether they sit on one row. */
function tops([a, b]: readonly [string, string]) {
  const box = (selector: string) => document.querySelector(selector)?.getBoundingClientRect()
  const ra = box(a)
  const rb = box(b)
  if (!ra || !rb) throw new Error(`missing ${!ra ? a : b}`)
  return { a: { x: ra.x, y: ra.y }, b: { x: rb.x, y: rb.y } }
}

async function load(page: import('@playwright/test').Page, path: string) {
  await page.goto(path)
  await expect(page.locator('#main').getByText('Loading your cards')).toBeHidden()
}

// @lat: [[tests#Accessibility tests#Wider screens use the column]]
test('Today puts overlap cards side by side from 600px', async ({ page, viewport }) => {
  if (!viewport) throw new Error('no viewport')
  test.skip(viewport.width < 600, 'wider widths only')
  await load(page, '/')
  const t = await page.evaluate(tops, [
    '.today__overlap:nth-child(1)',
    '.today__overlap:nth-child(2)',
  ] as const)
  expect(Math.abs(t.a.y - t.b.y)).toBeLessThanOrEqual(1)
  expect(t.b.x).toBeGreaterThan(t.a.x)
})

// @lat: [[tests#Accessibility tests#Wider screens use the column]]
test('Cards is a two-column grid at a medium width', async ({ page, viewport }) => {
  if (!viewport) throw new Error('no viewport')
  test.skip(viewport.width < 600 || viewport.width >= 1024, 'medium width only')
  await load(page, '/cards')
  const t = await page.evaluate(tops, ['.cardstat:nth-child(1)', '.cardstat:nth-child(2)'] as const)
  expect(Math.abs(t.a.y - t.b.y)).toBeLessThanOrEqual(1)
  expect(t.b.x).toBeGreaterThan(t.a.x)
})

// @lat: [[tests#Accessibility tests#Wider screens use the column]]
test('the expanded width sets sections and fields side by side', async ({ page, viewport }) => {
  if (!viewport) throw new Error('no viewport')
  test.skip(viewport.width < 1024, 'expanded width only')

  await load(page, '/')
  const today = await page.evaluate(tops, ['.today__soon', '.today__locked'] as const)
  expect(today.b.x, 'locked section beside the rows').toBeGreaterThan(today.a.x)
  expect(Math.abs(today.a.y - today.b.y)).toBeLessThanOrEqual(1)

  await load(page, '/cards')
  const card = await page.evaluate(tops, ['.cardstat__head', '.cardstat__verdict'] as const)
  expect(card.b.x, 'verdict beside the card').toBeGreaterThan(card.a.x)
  expect(Math.abs(card.a.y - card.b.y)).toBeLessThanOrEqual(1)

  await load(page, '/cards/card-0001')
  const editor = await page.evaluate(tops, ['#card-holder', '#card-nickname'] as const)
  expect(Math.abs(editor.a.y - editor.b.y), 'holder and nickname on one row').toBeLessThanOrEqual(1)

  await load(page, '/benefit/ben-0003')
  const benefit = await page.evaluate(tops, ['#benefit-name', '#benefit-value'] as const)
  expect(Math.abs(benefit.a.y - benefit.b.y), 'name and value on one row').toBeLessThanOrEqual(1)
  const steps = await page.evaluate(() => {
    const area = document.querySelector('#benefit-steps')?.getBoundingClientRect()
    const name = document.querySelector('#benefit-name')?.getBoundingClientRect()
    if (!area || !name) throw new Error('missing fields')
    return { areaWidth: area.width, nameWidth: name.width }
  })
  expect(steps.areaWidth, 'the text area spans the column').toBeGreaterThan(steps.nameWidth * 1.8)
})

// @lat: [[tests#Accessibility tests#Reading order is the same at every width]]
test('Today reads in the same order at 1280 and 402px', async ({ page, viewport }) => {
  if (!viewport) throw new Error('no viewport')
  test.skip(viewport.width < 1024, 'expanded project only')
  await load(page, '/')
  const order = () =>
    page.evaluate(() =>
      [...document.querySelectorAll('#main h1, #main h2, #main .row-card__title')].map((el) =>
        el.textContent?.trim(),
      ),
    )
  const wide = await order()
  await page.setViewportSize({ width: 402, height: 874 })
  const phone = await order()
  expect(wide.length).toBeGreaterThan(5)
  expect(phone).toEqual(wide)
})

for (const [name, path] of ROUTES) {
  // @lat: [[tests#Accessibility tests#Wider screens use the column]]
  test(`${name} screenshot for review`, async ({ page, viewport }, testInfo) => {
    if (!viewport) throw new Error('no viewport')
    test.skip(viewport.width < 600, 'wider widths only')
    await load(page, path)
    const png = await page.screenshot({ fullPage: false })
    await testInfo.attach(`${name} at ${viewport.width}px`, { body: png, contentType: 'image/png' })
    if (process.env.UPDATE_SCREENSHOTS) {
      const file = `${name.toLowerCase().replace(/\s+/g, '-')}-${viewport.width}.png`
      writeFileSync(resolve(process.cwd(), 'tests', 'e2e', 'screenshots', file), png)
    }
  })
}
