import { Show } from 'solid-js'
import { Ph } from './Ph.tsx'
import './TopBar.css'

interface TopBarProps {
  title: string
  subtitle?: string | undefined
  onBack: () => void
  /** Optional destructive or secondary action on the trailing edge. */
  action?: { icon: string; label: string; onAct: () => void } | undefined
}

/** The app bar on secondary screens — anything that is not a tab. */
export function TopBar(props: TopBarProps) {
  return (
    <header class="topbar">
      <button
        type="button"
        class="icon-btn icon-btn--boxed"
        aria-label="Back"
        onClick={props.onBack}
      >
        <Ph name="arrow-left" size={15} />
      </button>
      <div class="grow">
        <h1 class="topbar__title" tabindex="-1">
          {props.title}
        </h1>
        <Show when={props.subtitle}>
          <p class="topbar__sub">{props.subtitle}</p>
        </Show>
      </div>
      <Show when={props.action}>
        {(action) => (
          <button
            type="button"
            class="icon-btn icon-btn--boxed"
            aria-label={action().label}
            onClick={action().onAct}
          >
            <Ph name={action().icon} size={15} />
          </button>
        )}
      </Show>
    </header>
  )
}
