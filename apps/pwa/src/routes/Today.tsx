import { createMemo, For, Index, Show } from 'solid-js'
import { formatHeaderDate, formatMoney, formatResetDate, moneyParts } from '../domain/format.ts'
import {
  byStatus,
  cardLabel,
  findOverlaps,
  isClaimable,
  nextReset,
  sumClaimed,
  sumRemaining,
  totalsFor,
} from '../domain/selectors.ts'
import { readSchedule } from '../services/notifications.ts'
import { useApp } from '../stores/app.tsx'
import { useUi } from '../stores/ui.tsx'
import { CreditRow } from '../ui/CreditRow.tsx'
import { HolderFilter } from '../ui/HolderFilter.tsx'
import { sampleReminder } from '../ui/NudgePreview.tsx'
import { Ph } from '../ui/Ph.tsx'
import { useCreditActions } from '../ui/useCreditActions.ts'
import './Today.css'
import { useScreenTitle } from '../ui/useScreenTitle.ts'

/**
 * Today: one number, a countdown, and the rows behind them.
 *
 * The headline deliberately counts only what is *claimable* — locked credits
 * get their own section further down. Adding money the user cannot spend into
 * the number they are meant to act on would make the number a lie.
 */

export function Today() {
  const app = useApp()
  useScreenTitle(() => 'Today')
  const ui = useUi()
  const actions = useCreditActions()

  /**
   * Shows the next real reminder, with the user's own numbers in it.
   * Notification permission is a big ask on faith; showing exactly what will
   * arrive is the honest way to make it.
   */
  async function previewNudge() {
    const schedule = await readSchedule()
    const next = schedule?.reminders.find((reminder) => reminder.fireAt > Date.now())
    ui.showNudge(next ?? sampleReminder(sumRemaining(instances().filter(isClaimable))))
  }

  const instances = () => app.visibleInstances()
  const soon = () => byStatus(instances(), 'use_soon')
  const locked = () => byStatus(instances(), 'locked')
  const captured = () => instances().filter((i) => i.claimedCents > 0)
  const allOverlaps = createMemo(() => findOverlaps(instances()))
  const overlaps = () => allOverlaps().slice(0, 3)

  const totals = createMemo(() =>
    totalsFor(
      instances(),
      app.missed().reduce((sum, m) => sum + m.missedCents, 0),
    ),
  )

  const reset = () => nextReset(instances())
  const daysToReset = () => soon()[0]?.daysRemaining ?? null

  // The three bands of the split bar. Flex weights rather than percentages, so
  // a tiny band still shows its label instead of collapsing to nothing.
  const bands = createMemo(() => {
    const soonCents = sumRemaining(soon())
    const availableCents = sumRemaining(byStatus(instances(), 'available'))
    const capturedCents = sumClaimed(instances())
    const total = soonCents + availableCents + capturedCents
    // A band narrower than its own label spills the text outside the fill. The
    // legend underneath carries every figure anyway, so narrow bands go bare.
    const fits = (cents: number) => total > 0 && cents / total > 0.16
    return {
      soonCents,
      availableCents,
      capturedCents,
      total,
      showSoon: fits(soonCents),
      showAvailable: fits(availableCents),
      showCaptured: fits(capturedCents),
    }
  })

  const headlineSub = () => {
    const open = instances().filter(isClaimable).length
    if (open === 0) return 'Nothing is waiting on you. Every open credit is used.'
    const resetOn = reset()
    const soonest = resetOn ? ` The nearest window shuts ${formatResetDate(resetOn)}.` : ''
    return `${open} open credit${open === 1 ? '' : 's'} across ${
      new Set(instances().map((i) => i.card.id)).size
    } card${new Set(instances().map((i) => i.card.id)).size === 1 ? '' : 's'}.${soonest}`
  }

  const hasCards = () => app.data.cards.some((card) => !card.archived)

  return (
    <div class="screen__pad">
      <header class="today__head">
        {/* The heading carries the screen's name; the logotype is decoration. */}
        <h1 class="visually-hidden" tabindex="-1">
          Today
        </h1>
        <div class="row row--baseline" style={{ gap: 'var(--space-3)' }}>
          {/* Two renders of the logotype, one per ground; the theme selector
              in Today.css shows whichever matches the current background. */}
          <img
            class="today__logotype today__logotype--dark"
            src="/brand/logotype-horz-dark.png"
            alt=""
            width="1024"
            height="178"
          />
          <img
            class="today__logotype today__logotype--light"
            src="/brand/logotype-horz-light.png"
            alt=""
            width="1024"
            height="178"
          />
          <span class="today__dot" />
          <span
            class="muted"
            style={{ 'font-size': 'var(--type-caption)', 'white-space': 'nowrap' }}
          >
            {formatHeaderDate(app.today())}
          </span>
        </div>
        <div class="row" style={{ gap: 'var(--space-2)' }}>
          <button type="button" class="btn btn--small" onClick={() => void previewNudge()}>
            <Ph name="bell-ringing" size={13} />
            Preview nudge
          </button>
          {/* The only way into Settings, and therefore into turning reminders
              on at all — so it lives on the screen people open every day. */}
          <a class="icon-btn" href="/settings" aria-label="Settings">
            <Ph name="gear-six" size={17} />
          </a>
        </div>
      </header>

      <Show when={hasCards()} fallback={<FirstRun />}>
        <div class="today__body">
          <HolderFilter />

          <section class="today__headline" aria-labelledby="today-headline-label">
            <div class="kicker" id="today-headline-label">
              Unclaimed, open periods
            </div>
            <p class="today__amount numeric">
              <span class="today__amount-symbol">{moneyParts(totals().claimableCents).symbol}</span>
              <span class="today__amount-digits">{moneyParts(totals().claimableCents).digits}</span>
            </p>
            <p class="today__sub">{headlineSub()}</p>

            <Show when={bands().total > 0}>
              <div class="split" aria-hidden="true">
                <Show when={bands().soonCents > 0}>
                  <div class="split__part split__part--soon" style={{ flex: bands().soonCents }}>
                    <Show when={bands().showSoon}>{formatMoney(bands().soonCents)}</Show>
                  </div>
                </Show>
                <Show when={bands().availableCents > 0}>
                  <div
                    class="split__part split__part--available"
                    style={{ flex: bands().availableCents }}
                  >
                    <Show when={bands().showAvailable}>{formatMoney(bands().availableCents)}</Show>
                  </div>
                </Show>
                <Show when={bands().capturedCents > 0}>
                  <div
                    class="split__part split__part--captured"
                    style={{ flex: bands().capturedCents }}
                  >
                    <Show when={bands().showCaptured}>{formatMoney(bands().capturedCents)}</Show>
                  </div>
                </Show>
              </div>

              {/* The bar is decorative; this list is what a screen reader gets. */}
              <ul class="legend">
                <li class="legend__item">
                  <span
                    class="legend__swatch"
                    style={{ background: 'var(--color-accent)' }}
                    aria-hidden="true"
                  />
                  Use soon {formatMoney(bands().soonCents)}
                </li>
                <li class="legend__item">
                  <span
                    class="legend__swatch"
                    style={{ background: 'var(--color-accent-800)' }}
                    aria-hidden="true"
                  />
                  Available {formatMoney(bands().availableCents)}
                </li>
                <li class="legend__item">
                  <span
                    class="legend__swatch"
                    style={{ background: 'var(--color-neutral-800)' }}
                    aria-hidden="true"
                  />
                  Captured {formatMoney(bands().capturedCents)}
                </li>
              </ul>
            </Show>
          </section>

          <Show when={soon().length > 0}>
            <section class="section today__soon">
              <div
                class="row row--baseline row--between"
                style={{ 'margin-bottom': 'var(--space-4)' }}
              >
                <h2 class="section-title">
                  <Show when={reset()} fallback="Use soon">
                    {(on) => `Use soon — resets ${formatResetDate(on())}`}
                  </Show>
                </h2>
                <Show when={daysToReset() !== null}>
                  <span class="today__countdown numeric">
                    {daysToReset() === 0 ? 'today' : `${daysToReset()} days`}
                  </span>
                </Show>
              </div>
              <div class="list">
                {/* Index, not For: instances are rebuilt on every change, and For
                    would rebuild the rows and drop keyboard focus with them. */}
                <Index each={soon()}>
                  {(instance) => (
                    <CreditRow
                      instance={instance()}
                      showCard={app.data.cards.length > 1}
                      onOpen={() => ui.openCredit(instance().benefit.id)}
                      onLogAll={() => actions.logAll(instance())}
                      onToggleMute={() => actions.toggleMute(instance())}
                    />
                  )}
                </Index>
              </div>
            </section>
          </Show>

          <Show when={overlaps().length > 0}>
            <section class="section today__overlaps-section">
              <h2 class="section-title">Two cards, one benefit</h2>
              <p class="section-note" style={{ margin: 'var(--space-2) 0 var(--space-4)' }}>
                These credits exist twice in the household, and one purchase cannot draw on both.
                <Show when={allOverlaps().length > overlaps().length}>
                  {' '}
                  Showing the {overlaps().length} largest of {allOverlaps().length}; the rest are on
                  Credits.
                </Show>
              </p>
              <div class="stack today__overlaps">
                <For each={overlaps()}>
                  {(overlap) => (
                    <button
                      type="button"
                      class="feature today__overlap"
                      onClick={() => ui.openOverlap(overlap.label)}
                    >
                      <span class="row" style={{ gap: 'var(--space-2)' }}>
                        <Ph name="arrows-split" size={14} color="var(--color-accent-400)" />
                        <span class="kicker" style={{ color: 'var(--color-accent-400)' }}>
                          {overlap.sameProduct ? 'Same card, twice' : 'Same spend, two cards'}
                        </span>
                      </span>
                      <span class="today__overlap-title">
                        {overlap.label} &times; {overlap.instances.length}
                      </span>
                      <span class="today__overlap-body">
                        {formatMoney(overlap.remainingCents)} unclaimed across{' '}
                        {overlap.instances
                          .map((i) => i.card.holder || cardLabel(i.card))
                          .join(' and ')}
                        .
                      </span>
                      <span class="today__overlap-cta">
                        Compare
                        <Ph name="arrow-right" size={12} />
                      </span>
                    </button>
                  )}
                </For>
              </div>
            </section>
          </Show>

          <Show when={locked().length > 0}>
            <section class="section today__locked">
              <h2 class="section-title">Locked behind enrolment</h2>
              <p class="section-note" style={{ margin: 'var(--space-2) 0 var(--space-4)' }}>
                {formatMoney(totals().lockedCents)} you cannot touch until you tick a box on the
                issuer&rsquo;s benefits page.
              </p>
              <div class="list">
                <Index each={locked()}>
                  {(instance) => (
                    <CreditRow
                      instance={instance()}
                      showCard={app.data.cards.length > 1}
                      onOpen={() => ui.openCredit(instance().benefit.id)}
                      onLogAll={() => actions.logAll(instance())}
                      onToggleMute={() => actions.toggleMute(instance())}
                    />
                  )}
                </Index>
              </div>
            </section>
          </Show>

          <Show when={captured().length > 0}>
            <section class="section today__captured">
              <h2 class="section-title">
                Captured this period &mdash; {formatMoney(totals().capturedCents)}
              </h2>
              <div class="list" style={{ 'margin-top': 'var(--space-4)' }}>
                <Index each={captured()}>
                  {(instance) => (
                    <CreditRow
                      instance={instance()}
                      showCard={app.data.cards.length > 1}
                      onOpen={() => ui.openCredit(instance().benefit.id)}
                      onLogAll={() => actions.logAll(instance())}
                      onToggleMute={() => actions.toggleMute(instance())}
                    />
                  )}
                </Index>
              </div>
            </section>
          </Show>
        </div>
      </Show>
    </div>
  )
}

/** The first-run screen: one thing to do, and the reason to do it. */
function FirstRun() {
  return (
    <div class="empty">
      <span class="empty__glyph">
        <Ph name="cards-three" />
      </span>
      <h2 class="section-title">Start with one card</h2>
      <p class="section-note">
        Pick it from the catalogue and its credits arrive pre-filled — monthly, quarterly and annual
        windows, and which ones are stuck behind an enrolment box. HelpMe Reward then warns you
        before each window shuts, and shows what the card is really worth against its fee.
      </p>
      <a class="btn btn--primary" href="/cards/new">
        <Ph name="plus" size={14} />
        Add your first card
      </a>
    </div>
  )
}
