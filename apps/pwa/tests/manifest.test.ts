import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { describe, expect, it } from 'vitest'

// Guards the PWA manifest options in vite.config.ts. The built manifest is
// checked by the Playwright suite; this runs before a build exists.

const config = readFileSync(join(import.meta.dirname, '..', 'vite.config.ts'), 'utf8')

describe('PWA manifest', () => {
  // @lat: [[tests#PWA manifest#Manifest sets no orientation]]
  it('sets no orientation, so the OS decides', () => {
    expect(config).not.toMatch(/^\s*orientation:/m)
  })
})
