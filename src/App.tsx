import { type RouteDefinition, Router, useLocation, useNavigate } from '@solidjs/router'
import { createEffect, on, onCleanup, onMount, type ParentProps, Show } from 'solid-js'
import type { OverlapGroup } from './domain/selectors.ts'
import { findOverlaps } from './domain/selectors.ts'
import type { BenefitInstance } from './domain/types.ts'
import { AddCard } from './routes/AddCard.tsx'
import { BenefitEditor } from './routes/BenefitEditor.tsx'
import { CardEditor } from './routes/CardEditor.tsx'
import { Cards } from './routes/Cards.tsx'
import { Credits } from './routes/Credits.tsx'
import { Settings } from './routes/Settings.tsx'
import { Today } from './routes/Today.tsx'
import { Value } from './routes/Value.tsx'
import { publishSchedule } from './services/notifications.ts'
import { AppProvider, useApp } from './stores/app.tsx'
import { UiProvider, useUi } from './stores/ui.tsx'
import { CompareSheet } from './ui/CompareSheet.tsx'
import { CreditSheet } from './ui/CreditSheet.tsx'
import { NudgePreview } from './ui/NudgePreview.tsx'
import { Ph } from './ui/Ph.tsx'
import { SnackbarProvider } from './ui/Snackbar.tsx'
import { TabBar } from './ui/TabBar.tsx'
import { useScreenTitle } from './ui/useScreenTitle.ts'

/**
 * The app shell, used as the router's root layout.
 *
 * It has to sit inside `<Router>` — the tab bar and the notification handler
 * both use router primitives — and it renders the sheets so that a credit
 * opened from Today, from Credits or from a compare all share one instance.
 *
 * Exported, with `routes`, so the accessibility tests can mount the real
 * shell on a memory router.
 */
export function Shell(props: ParentProps) {
  const app = useApp()
  const ui = useUi()
  const navigate = useNavigate()
  const location = useLocation()

  const openInstance = (): BenefitInstance | null =>
    app.instances().find((i) => i.benefit.id === ui.openBenefitId()) ?? null

  const openOverlap = (): OverlapGroup | null =>
    findOverlaps(app.visibleInstances()).find((o) => o.label === ui.openOverlapLabel()) ?? null

  // Keep the worker's schedule in step with the data. Recomputing on every
  // change is cheap; a stale schedule means a missed reminder.
  createEffect(() => {
    if (app.loading()) return
    const snapshot = JSON.parse(JSON.stringify(app.data)) as typeof app.data
    void publishSchedule(snapshot).catch(() => undefined)
  })

  // The theme goes on the document element, where the token sheet's
  // `[data-theme]` selectors can see it.
  createEffect(() => {
    const theme = app.data.settings.theme
    if (theme === 'system') document.documentElement.removeAttribute('data-theme')
    else document.documentElement.setAttribute('data-theme', theme)
  })

  // Moving between screens never reloads the document, so focus would stay
  // wherever it was — often on a control that no longer exists — and a screen
  // reader would say nothing. Each screen's <h1> carries tabindex="-1" and
  // takes focus on arrival (WCAG 2.4.3). A tab press is the exception: the
  // user is still on the tab they pressed, and stays there. The first render
  // is skipped so the page loads with focus at the top, as pages do.
  createEffect(
    on(
      () => location.pathname,
      () => {
        if (document.activeElement?.closest('.tabbar')) return
        queueMicrotask(() => document.querySelector<HTMLElement>('#main h1')?.focus())
      },
      { defer: true },
    ),
  )

  // A tapped notification asks the worker to bring us to the right screen.
  onMount(() => {
    const onMessage = (event: MessageEvent) => {
      const data = event.data as { type?: string; url?: string } | undefined
      if (data?.type === 'navigate' && data.url) navigate(data.url)
    }
    navigator.serviceWorker?.addEventListener('message', onMessage)
    onCleanup(() => navigator.serviceWorker?.removeEventListener('message', onMessage))
  })

  return (
    <div class="shell">
      <div class="shell__glow" aria-hidden="true">
        <div class="shell__bloom" />
      </div>
      <a class="skip-link" href="#main">
        Skip to content
      </a>

      <NudgePreview
        reminder={ui.nudge()}
        onDismiss={ui.dismissNudge}
        onOpen={() => {
          ui.dismissNudge()
          navigate('/')
        }}
      />

      <main class="screen" id="main">
        <Show
          when={!app.loading()}
          fallback={
            <p class="screen__pad muted" role="status">
              Loading your cards&hellip;
            </p>
          }
        >
          {props.children}
        </Show>
      </main>

      <CreditSheet instance={openInstance()} onClose={ui.closeCredit} />
      <CompareSheet
        overlap={openOverlap()}
        onClose={ui.closeOverlap}
        onOpenCredit={(benefitId) => {
          ui.closeOverlap()
          ui.openCredit(benefitId)
        }}
      />

      <TabBar />
    </div>
  )
}

function NotFound() {
  useScreenTitle(() => 'Not found')
  return (
    <div class="screen__pad empty">
      <span class="empty__glyph">
        <Ph name="compass" />
      </span>
      <h1 class="section-title" tabindex="-1">
        That screen does not exist.
      </h1>
      <a class="btn btn--primary" href="/">
        Back to Today
      </a>
    </div>
  )
}

export const routes: RouteDefinition[] = [
  { path: '/', component: Today },
  { path: '/credits', component: Credits },
  { path: '/cards', component: Cards },
  { path: '/cards/new', component: AddCard },
  { path: '/cards/:id', component: CardEditor },
  { path: '/benefit/:id', component: BenefitEditor },
  { path: '/value', component: Value },
  { path: '/settings', component: Settings },
  { path: '*', component: NotFound },
]

export function App() {
  return (
    <AppProvider>
      <UiProvider>
        <SnackbarProvider>
          <Router root={Shell}>{routes}</Router>
        </SnackbarProvider>
      </UiProvider>
    </AppProvider>
  )
}
