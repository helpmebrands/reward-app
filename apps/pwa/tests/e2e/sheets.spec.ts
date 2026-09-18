import type { Page } from '@playwright/test'
import { expect, test } from './fixtures.ts'

/**
 * Sheets by width: a draggable bottom sheet on a phone, a centred dialog
 * from 600px, and for the credit sheet a side panel beside the list from
 * 1024px. Runs on the shell projects in playwright.config.ts.
 */

async function openFirstCredit(page: Page) {
  await page.goto('/')
  await expect(page.locator('#main').getByText('Loading your cards')).toBeHidden()
  const row = page.locator('.row-card__main').first()
  await row.click()
  const dialog = page.getByRole('dialog')
  await expect(dialog).toBeVisible()
  await dialog
    .locator('.sheet__panel')
    .evaluate((el) => Promise.all(el.getAnimations().map((a) => a.finished)))
  return { row, dialog }
}

// @lat: [[pwa-tests#Accessibility tests#The sheet still drags on a phone]]
test('drags and dismisses past 110px on a phone', async ({ page, viewport }) => {
  if (!viewport) throw new Error('no viewport')
  test.skip(viewport.width >= 600, 'phone widths only')
  const { dialog } = await openFirstCredit(page)
  const grip = await dialog.locator('.sheet__grip').boundingBox()
  if (!grip) throw new Error('no grip')
  const x = grip.x + grip.width / 2
  const y = grip.y + grip.height / 2

  // A slow drag, well under the 0.5 px/ms flick, so only distance counts.
  async function drag(distance: number) {
    await page.mouse.move(x, y)
    await page.mouse.down()
    for (let moved = 10; moved <= distance; moved += 10) {
      await page.mouse.move(x, y + moved)
      await page.waitForTimeout(40)
    }
    await page.mouse.up()
  }

  await drag(60)
  await expect(dialog, 'short drag springs back').toBeVisible()
  // Let it finish springing back, or the next press lands beside the grip.
  await dialog
    .locator('.sheet__panel')
    .evaluate((el) => Promise.all(el.getAnimations().map((a) => a.finished)))
  await drag(130)
  await expect(dialog, 'past 110px dismisses').toBeHidden()
})

// @lat: [[pwa-tests#Accessibility tests#The sheet is a dialog from 600px]]
test('is a centred dialog at a medium width', async ({ page, viewport }) => {
  if (!viewport) throw new Error('no viewport')
  test.skip(viewport.width < 600 || viewport.width >= 1024, 'medium width only')
  const { dialog } = await openFirstCredit(page)
  await expect(dialog.locator('.sheet__grip')).toHaveCount(0)
  const panel = await dialog.locator('.sheet__panel').boundingBox()
  if (!panel) throw new Error('no panel')
  expect(panel.width).toBeLessThanOrEqual(480)
  expect(Math.abs(panel.x + panel.width / 2 - viewport.width / 2)).toBeLessThanOrEqual(1)
  expect(Math.abs(panel.y + panel.height / 2 - viewport.height / 2)).toBeLessThanOrEqual(1)
})

// @lat: [[pwa-tests#Accessibility tests#The credit panel sits beside the list]]
test('is a side panel beside the list at an expanded width', async ({ page, viewport }) => {
  if (!viewport) throw new Error('no viewport')
  test.skip(viewport.width < 1024, 'expanded width only')
  const { row, dialog } = await openFirstCredit(page)
  await expect(dialog.locator('.sheet__grip')).toHaveCount(0)
  const panel = await dialog.locator('.sheet__panel').boundingBox()
  const main = await page.locator('#main').boundingBox()
  if (!panel || !main) throw new Error('no panel or main')
  expect(Math.round(panel.x + panel.width), 'panel on the trailing edge').toBe(viewport.width)
  expect(Math.round(panel.height), 'panel is full height').toBe(viewport.height)
  expect(main.x + main.width, 'list is not covered').toBeLessThanOrEqual(panel.x + 1)

  await page.keyboard.press('Escape')
  await expect(dialog).toBeHidden()
  await expect(row, 'focus returns to the row that opened it').toBeFocused()
})
