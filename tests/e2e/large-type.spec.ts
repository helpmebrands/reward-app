import { expect, test } from './fixtures.ts'

/**
 * WCAG 1.4.4: a user's browser font-size preference must reach the app.
 * Chromium has no switch for the preference itself, so the root font size
 * is set to 24px after load, which is exactly what the preference changes;
 * a rem scale follows it and a px scale ignores it. Runs on the large-type
 * project in playwright.config.ts.
 */

const ROOT_24PX = 'html { font-size: 24px !important; }'

/** Bounding boxes of the visible controls in main, top-level only. */
function controlBoxes() {
  const controls = [
    ...document.querySelectorAll<HTMLElement>('#main :is(button, a, input, select, textarea)'),
  ].filter(
    (el) =>
      !el.closest('.visually-hidden') &&
      el.getClientRects().length > 0 &&
      getComputedStyle(el).visibility !== 'hidden',
  )
  return controls
    .filter((el) => !controls.some((other) => other !== el && other.contains(el)))
    .map((el) => {
      const r = el.getBoundingClientRect()
      return {
        name: `${el.tagName.toLowerCase()}#${el.id || el.className.toString().split(' ')[0]}`,
        x: r.left,
        y: r.top,
        w: r.width,
        h: r.height,
      }
    })
    .filter((b) => b.w > 0 && b.h > 0)
}

function overlaps(boxes: ReturnType<typeof controlBoxes>) {
  const out: string[] = []
  for (let i = 0; i < boxes.length; i += 1) {
    for (let j = i + 1; j < boxes.length; j += 1) {
      const a = boxes[i]
      const b = boxes[j]
      if (!a || !b) continue
      const x = Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x)
      const y = Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y)
      if (x > 1 && y > 1) out.push(`${a.name} overlaps ${b.name}`)
    }
  }
  return out
}

// @lat: [[tests#Accessibility tests#Body text follows the browser font size]]
test('body text follows a 24px browser font size', async ({ page }) => {
  await page.goto('/')
  await expect(page.locator('#main').getByText('Loading your cards')).toBeHidden()
  await page.addStyleTag({ content: ROOT_24PX })
  const size = await page.evaluate(() => getComputedStyle(document.body).fontSize)
  expect(size).toBe('22.5px')
})

for (const [name, path] of [
  ['Today', '/'],
  ['Benefit editor', '/benefit/ben-0003'],
] as const) {
  // @lat: [[tests#Accessibility tests#Controls keep clear of each other at 24px]]
  test(`${name} controls keep clear of each other at 24px`, async ({ page }) => {
    await page.goto(path)
    await expect(page.locator('#main').getByText('Loading your cards')).toBeHidden()
    await page.addStyleTag({ content: ROOT_24PX })
    const boxes = await page.evaluate(controlBoxes)
    expect(boxes.length).toBeGreaterThan(3)
    expect(overlaps(boxes)).toEqual([])
    const sideways = await page.evaluate(
      () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
    )
    expect(sideways).toBe(0)
  })
}
