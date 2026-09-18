import { For, Show } from 'solid-js'
import { holders } from '../domain/selectors.ts'
import { useApp } from '../stores/app.tsx'
import { Ph } from './Ph.tsx'

/**
 * Narrows the screen to one member of the household.
 *
 * A native `<select>` sits invisibly over a styled row, so mobile gets the OS
 * picker — a custom dropdown here would be worse in every way that matters:
 * no keyboard accessory, no scroll wheel, no VoiceOver rotor.
 *
 * The control hides itself when there is only one person, because a filter with
 * one option is furniture.
 */
export function HolderFilter() {
  const app = useApp()
  const people = () => holders(app.data)

  const count = () =>
    app.data.settings.holderFilter
      ? app.instances().filter((i) => i.card.holder === app.data.settings.holderFilter).length
      : app.instances().length

  return (
    <Show when={people().length > 1}>
      <div class="select-row" style={{ 'margin-bottom': 'var(--space-6)' }}>
        <Ph name="cards-three" size={15} color="var(--color-accent)" />
        <span class="grow truncate" style={{ font: '500 var(--type-body) var(--font-body)' }}>
          {app.data.settings.holderFilter || 'Everyone in the household'}
        </span>
        <span class="muted numeric" style={{ 'font-size': 'var(--type-sm)' }}>
          {count()} credits
        </span>
        <Ph name="caret-down" size={13} color="var(--text-secondary)" />
        <select
          class="select-row__native"
          aria-label="Filter by cardholder"
          value={app.data.settings.holderFilter}
          onChange={(event) => app.updateSettings({ holderFilter: event.currentTarget.value })}
        >
          <option value="">Everyone in the household</option>
          <For each={people()}>{(holder) => <option value={holder}>{holder}</option>}</For>
        </select>
      </div>
    </Show>
  )
}
