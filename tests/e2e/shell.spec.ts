import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { expect, test } from './fixtures.ts'

/**
 * The responsive shell. Under 600px the phone layout is the design as drawn
 * and must not move by a pixel; from 600px the tab bar is a navigation rail
 * on the leading edge and the content column is centred at its cap. Runs on
 * the shell projects in playwright.config.ts, one per width.
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

/** What each width owes: the rail's width and the content column's cap. */
const LAYOUT: Record<number, { rail: number; content: number }> = {
  768: { rail: 80, content: 560 },
  1280: { rail: 200, content: 720 },
}

/** Elements whose boxes pin the phone layout. Missing ones are recorded as null. */
const LANDMARKS = [
  '#main',
  '.tabbar',
  '.tabbar__tab:nth-child(1)',
  '.tabbar__tab:nth-child(4)',
  '#main h1',
  '.today__amount',
  '.row-card',
  '.topbar',
  '.field',
  '#main .btn',
  '.value__totals',
]

type Box = [x: number, y: number, w: number, h: number] | null
type Baseline = Record<string, Box[]>

const BASELINE_PATH = resolve(process.cwd(), 'tests', 'e2e', 'layout-baseline.json')

function boxes(selectors: string[]): Box[] {
  return selectors.map((selector) => {
    const el = document.querySelector(selector)
    if (!el) return null
    const r = el.getBoundingClientRect()
    return [Math.round(r.x), Math.round(r.y), Math.round(r.width), Math.round(r.height)]
  })
}

function loadBaseline(): Baseline {
  return existsSync(BASELINE_PATH)
    ? (JSON.parse(readFileSync(BASELINE_PATH, 'utf8')) as Baseline)
    : {}
}

for (const [name, path] of ROUTES) {
  test(`${name} shell layout`, async ({ page, viewport }) => {
    if (!viewport) throw new Error('no viewport')
    await page.goto(path)
    await expect(page.locator('#main').getByText('Loading your cards')).toBeHidden()
    const expected = LAYOUT[viewport.width]

    if (!expected) {
      // @lat: [[tests#Accessibility tests#The phone layout does not move]]
      // Compact: the phone design as drawn. Compared against a baseline taken
      // from develop before the responsive work; UPDATE_LAYOUT_BASELINE=1
      // rewrites it once a change to the phone layout is intended.
      const key = `${viewport.width}:${path}`
      const actual = await page.evaluate(boxes, LANDMARKS)
      const baseline = loadBaseline()
      if (process.env.UPDATE_LAYOUT_BASELINE) {
        baseline[key] = actual
        mkdirSync(dirname(BASELINE_PATH), { recursive: true })
        writeFileSync(BASELINE_PATH, `${JSON.stringify(baseline, null, 1)}\n`)
        return
      }
      const drift = LANDMARKS.flatMap((selector, i) => {
        const was = baseline[key]?.[i]
        const now = actual[i] ?? null
        if (was === undefined) return [`${selector}: no baseline`]
        if (was === null || now === null) return was === now ? [] : [`${selector}: ${was} → ${now}`]
        return was.some((v, j) => Math.abs(v - (now[j] ?? 0)) > 1)
          ? [`${selector}: ${was.join(',')} → ${now.join(',')}`]
          : []
      })
      expect(drift).toEqual([])
      return
    }

    // @lat: [[tests#Accessibility tests#The rail and the centred column at wider widths]]
    const nav = page.getByRole('navigation', { name: 'Main' })
    const navBox = await nav.boundingBox()
    const mainBox = await page.locator('#main').boundingBox()
    if (!navBox || !mainBox) throw new Error('no nav or main')
    expect(navBox.x, 'rail on the leading edge').toBe(0)
    expect(Math.round(navBox.width), 'rail width').toBe(expected.rail)
    expect(Math.round(navBox.height), 'rail is full height').toBe(viewport.height)
    expect(Math.round(mainBox.width), 'content column at its cap').toBe(expected.content)
    const leftGap = mainBox.x - expected.rail
    const rightGap = viewport.width - (mainBox.x + mainBox.width)
    expect(
      Math.abs(leftGap - rightGap),
      'content column centred beside the rail',
    ).toBeLessThanOrEqual(1)
  })
}

// @lat: [[tests#Accessibility tests#The rail and the centred column at wider widths]]
test('the four tabs are reachable by keyboard in order', async ({ page, viewport }) => {
  if (!viewport || !LAYOUT[viewport.width]) test.skip()
  await page.goto('/')
  await expect(page.locator('#main').getByText('Loading your cards')).toBeHidden()
  await page.getByRole('button', { name: 'Today' }).focus()
  const names: string[] = []
  for (let i = 0; i < 4; i += 1) {
    names.push(await page.evaluate(() => document.activeElement?.textContent?.trim() ?? ''))
    await page.keyboard.press('Tab')
  }
  expect(names).toEqual(['Today', 'Credits', 'Cards', 'Value'])
})
