import { createMemoryHistory, MemoryRouter } from '@solidjs/router'
import { render, waitFor } from '@solidjs/testing-library'
import { expect } from 'vitest'
import sample from '../../samples/sample-household.json'
import { routes, Shell } from '../../src/App.tsx'
import type { AppData } from '../../src/domain/types.ts'
import { AppProvider, type AppStore, useApp } from '../../src/stores/app.tsx'
import { UiProvider, type UiStore, useUi } from '../../src/stores/ui.tsx'
import { SnackbarProvider } from '../../src/ui/Snackbar.tsx'

/**
 * Mounts the real shell at one route with the sample household loaded, the
 * same composition `App` uses but on a memory router so a test can pick the
 * screen. Resolves once the store has finished its (empty) IndexedDB read and
 * the screen is rendered.
 */
export async function mountRoute(path: string): Promise<{ app: AppStore; ui: UiStore }> {
  // index.html declares the language; the jsdom document does not load it.
  document.documentElement.lang = 'en'

  const history = createMemoryHistory()
  history.set({ value: path })

  let app: AppStore | undefined
  let ui: UiStore | undefined
  function Probe() {
    app = useApp()
    ui = useUi()
    return null
  }

  render(() => (
    <AppProvider>
      <UiProvider>
        <Probe />
        <SnackbarProvider>
          <MemoryRouter history={history} root={Shell}>
            {routes}
          </MemoryRouter>
        </SnackbarProvider>
      </UiProvider>
    </AppProvider>
  ))
  if (!app || !ui) throw new Error('shell did not mount')

  app.replaceAll(sample as AppData)
  const store = app
  await waitFor(() => expect(store.loading()).toBe(false))
  return { app, ui }
}
