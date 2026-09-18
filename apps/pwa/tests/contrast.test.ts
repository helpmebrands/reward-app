import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { describe, expect, it } from 'vitest'

/**
 * Token contrast, WCAG 1.4.3 (text, 4.5:1) and 1.4.11 (controls, 3:1).
 *
 * Parses `src/styles/tokens.css` rather than rendering anything, so the
 * ratios are checked before a build exists and independently of what axe
 * can see. Each pair below is a role a component actually uses; the grounds
 * are every surface that role sits on.
 *
 * `--surface-line` dividers and the `--color-neutral-900` hairlines are
 * decorative and are not asserted: a divider that fails 3:1 loses nothing a
 * user needs, which is the exemption 1.4.11 makes.
 */

type Tokens = Record<string, string>

const sheet = readFileSync(join(import.meta.dirname, '..', 'src', 'styles', 'tokens.css'), 'utf8')

function block(selector: string): Tokens {
  const start = sheet.indexOf(`${selector} {`)
  if (start < 0) throw new Error(`no ${selector} block`)
  const body = sheet.slice(start, sheet.indexOf('\n}', start))
  const tokens: Tokens = {}
  for (const [, name, value] of body.matchAll(/(--[\w-]+):\s*([^;]+);/g)) {
    if (name && value) tokens[name] = value.trim()
  }
  return tokens
}

const dark = block(':root')
const light = { ...dark, ...block(':root[data-theme="light"]') }

function resolve(tokens: Tokens, name: string): string {
  const value = tokens[name]
  if (!value) throw new Error(`${name} is not defined`)
  const ref = value.match(/^var\((--[\w-]+)\)$/)
  return ref?.[1] ? resolve(tokens, ref[1]) : value
}

function luminance(hex: string): number {
  if (!/^#[0-9a-f]{6}$/i.test(hex)) throw new Error(`${hex} is not a hex colour`)
  const channel = (i: number) => {
    const c = Number.parseInt(hex.slice(i, i + 2), 16) / 255
    return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4
  }
  return 0.2126 * channel(1) + 0.7152 * channel(3) + 0.0722 * channel(5)
}

function ratio(tokens: Tokens, fg: string, bg: string): number {
  const [hi, lo] = [luminance(resolve(tokens, fg)), luminance(resolve(tokens, bg))].sort(
    (a, b) => b - a,
  )
  return ((hi ?? 0) + 0.05) / ((lo ?? 0) + 0.05)
}

const THEMES = { dark, light } as const
const GROUNDS = ['--color-bg', '--surface-raised', '--surface-sunken', '--surface-quiet']

/** One line per failing pair, so a red run names every offender at once. */
function failures(pairs: ReadonlyArray<[fg: string, bg: string]>, minimum: number): string[] {
  const out: string[] = []
  for (const [theme, tokens] of Object.entries(THEMES)) {
    for (const [fg, bg] of pairs) {
      const r = ratio(tokens, fg, bg)
      if (r < minimum) out.push(`${theme}: ${fg} on ${bg} is ${r.toFixed(2)}:1`)
    }
  }
  return out
}

describe('token contrast', () => {
  // @lat: [[pwa-tests#Token contrast#Secondary text reaches 4.5:1 on every ground]]
  it('secondary text reaches 4.5:1 on every ground it sits on', () => {
    const pairs: [string, string][] = [
      // The alias screen-sub, section-note, .muted and the like resolve to.
      ...GROUNDS.map((g): [string, string] => ['--text-secondary', g]),
      // The bloom's peak, behind the top of every screen: every text colour
      // that can sit there.
      ['--text-secondary', '--color-bloom'],
      ['--color-neutral-500', '--color-bloom'],
      ['--color-neutral-400', '--color-bloom'],
      ['--color-text', '--color-bloom'],
      ['--color-accent', '--color-bloom'], // kickers
      ['--color-accent-300', '--color-bloom'],
      // Field labels, segment text, the missed figure, the "of" line.
      ...GROUNDS.map((g): [string, string] => ['--color-neutral-500', g]),
      // Today's subtitle and the leak titles.
      ...GROUNDS.map((g): [string, string] => ['--color-neutral-400', g]),
      // Captured rows on their own ground.
      ['--tone-captured-fg', '--tone-captured-bg'],
      ['--color-neutral-500', '--surface-sunken'],
    ]
    expect(failures(pairs, 4.5)).toEqual([])
  })

  // @lat: [[pwa-tests#Token contrast#Accent and status text hold in both themes]]
  it('accent and status text hold in both themes', () => {
    const pairs: [string, string][] = [
      ['--color-accent', '--color-bg'], // kickers, countdowns
      ['--color-accent-300', '--color-bg'], // primary buttons, row amounts
      ['--color-accent-300', '--surface-raised'],
      ['--color-accent-200', '--color-accent-900'], // selected segment
      ['--color-accent-200', '--color-accent-800'], // split "available"
      ['--color-accent-100', '--color-accent-800'], // skip link, swipe action
      ['--color-neutral-300', '--color-neutral-800'], // split "captured"
      ['--color-neutral-400', '--color-neutral-900'], // tags
      ['--tone-locked-fg', '--tone-locked-bg'],
      ['--tone-locked-fg', '--surface-raised'],
      ['--tone-missed-fg', '--tone-missed-bg'],
      ['--tone-missed-fg', '--surface-raised'],
      // Inline form errors sit on the page and on sunken inputs' borders.
      ['--tone-missed-fg', '--color-bg'],
      ['--tone-missed-fg', '--surface-sunken'],
      ['--tone-soon-fg', '--tone-soon-bg'],
      // The feature card: an inset section glow over the raised surface, so
      // its text sits on both ends of that fade.
      ...['--color-section', '--surface-raised'].flatMap((g): [string, string][] => [
        ['--color-text', g],
        ['--color-accent-300', g], // kicker, stepped up from the accent
        ['--color-neutral-300', g], // body
        ['--color-accent-300', g], // call to action
      ]),
    ]
    expect(failures(pairs, 4.5)).toEqual([])
  })

  // @lat: [[pwa-tests#Token contrast#Control boundaries reach 3:1]]
  it('control boundaries and the missed bar reach 3:1', () => {
    const pairs: [string, string][] = [
      // Inputs, buttons, segments and the switch track sit on all of these.
      ...GROUNDS.map((g): [string, string] => ['--control-border', g]),
      // The "Missed" bar and its legend swatch, on the page and on a card.
      ['--chart-missed', '--color-bg'],
      ['--chart-missed', '--surface-raised'],
      // The accent outline, focus ring and bar fill.
      ['--color-accent', '--color-bg'],
      ['--color-accent', '--surface-raised'],
      // The switch knob at rest on its track.
      ['--color-neutral-600', '--surface-sunken'],
    ]
    expect(failures(pairs, 3)).toEqual([])
  })
})
