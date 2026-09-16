import { useLocation, useNavigate } from '@solidjs/router'
import { For } from 'solid-js'
import { Ph } from './Ph.tsx'
import './TabBar.css'

/**
 * The bottom tab bar: Today, Credits, Cards, Value.
 *
 * Today answers "what do I do now"; Credits is the full ledger including the
 * parts Today hides — locked, captured and periods that already closed.
 */
const TABS = [
  { path: '/', label: 'Today', icon: 'house' },
  { path: '/credits', label: 'Credits', icon: 'list-checks' },
  { path: '/cards', label: 'Cards', icon: 'cards-three' },
  { path: '/value', label: 'Value', icon: 'chart-line-up' },
] as const

export function TabBar() {
  const location = useLocation()
  const navigate = useNavigate()

  // `/cards/new` should still light the Cards tab, so match the section rather
  // than the exact path.
  const isActive = (path: string) =>
    path === '/' ? location.pathname === '/' : location.pathname.startsWith(path)

  return (
    <nav class="tabbar" aria-label="Main">
      <For each={TABS}>
        {(tab) => (
          <button
            type="button"
            class="tabbar__tab"
            classList={{ 'tabbar__tab--active': isActive(tab.path) }}
            aria-current={isActive(tab.path) ? 'page' : undefined}
            onClick={() => navigate(tab.path)}
          >
            <Ph name={tab.icon} fill={isActive(tab.path)} size={21} />
            <span class="tabbar__label">{tab.label}</span>
          </button>
        )}
      </For>
    </nav>
  )
}
