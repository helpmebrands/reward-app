import { A } from '@solidjs/router'
import { For, Show } from 'solid-js'
import { formatMoney } from '../domain/format.ts'
import type { CardSummary } from '../domain/selectors.ts'
import { cardLabel } from '../domain/selectors.ts'
import { useApp } from '../stores/app.tsx'
import { Ph } from '../ui/Ph.tsx'
import './Cards.css'
import { useScreenTitle } from '../ui/useScreenTitle.ts'

/**
 * Cards: what each card is actually worth against its fee.
 *
 * The verdict leads with an action rather than a score, and it refuses to price
 * lounge access or status — putting a number on those would be the one
 * judgement the app should not fake.
 */

/** Captured as a share of the fee, expressed as the break-even bar. */
function verdict(summary: CardSummary): { headline: string; body: string; tone: string } {
  const { netCents, annualFeeCents, claimableCents, lockedCents, daysUntilRenewal } = summary

  if (annualFeeCents === 0) {
    return {
      headline: 'No fee',
      body: 'Nothing to break even against — every credit you capture is upside.',
      tone: 'var(--color-accent-300)',
    }
  }
  if (netCents >= 0) {
    return {
      headline: 'Keep',
      body: `Already ${formatMoney(netCents)} past the fee, with ${formatMoney(
        claimableCents,
      )} still open.`,
      tone: 'var(--color-accent-300)',
    }
  }
  if (lockedCents > 0 && claimableCents + lockedCents >= Math.abs(netCents)) {
    return {
      headline: 'Unlock first',
      body: `${formatMoney(
        lockedCents,
      )} is sitting behind an enrolment box. With it, there is enough left this year to clear the ${formatMoney(
        Math.abs(netCents),
      )} shortfall — so unlock it before you weigh a downgrade.`,
      tone: 'var(--tone-locked-fg)',
    }
  }
  if (claimableCents >= Math.abs(netCents)) {
    return {
      headline: 'Catch up',
      body: `${formatMoney(claimableCents)} is still claimable — more than the ${formatMoney(
        Math.abs(netCents),
      )} you are short. ${daysUntilRenewal} days to the renewal.`,
      tone: 'var(--color-accent-300)',
    }
  }
  return {
    headline: 'Decide',
    body: `${formatMoney(Math.abs(netCents))} short with ${daysUntilRenewal} days to the renewal, and only ${formatMoney(
      claimableCents,
    )} left to claim. Lounge access and status are not counted here.`,
    tone: 'var(--tone-missed-fg)',
  }
}

export function Cards() {
  const app = useApp()
  useScreenTitle(() => 'Cards')

  const feeTotal = () => app.cardSummaries().reduce((sum, s) => sum + s.annualFeeCents, 0)
  const capturedTotal = () => app.cardSummaries().reduce((sum, s) => sum + s.capturedCents, 0)

  return (
    <div class="screen__pad">
      <header style={{ 'margin-bottom': 'var(--space-6)' }}>
        <h1 class="screen-title" tabindex="-1">
          Cards
        </h1>
        <Show when={app.cardSummaries().length > 0}>
          <p class="screen-sub" style={{ 'margin-top': 'var(--space-2)', 'max-width': '300px' }}>
            {formatMoney(feeTotal())} in fees this cardmember year. Value captured so far:{' '}
            {formatMoney(capturedTotal())}.
          </p>
        </Show>
      </header>

      <div class="stack stack--loose cards__grid">
        <For each={app.cardSummaries()}>
          {(summary) => {
            const call = verdict(summary)
            return (
              <article class="card cardstat">
                <header class="cardstat__head">
                  <div class="grow">
                    <div class="kicker kicker--quiet">{summary.card.issuer}</div>
                    <h2 class="cardstat__name">{cardLabel(summary.card)}</h2>
                  </div>
                  <button
                    type="button"
                    class="icon-btn"
                    classList={{ 'icon-btn--muted': summary.card.muted }}
                    aria-pressed={summary.card.muted}
                    aria-label={`${summary.card.muted ? 'Unsilence' : 'Silence'} every credit on ${cardLabel(
                      summary.card,
                    )}`}
                    onClick={() => app.toggleCardMute(summary.card.id)}
                  >
                    <Ph name={summary.card.muted ? 'bell-slash' : 'bell'} size={14} />
                  </button>
                </header>

                <dl class="cardstat__figures">
                  <div>
                    <dt class="kicker kicker--quiet">Fee</dt>
                    <dd class="cardstat__figure numeric">{formatMoney(summary.annualFeeCents)}</dd>
                  </div>
                  <div>
                    <dt class="kicker kicker--quiet">Captured</dt>
                    <dd class="cardstat__figure numeric">{formatMoney(summary.capturedCents)}</dd>
                  </div>
                  <div>
                    <dt class="kicker kicker--quiet">Net vs fee</dt>
                    <dd
                      class="cardstat__figure numeric"
                      style={{
                        color:
                          summary.netCents >= 0
                            ? 'var(--color-accent-300)'
                            : 'var(--color-neutral-400)',
                      }}
                    >
                      {summary.netCents >= 0 ? '+' : '−'}
                      {formatMoney(Math.abs(summary.netCents))}
                    </dd>
                  </div>
                </dl>

                {/* The 100% line is break-even, so cards with different fees
                    stay comparable. */}
                <div
                  class="bar"
                  role="progressbar"
                  aria-valuemin={0}
                  aria-valuemax={100}
                  aria-valuenow={Math.round(Math.min(1, summary.feeProgress) * 100)}
                  aria-label="Share of the annual fee earned back"
                >
                  <div
                    class="bar__fill"
                    style={{ width: `${Math.min(100, summary.feeProgress * 100)}%` }}
                  />
                </div>
                <p class="cardstat__pct numeric">
                  {Math.round(summary.feeProgress * 100)}% of the fee earned back &middot;{' '}
                  {summary.daysUntilRenewal} days to renewal
                </p>

                <p class="cardstat__verdict">
                  <strong style={{ color: call.tone }}>{call.headline}.</strong> {call.body}
                </p>

                <div class="cardstat__tags">
                  <Show when={summary.claimableCents > 0}>
                    <span class="tag tag--accent">
                      <Ph name="hourglass-high" size={11} />
                      {formatMoney(summary.claimableCents)} claimable
                    </span>
                  </Show>
                  <Show when={summary.lockedCents > 0}>
                    <span class="tag tag--locked">
                      <Ph name="lock-simple" size={11} />
                      {formatMoney(summary.lockedCents)} locked
                    </span>
                  </Show>
                  <Show when={summary.missedCents > 0}>
                    <span class="tag tag--missed">
                      <Ph name="hourglass-low" size={11} />
                      {formatMoney(summary.missedCents)} missed
                    </span>
                  </Show>
                  <span class="tag">
                    {summary.instances.length} credit{summary.instances.length === 1 ? '' : 's'}
                  </span>
                </div>

                <A class="btn btn--block cardstat__edit" href={`/cards/${summary.card.id}`}>
                  <Ph name="sliders-horizontal" size={14} />
                  Edit card and credits
                </A>
              </article>
            )
          }}
        </For>

        <A class="btn btn--dashed" href="/cards/new">
          <Ph name="plus" size={14} />
          Add a card from the catalogue
        </A>
      </div>

      <Show when={app.cardSummaries().length === 0}>
        <div class="empty">
          <span class="empty__glyph">
            <Ph name="cards-three" />
          </span>
          <h2 class="section-title">Start with one card</h2>
          <p class="section-note">
            Pick it from the catalogue and its credits come pre-filled, including which ones are
            stuck behind an enrolment box. You can edit every one of them afterwards.
          </p>
        </div>
      </Show>
    </div>
  )
}
