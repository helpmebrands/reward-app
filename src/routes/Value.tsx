import { createMemo, createSignal, For, Show } from 'solid-js'
import { formatMoney } from '../domain/format.ts'
import { biggestLeaks, cardLabel, monthlyTotals } from '../domain/selectors.ts'
import { useApp } from '../stores/app.tsx'
import { Ph } from '../ui/Ph.tsx'
import './Value.css'
import { useScreenTitle } from '../ui/useScreenTitle.ts'

/**
 * Value: what the household actually got, and what leaked away.
 *
 * Cards are ranked worst-first and plotted as a percentage of *their own* fee
 * rather than in dollars. Six cards with six different fees cannot share a
 * dollar axis; on a percentage axis the 100% line is break-even for all of
 * them, and a $325 Gold is comparable with an $895 Platinum.
 */
export function Value() {
  const app = useApp()
  useScreenTitle(() => 'Value')
  const [monthsBack, setMonthsBack] = createSignal(9)

  const missed = () => app.missed()
  const months = createMemo(() => monthlyTotals(app.data, missed(), app.today(), monthsBack()))
  const leaks = createMemo(() => biggestLeaks(missed()))

  const capturedTotal = () => months().reduce((sum, m) => sum + m.capturedCents, 0)
  const missedTotal = () => months().reduce((sum, m) => sum + m.missedCents, 0)

  /** Bars share one scale, so a tall month is tall on every card. */
  const peak = () => Math.max(1, ...months().map((m) => Math.max(m.capturedCents, m.missedCents)))

  const ranked = createMemo(() =>
    [...app.cardSummaries()].sort((a, b) => a.feeProgress - b.feeProgress),
  )

  return (
    <div class="screen__pad">
      <header style={{ 'margin-bottom': 'var(--space-6)' }}>
        <h1 class="screen-title" tabindex="-1">
          Value
        </h1>
        <p class="screen-sub" style={{ 'margin-top': 'var(--space-2)' }}>
          Last {monthsBack()} months &middot;{' '}
          <Show
            when={app.cardSummaries().length === 1 && app.cardSummaries()[0]}
            fallback={`${app.cardSummaries().length} cards`}
          >
            {(only) => cardLabel(only().card)}
          </Show>
        </p>
      </header>

      <div class="value__totals">
        <div class="value__total value__total--captured">
          <span class="kicker">Captured</span>
          <span class="value__figure numeric">{formatMoney(capturedTotal())}</span>
        </div>
        <div class="value__total">
          <span class="kicker kicker--quiet">Missed</span>
          <span class="value__figure numeric" style={{ color: 'var(--color-neutral-500)' }}>
            {formatMoney(missedTotal())}
          </span>
        </div>
      </div>

      <Show when={missedTotal() > 0}>
        <div class="feature" style={{ 'margin-bottom': 'var(--space-8)' }}>
          <p class="value__lead">{formatMoney(missedTotal())} has expired unclaimed</p>
          <p class="value__lead-body">
            <Show when={leaks()[0]} fallback="Nothing is repeating — these were one-off windows.">
              {(worst) => (
                <>
                  The biggest single leak is {worst().label} at {formatMoney(worst().missedCents)}.
                  Small recurring credits are exactly the shape of loss the reminder ladder exists
                  for.
                </>
              )}
            </Show>
          </p>
        </div>
      </Show>

      <section class="section">
        <div class="row row--between row--baseline" style={{ 'margin-bottom': 'var(--space-4)' }}>
          <h2 class="section-title">Captured against missed, by month</h2>
          <div class="seg" style={{ flex: 'none' }}>
            <For each={[6, 9, 12]}>
              {(count) => (
                <button
                  type="button"
                  class="seg__opt"
                  aria-pressed={monthsBack() === count}
                  onClick={() => setMonthsBack(count)}
                >
                  {count}m
                </button>
              )}
            </For>
          </div>
        </div>

        <p class="value__scale numeric" aria-hidden="true">
          Tallest bar = {formatMoney(peak())}
        </p>

        {/* The chart is decorative; the table below carries the same numbers. */}
        <div class="value__chart" aria-hidden="true">
          <For each={months()}>
            {(month) => (
              <div class="value__col">
                <div
                  class="value__bar value__bar--missed"
                  style={{ height: `${(month.missedCents / peak()) * 100}%` }}
                />
                <div
                  class="value__bar value__bar--captured"
                  style={{ height: `${(month.capturedCents / peak()) * 100}%` }}
                />
              </div>
            )}
          </For>
        </div>
        <div class="value__labels" aria-hidden="true">
          <For each={months()}>{(month) => <span>{month.label}</span>}</For>
        </div>

        <div class="visually-hidden">
          <table>
            <caption>Captured against missed, by month</caption>
            <thead>
              <tr>
                <th scope="col">Month</th>
                <th scope="col">Captured</th>
                <th scope="col">Missed</th>
              </tr>
            </thead>
            <tbody>
              <For each={months()}>
                {(month) => (
                  <tr>
                    <th scope="row">{month.label}</th>
                    <td>{formatMoney(month.capturedCents)}</td>
                    <td>{formatMoney(month.missedCents)}</td>
                  </tr>
                )}
              </For>
            </tbody>
          </table>
        </div>

        <ul class="legend" style={{ 'margin-top': 'var(--space-4)' }}>
          <li class="legend__item">
            <span class="legend__swatch" style={{ background: 'var(--color-accent)' }} />
            Captured
          </li>
          <li class="legend__item">
            <span class="legend__swatch" style={{ background: 'var(--chart-missed)' }} />
            Missed
          </li>
        </ul>
      </section>

      <Show when={ranked().length > 1}>
        <section class="section">
          <h2 class="section-title">Cards against their own fee</h2>
          <p class="section-note" style={{ margin: 'var(--space-2) 0 var(--space-4)' }}>
            Worst first. The line at 100% is break-even, so cards with different fees stay
            comparable.
          </p>
          <div class="stack stack--tight">
            <For each={ranked()}>
              {(summary) => (
                <div class="value__rank">
                  <div class="row row--between" style={{ 'margin-bottom': 'var(--space-2)' }}>
                    <span class="grow" style={{ 'font-size': 'var(--type-body-sm)' }}>
                      {cardLabel(summary.card)}
                    </span>
                    <span
                      class="numeric"
                      style={{
                        'font-size': 'var(--type-body-sm)',
                        color:
                          summary.feeProgress >= 1
                            ? 'var(--color-accent-300)'
                            : 'var(--color-neutral-500)',
                      }}
                    >
                      {Math.round(summary.feeProgress * 100)}%
                    </span>
                  </div>
                  <div class="value__track">
                    <div
                      class="value__track-fill"
                      style={{ width: `${Math.min(100, summary.feeProgress * 100)}%` }}
                    />
                    <span class="value__breakeven" aria-hidden="true" />
                  </div>
                </div>
              )}
            </For>
          </div>
        </section>
      </Show>

      <Show when={leaks().length > 0}>
        <section class="section">
          <h2 class="section-title">Biggest leaks</h2>
          <p class="section-note" style={{ margin: 'var(--space-2) 0 var(--space-4)' }}>
            Recurring credits that expired unclaimed, worst first.
          </p>
          <ul class="list">
            <For each={leaks()}>
              {(leak) => (
                <li class="value__leak">
                  <Ph name={leak.icon ?? 'hourglass-low'} size={14} />
                  <span class="grow">
                    <span class="value__leak-title">{leak.label}</span>
                    <span class="value__leak-when">{leak.when}</span>
                  </span>
                  <span class="value__leak-amount numeric">{formatMoney(leak.missedCents)}</span>
                </li>
              )}
            </For>
          </ul>
        </section>
      </Show>

      <Show when={app.data.cards.length === 0}>
        <div class="empty">
          <span class="empty__glyph">
            <Ph name="chart-line-up" />
          </span>
          <p class="section-note">
            Once a card is added and a few windows have closed, this screen shows what you captured
            against what slipped.
          </p>
        </div>
      </Show>
    </div>
  )
}
