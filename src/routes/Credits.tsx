import { createMemo, createSignal, For, Show } from 'solid-js'
import { cadenceLabel } from '../domain/cycles.ts'
import { formatMoney } from '../domain/format.ts'
import {
  byStatus,
  cardLabel,
  categoryLabel,
  isClaimable,
  statusLabel,
  sumClaimed,
  sumRemaining,
  totalsFor,
} from '../domain/selectors.ts'
import type { BenefitInstance, BenefitStatus } from '../domain/types.ts'
import { useApp } from '../stores/app.tsx'
import { useUi } from '../stores/ui.tsx'
import { CreditRow } from '../ui/CreditRow.tsx'
import { HolderFilter } from '../ui/HolderFilter.tsx'
import { Ph } from '../ui/Ph.tsx'
import { useCreditActions } from '../ui/useCreditActions.ts'
import './Credits.css'
import { useScreenTitle } from '../ui/useScreenTitle.ts'

/**
 * Credits: the ledger.
 *
 * Today says *do this now*. This screen shows everything that exists and where
 * it stands, including the parts Today hides — locked, captured, and the
 * periods that already closed unused.
 *
 * Four totals rather than one. "Claimable" and "missed" must never be summed:
 * money you can still get and money you have already lost are not the same
 * quantity, and a single figure combining them would mean nothing.
 */

type Grouping = 'card' | 'cycle' | 'status'
type Filter = 'all' | 'use_soon' | 'open' | 'locked' | 'captured' | 'missed'

const FILTERS: Array<{ id: Filter; label: string }> = [
  { id: 'all', label: 'All' },
  { id: 'use_soon', label: 'Use soon' },
  { id: 'open', label: 'Open' },
  { id: 'locked', label: 'Locked' },
  { id: 'captured', label: 'Captured' },
  { id: 'missed', label: 'Missed' },
]

const GROUPINGS: Array<{ id: Grouping; label: string }> = [
  { id: 'card', label: 'Card' },
  { id: 'cycle', label: 'Cycle' },
  { id: 'status', label: 'Status' },
]

interface Group {
  key: string
  label: string
  tone: string
  instances: BenefitInstance[]
  /** One labelled figure that follows the filter — never a mixed sum. */
  figure: string
}

const STATUS_TONE: Record<BenefitStatus, string> = {
  use_soon: 'var(--color-accent)',
  available: 'var(--color-accent-700)',
  locked: 'var(--tone-locked)',
  captured: 'var(--color-neutral-800)',
  manual: 'var(--color-neutral-800)',
  missed: 'var(--tone-missed)',
}

export function Credits() {
  const app = useApp()
  useScreenTitle(() => 'Credits')
  const ui = useUi()
  const actions = useCreditActions()
  const [grouping, setGrouping] = createSignal<Grouping>('card')
  const [filter, setFilter] = createSignal<Filter>('all')

  /**
   * Closed windows are folded in as first-class rows so "Missed" is itemised
   * per credit rather than sitting as one number on the Value tab.
   */
  const allRows = createMemo<BenefitInstance[]>(() => {
    const live = app.visibleInstances()
    const holder = app.data.settings.holderFilter
    const missedRows: BenefitInstance[] = app
      .missed()
      .filter((entry) => !holder || entry.card.holder === holder)
      .map((entry) => ({
        benefit: entry.benefit,
        card: entry.card,
        cycle: entry.cycle,
        status: 'missed' as const,
        claimedCents: entry.benefit.valueCents - entry.missedCents,
        remainingCents: entry.missedCents,
        daysRemaining: -1,
        cycleProgress: 1,
        muted: entry.benefit.muted || entry.card.muted,
      }))
    return [...live, ...missedRows]
  })

  const filtered = createMemo(() => {
    const rows = allRows()
    switch (filter()) {
      case 'use_soon':
        return byStatus(rows, 'use_soon')
      case 'open':
        return rows.filter(isClaimable)
      case 'locked':
        return byStatus(rows, 'locked')
      case 'captured':
        return rows.filter((row) => row.claimedCents > 0 && row.status !== 'missed')
      case 'missed':
        return byStatus(rows, 'missed')
      default:
        return rows
    }
  })

  const totals = createMemo(() =>
    totalsFor(
      app.visibleInstances(),
      app
        .missed()
        .filter(
          (entry) =>
            !app.data.settings.holderFilter || entry.card.holder === app.data.settings.holderFilter,
        )
        .reduce((sum, entry) => sum + entry.missedCents, 0),
    ),
  )

  /** The figure a group header carries, matched to the active filter. */
  function figureFor(instances: BenefitInstance[]): string {
    if (filter() === 'missed') return `${formatMoney(sumRemaining(instances))} missed`
    if (filter() === 'captured') return `${formatMoney(sumClaimed(instances))} captured`
    if (filter() === 'locked') return `${formatMoney(sumRemaining(instances))} locked`
    const claimable = instances.filter(isClaimable)
    return `${formatMoney(sumRemaining(claimable))} claimable`
  }

  const groups = createMemo<Group[]>(() => {
    const buckets = new Map<string, BenefitInstance[]>()
    for (const row of filtered()) {
      const key =
        grouping() === 'card'
          ? row.card.id
          : grouping() === 'cycle'
            ? row.benefit.cadence
            : row.status
      const bucket = buckets.get(key)
      if (bucket) bucket.push(row)
      else buckets.set(key, [row])
    }

    return [...buckets.entries()]
      .map(([key, instances]) => {
        const first = instances[0]
        if (!first) return null
        const label =
          grouping() === 'card'
            ? cardLabel(first.card)
            : grouping() === 'cycle'
              ? cadenceLabel(first.benefit.cadence)
              : statusLabel(first.status)
        return {
          key,
          label,
          tone: grouping() === 'status' ? STATUS_TONE[first.status] : 'var(--color-accent-700)',
          instances,
          figure: figureFor(instances),
        }
      })
      .filter((group): group is Group => group !== null)
  })

  return (
    <div class="screen__pad">
      <header style={{ 'margin-bottom': 'var(--space-6)' }}>
        <h1 class="screen-title" tabindex="-1">
          All credits
        </h1>
        <p class="screen-sub" style={{ 'margin-top': 'var(--space-2)' }}>
          {app.visibleInstances().filter(isClaimable).length} open &middot;{' '}
          {byStatus(app.visibleInstances(), 'locked').length} locked &middot; {app.missed().length}{' '}
          missed
        </p>
      </header>

      <HolderFilter />

      {/* Four totals kept deliberately apart. */}
      <ul class="totals">
        <li class="totals__item totals__item--claimable">
          <span class="kicker">Claimable</span>
          <span class="totals__figure numeric">{formatMoney(totals().claimableCents)}</span>
        </li>
        <li class="totals__item totals__item--locked">
          <span class="kicker kicker--quiet">Locked</span>
          <span class="totals__figure numeric">{formatMoney(totals().lockedCents)}</span>
        </li>
        <li class="totals__item">
          <span class="kicker kicker--quiet">Captured</span>
          <span class="totals__figure numeric">{formatMoney(totals().capturedCents)}</span>
        </li>
        <li class="totals__item" classList={{ 'totals__item--missed': totals().missedCents > 0 }}>
          <span class="kicker kicker--quiet">Missed</span>
          <span class="totals__figure numeric">{formatMoney(totals().missedCents)}</span>
        </li>
      </ul>

      <div class="credits__controls">
        <div class="seg" role="tablist" aria-label="Group credits by">
          <For each={GROUPINGS}>
            {(option) => (
              <button
                type="button"
                role="tab"
                class="seg__opt"
                aria-selected={grouping() === option.id}
                onClick={() => setGrouping(option.id)}
              >
                {option.label}
              </button>
            )}
          </For>
        </div>

        <fieldset class="credits__filters">
          <legend class="visually-hidden">Filter by status</legend>
          <For each={FILTERS}>
            {(option) => (
              <button
                type="button"
                class="seg__opt credits__filter"
                aria-pressed={filter() === option.id}
                onClick={() => setFilter(option.id)}
              >
                {option.label}
              </button>
            )}
          </For>
        </fieldset>
      </div>

      <Show
        when={groups().length > 0}
        fallback={
          <div class="empty">
            <span class="empty__glyph">
              <Ph name="funnel" />
            </span>
            <p class="section-note">Nothing matches that filter.</p>
          </div>
        }
      >
        <For each={groups()}>
          {(group) => (
            <section class="credits__group">
              <div class="credits__group-head">
                <span
                  class="credits__group-dot"
                  style={{ background: group.tone }}
                  aria-hidden="true"
                />
                <h2 class="credits__group-label">{group.label}</h2>
                <span class="rule" aria-hidden="true" />
                <span class="muted numeric" style={{ 'font-size': '11px' }}>
                  {group.figure}
                </span>
              </div>
              <div class="list">
                <For each={group.instances}>
                  {(instance) => (
                    <CreditRow
                      instance={instance}
                      showCard={grouping() !== 'card'}
                      onOpen={() => ui.openCredit(instance.benefit.id)}
                      onLogAll={() => actions.logAll(instance)}
                      onToggleMute={() => actions.toggleMute(instance)}
                    />
                  )}
                </For>
              </div>
              <Show when={grouping() === 'card' && group.instances[0]}>
                {(first) => (
                  <p class="credits__group-foot">
                    {categoryLabel(first().benefit.category)} and {group.instances.length - 1} more
                    on this card
                  </p>
                )}
              </Show>
            </section>
          )}
        </For>
      </Show>
    </div>
  )
}
