import AxeBuilder from '@axe-core/playwright'
import { E2E_ALLOWLIST } from '../a11y/allowlist.ts'
import { AXE_TAGS } from '../a11y/axe.ts'
import { expect, test } from './fixtures.ts'

/**
 * The accessibility gate against the built app.
 *
 * Each project in playwright.config.ts is one viewport width and one theme,
 * so every route below is judged eight times: 320, 402, 768 and 1280px wide
 * in light and in dark. This is the suite that sees real layout and colour,
 * which the jsdom suite cannot.
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

for (const [name, path] of ROUTES) {
  // @lat: [[tests#Accessibility tests#Every route passes axe in a real browser]]
  test(`${name} has no axe violations`, async ({ page, theme }) => {
    await page.goto(path)
    await expect(page.locator('#main').getByText('Loading your cards')).toBeHidden()
    // Proves the seed took: the shell only stamps a non-system theme.
    await expect(page.locator('html')).toHaveAttribute('data-theme', theme)

    const results = await new AxeBuilder({ page })
      .withTags(AXE_TAGS)
      .disableRules([...E2E_ALLOWLIST])
      .analyze()

    const violations = results.violations.map(
      (v) =>
        `${v.id} (${v.impact}): ${v.help} — ${v.nodes.map((n) => n.target.join(' ')).join(', ')}`,
    )
    expect(violations).toEqual([])
  })
}
