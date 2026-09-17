import { defineConfig, devices } from '@playwright/test'
import type { Theme } from './tests/e2e/fixtures.ts'

/**
 * One project per width and theme, so a violation names where it happens.
 *
 * 320 is the narrowest phone WCAG 1.4.10 asks for, 402 is the design's own
 * column, 768 is a tablet or a landscape phone, 1280 is a desktop window.
 * Heights are a real device at each width. The suite runs against
 * `vite preview` of `dist/`, so build first.
 */
const VIEWPORTS: ReadonlyArray<{ width: number; height: number }> = [
  { width: 320, height: 568 },
  { width: 402, height: 874 },
  { width: 768, height: 1024 },
  { width: 1280, height: 800 },
]
const THEMES: readonly Theme[] = ['light', 'dark']

const PORT = 4173

export default defineConfig<{ theme: Theme }>({
  testDir: 'tests/e2e',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  reporter: [['list'], ['html', { open: process.env.CI ? 'never' : 'on-failure' }]],
  use: {
    baseURL: `http://localhost:${PORT}`,
    // The worker would otherwise serve a stale precache between runs.
    serviceWorkers: 'block',
    trace: 'retain-on-failure',
  },
  projects: [
    ...VIEWPORTS.flatMap((viewport) =>
      THEMES.map((theme) => ({
        name: `${viewport.width}px-${theme}`,
        testMatch: /a11y\.spec\.ts/,
        use: { ...devices['Desktop Chrome'], viewport, theme },
      })),
    ),
    // A phone on its side; the shortest viewport the compact layout serves.
    {
      name: '667x375-landscape',
      testMatch: /landscape\.spec\.ts/,
      use: { ...devices['Desktop Chrome'], viewport: { width: 667, height: 375 }, theme: 'dark' },
    },
    // The narrowest width WCAG 1.4.10 names: a desktop window at 400% zoom.
    {
      name: '320px-reflow',
      testMatch: /reflow\.spec\.ts/,
      use: { ...devices['Desktop Chrome'], viewport: { width: 320, height: 568 }, theme: 'dark' },
    },
    // The shell at each width: phone layout pinned below 600px, a rail above.
    ...[320, 402, 768, 1280].map((width) => ({
      name: `${width}px-shell`,
      testMatch: /shell\.spec\.ts/,
      use: {
        ...devices['Desktop Chrome'],
        viewport: { width, height: width < 600 ? 800 : 900 },
        theme: 'dark' as Theme,
      },
    })),
    // The design's own width with the browser font size raised to 24px.
    {
      name: '402px-large-type',
      testMatch: /large-type\.spec\.ts/,
      use: { ...devices['Desktop Chrome'], viewport: { width: 402, height: 874 }, theme: 'dark' },
    },
  ],
  webServer: {
    command: `npm run preview -- --port ${PORT} --strictPort`,
    url: `http://localhost:${PORT}`,
    reuseExistingServer: !process.env.CI,
  },
})
