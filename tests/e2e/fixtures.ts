import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { test as base, expect } from '@playwright/test'

export type Theme = 'light' | 'dark'

const sample = JSON.parse(
  readFileSync(
    fileURLToPath(new URL('../../samples/sample-household.json', import.meta.url)),
    'utf8',
  ),
) as { settings: Record<string, unknown> }

/**
 * Writes the sample household straight into the app's IndexedDB record.
 * Runs in the browser. The names mirror `src/services/db.ts`, which cannot be
 * imported here because idb-keyval opens the database at module load.
 */
function seedDatabase(data: unknown): Promise<void> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open('cardvantage')
    request.onupgradeneeded = () => request.result.createObjectStore('state')
    request.onerror = () => reject(request.error)
    request.onsuccess = () => {
      const db = request.result
      const tx = db.transaction('state', 'readwrite')
      tx.objectStore('state').put(data, 'app-data')
      tx.oncomplete = () => {
        db.close()
        resolve()
      }
      tx.onerror = () => reject(tx.error)
    }
  })
}

/**
 * `theme` is a project option (see playwright.config.ts). The seed goes in
 * through settings rather than by stamping `data-theme` on the document,
 * because the shell owns that attribute and would overwrite a stamp.
 *
 * The first load is allowed to finish before seeding: the store saves its
 * snapshot once its initial read resolves, and a seed written before that
 * would be overwritten by the empty default.
 */
export const test = base.extend<{ theme: Theme; seeded: undefined }>({
  theme: ['dark', { option: true }],
  seeded: [
    async ({ page, theme }, use) => {
      await page.goto('/')
      await expect(page.locator('#main').getByText('Loading your cards')).toBeHidden()
      await page.evaluate(seedDatabase, { ...sample, settings: { ...sample.settings, theme } })
      await use(undefined)
    },
    { auto: true },
  ],
})

export { expect }
