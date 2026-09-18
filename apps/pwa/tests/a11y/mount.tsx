import { createMemoryHistory, MemoryRouter } from '@solidjs/router'
import { render, waitFor } from '@solidjs/testing-library'
import { expect } from 'vitest'
import { routes, Shell } from '../../src/App.tsx'
import { AppProvider, type AppStore, useApp } from '../../src/stores/app.tsx'
import { UiProvider, type UiStore, useUi } from '../../src/stores/ui.tsx'
import { SnackbarProvider } from '../../src/ui/Snackbar.tsx'
import { loadSampleHousehold } from './sample.ts'

/**
 * Mounts the real shell at one route with the sample household loaded, the
 * same composition `App` uses but on a memory router so a test can pick the
 * screen. Resolves once the store has finished its (empty) IndexedDB read and
 * the screen is rendered.
 */
export interface Mounted {
  app: AppStore
  ui: UiStore
  /** The memory history, for navigating the way a link or the back button would. */
  history: ReturnType<typeof createMemoryHistory>
}

export async function mountRoute(path: string): Promise<Mounted> {
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

  app.replaceAll(loadSampleHousehold())
  const store = app
  await waitFor(() => expect(store.loading()).toBe(false))
  return { app, ui, history }
}
