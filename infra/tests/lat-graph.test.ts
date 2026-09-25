import { existsSync, readdirSync, readFileSync } from 'node:fs'
import { join } from 'node:path'
import { describe, expect, it } from 'vitest'

// Guards the shape of the lat.md graph: one root, split by area, with the
// product spec free of anything the Dart port and the Flutter app must not
// inherit from the retired PWA.

const root = join(import.meta.dirname, '..', '..')
const graph = join(root, 'lat.md')
const AREAS = ['product', 'mobile', 'api', 'infra'] as const

const markdownUnder = (dir: string) =>
  readdirSync(dir, { withFileTypes: true })
    .filter((entry) => entry.isFile() && entry.name.endsWith('.md'))
    .map((entry) => entry.name)

describe('lat.md graph layout', () => {
  // @lat: [[infra-tests#Infrastructure config#The graph is split by area]]
  it('keeps every section under product, mobile, api or infra', () => {
    for (const area of AREAS) {
      expect(existsSync(join(graph, area)), area).toBe(true)
      expect(markdownUnder(join(graph, area)).length, area).toBeGreaterThan(0)
    }
    expect(markdownUnder(graph)).toEqual(['lat.md'])
    expect(existsSync(join(graph, 'pwa'))).toBe(false)
  })

  // @lat: [[infra-tests#Infrastructure config#The index names the four areas]]
  it('indexes the four areas from lat.md/lat.md', () => {
    const index = readFileSync(join(graph, 'lat.md'), 'utf8')
    for (const area of AREAS) {
      expect(index, area).toContain(`${area}/`)
    }
  })

  // @lat: [[infra-tests#Infrastructure config#The product spec names no PWA technology]]
  it('keeps Solid, IndexedDB, Vite, the service worker and Web Push out of product', () => {
    const banned = /\bsolid\b|indexeddb|\bvite\b|service.worker|web push/i
    const dir = join(graph, 'product')
    const offenders = existsSync(dir)
      ? markdownUnder(dir).filter((name) => banned.test(readFileSync(join(dir, name), 'utf8')))
      : ['(no product directory)']
    expect(offenders).toEqual([])
  })
})
