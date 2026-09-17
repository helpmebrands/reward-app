import axe from 'axe-core'
import { COMPONENT_ALLOWLIST } from './allowlist.ts'

/**
 * The WCAG 2.1 AA rule set, plus axe's best practices so a missing `<h1>` or
 * content outside a landmark is caught too. The same tags drive the
 * Playwright suite.
 */
export const AXE_TAGS = ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'best-practice']

/**
 * Runs axe over the whole document (portalled sheets included) and returns
 * one readable line per violation, so a failing test names the rule and the
 * offending node rather than dumping an object.
 */
export async function axeViolations(): Promise<string[]> {
  const results = await axe.run(document, {
    runOnly: { type: 'tag', values: AXE_TAGS },
    rules: Object.fromEntries(COMPONENT_ALLOWLIST.map((id) => [id, { enabled: false }])),
  })
  return results.violations.map(
    (v) =>
      `${v.id} (${v.impact}): ${v.help} — ${v.nodes.map((n) => n.target.join(' ')).join(', ')}`,
  )
}
