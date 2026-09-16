import { createMemo, For, Show } from 'solid-js'
import { cadenceLabel } from '../domain/cycles.ts'
import {
  formatDate,
  formatDaysRemaining,
  formatMoney,
  parseMoneyToCents,
} from '../domain/format.ts'
import { currentRung, ladderFor } from '../domain/ladder.ts'
import { cardLabel, statusLabel } from '../domain/selectors.ts'
import type { BenefitInstance } from '../domain/types.ts'
import { useApp } from '../stores/app.tsx'
import { Ph } from './Ph.tsx'
import { Sheet } from './Sheet.tsx'
import { useSnackbar } from './Snackbar.tsx'
import { Switch } from './Switch.tsx'
import './CreditSheet.css'

/**
 * The credit detail sheet.
 *
 * Its job is to make logging a *partial* amount as easy as logging the whole
 * thing. Most of these credits are spent in pieces — $40 of a $100 dining
 * credit — and an app that only offers a tick mark quietly trains people to lie
 * to it, after which every number it shows is wrong.
 */

interface CreditSheetProps {
  instance: BenefitInstance | null
  onClose: () => void
}

export function CreditSheet(props: CreditSheetProps) {
  const app = useApp()
  const snackbar = useSnackbar()

  const instance = () => props.instance
  const benefit = () => instance()?.benefit
  const status = () => instance()?.status

  /**
   * Quick amounts: a quarter, a half, and a round figure, all capped at what is
   * actually left. Rounded to whole dollars because nobody logs $37.53.
   */
  const quickAmounts = createMemo(() => {
    const remaining = instance()?.remainingCents ?? 0
    if (remaining < 500) return []
    const candidates = [
      Math.round(remaining / 4 / 100) * 100,
      Math.round(remaining / 2 / 100) * 100,
    ].filter((cents) => cents >= 100 && cents < remaining)
    return [...new Set(candidates)]
  })

  function log(amountCents?: number) {
    const current = instance()
    if (!current) return
    const claim = app.claim(current, amountCents)
    snackbar.show(`Logged ${formatMoney(claim.amountCents)} on ${current.benefit.name}.`, {
      label: 'Undo',
      onAct: () => app.unclaim(claim.benefitId, claim.cycleKey),
    })
    props.onClose()
  }

  function logCustom() {
    const current = instance()
    if (!current) return
    const entered = window.prompt(
      `How much of ${current.benefit.name} did you use?`,
      (current.remainingCents / 100).toFixed(2),
    )
    if (entered === null) return
    const cents = parseMoneyToCents(entered)
    if (cents === null || cents === 0) {
      snackbar.show('That did not look like an amount.')
      return
    }
    // Never let a claim exceed what the cycle actually holds.
    log(Math.min(cents, current.remainingCents))
  }

  function undoAll() {
    const current = instance()
    if (!current) return
    app.unclaim(current.benefit.id, current.cycle.key)
    snackbar.show(`Cleared what was logged against ${current.benefit.name}.`)
  }

  return (
    <Sheet open={instance() !== null} onClose={props.onClose} title={benefit()?.name ?? 'Credit'}>
      <Show when={instance()}>
        {(current) => (
          <>
            <header class="sheet-head">
              <div class="grow">
                <div class="row" style={{ gap: 'var(--space-2)' }}>
                  <Ph
                    name={current().benefit.icon ?? 'sparkle'}
                    size={14}
                    color="var(--color-accent-400)"
                  />
                  <span class="kicker" style={{ color: 'var(--color-accent-400)' }}>
                    {cardLabel(current().card)}
                  </span>
                </div>
                <h2 class="sheet-head__title">{current().benefit.name}</h2>
                <p class="muted" style={{ 'font-size': '11.5px' }}>
                  {cadenceLabel(current().benefit.cadence)} &middot; {current().cycle.label}
                  <Show when={current().benefit.cadence !== 'manual'}>
                    {' '}
                    &middot; {formatDate(current().cycle.start)} &ndash;{' '}
                    {formatDate(current().cycle.end)}
                  </Show>
                </p>
              </div>
              <button
                type="button"
                class="icon-btn icon-btn--boxed"
                aria-label="Close"
                onClick={props.onClose}
              >
                <Ph name="x" size={14} />
              </button>
            </header>

            <section class="sheet-meter">
              <div class="row row--baseline row--between">
                <span class="sheet-meter__amount numeric">
                  {formatMoney(current().remainingCents)}
                </span>
                <span class="muted" style={{ 'font-size': '11px' }}>
                  left of {formatMoney(current().benefit.valueCents)}
                </span>
              </div>
              <div
                class="bar"
                style={{ margin: 'var(--space-4) 0' }}
                role="progressbar"
                aria-valuemin={0}
                aria-valuemax={current().benefit.valueCents}
                aria-valuenow={current().claimedCents}
                aria-label="Claimed so far"
              >
                <div
                  class="bar__fill"
                  style={{
                    width: `${(current().claimedCents / Math.max(1, current().benefit.valueCents)) * 100}%`,
                  }}
                />
              </div>
              <div class="row" style={{ gap: 'var(--space-2)' }}>
                <Ph name="clock-countdown" size={13} color="var(--color-accent-300)" />
                <span style={{ 'font-size': '11.5px', color: 'var(--color-accent-300)' }}>
                  <Show
                    when={current().benefit.cadence !== 'manual'}
                    fallback="Tracked by hand — no deadline"
                  >
                    {current().daysRemaining < 0
                      ? `Expired ${formatDate(current().cycle.end)}`
                      : `${formatDaysRemaining(current().daysRemaining)} — closes ${formatDate(
                          current().cycle.end,
                        )}`}
                  </Show>
                </span>
              </div>
            </section>

            <Show when={status() === 'locked'}>
              <section class="sheet-locked">
                <div class="row" style={{ 'align-items': 'flex-start', gap: 'var(--space-3)' }}>
                  <Ph name="lock-simple" size={15} color="var(--tone-locked-fg)" />
                  <p class="sheet-locked__note">
                    {current().benefit.enrollmentNote ??
                      `Not enrolled. ${formatMoney(
                        current().benefit.valueCents,
                      )} is unreachable until you tick the box on the issuer's benefits page.`}
                  </p>
                </div>
                <div class="stack stack--tight" style={{ 'margin-top': 'var(--space-4)' }}>
                  <Show when={current().benefit.enrollmentUrl}>
                    {(url) => (
                      <a
                        class="btn btn--primary btn--block"
                        href={url()}
                        target="_blank"
                        rel="noreferrer noopener"
                      >
                        <Ph name="arrow-square-out" size={14} />
                        Open the benefits page
                      </a>
                    )}
                  </Show>
                  <button
                    type="button"
                    class="btn btn--block"
                    onClick={() => {
                      app.confirmEnrollment(current().benefit.id)
                      snackbar.show(`${current().benefit.name} unlocked.`, {
                        label: 'Undo',
                        onAct: () => app.revokeEnrollment(current().benefit.id),
                      })
                    }}
                  >
                    I&rsquo;ve enrolled &mdash; unlock this credit
                  </button>
                </div>
              </section>
            </Show>

            <Show when={status() === 'use_soon' || status() === 'available'}>
              <section class="sheet-section">
                <h3 class="sheet-section__title">Log what you spent</h3>
                <p class="section-note">Partial use is normal — log the dollars, not a tick.</p>
                <div class="sheet-quick">
                  <For each={quickAmounts()}>
                    {(cents) => (
                      <button type="button" class="btn" onClick={() => log(cents)}>
                        {formatMoney(cents)}
                      </button>
                    )}
                  </For>
                  <button type="button" class="btn" onClick={logCustom}>
                    Other&hellip;
                  </button>
                </div>
                <button
                  type="button"
                  class="btn btn--primary btn--block"
                  style={{ 'margin-top': 'var(--space-3)' }}
                  onClick={() => log()}
                >
                  Mark the full {formatMoney(current().remainingCents)} used
                </button>
              </section>
            </Show>

            <Show when={status() === 'captured'}>
              <section class="sheet-done">
                <Ph name="check-circle" fill size={19} color="var(--color-accent)" />
                <p class="grow" style={{ 'font-size': '11.5px', 'line-height': 1.5 }}>
                  Fully captured. Reminders stay off until it resets.
                </p>
                <button type="button" class="btn btn--small" onClick={undoAll}>
                  Undo
                </button>
              </section>
            </Show>

            <Show when={status() === 'missed'}>
              <section class="sheet-missed">
                <Ph name="hourglass-low" size={17} color="var(--tone-missed-fg)" />
                <p class="grow" style={{ 'font-size': '11.5px', 'line-height': 1.5 }}>
                  This window closed on {formatDate(current().cycle.end)} with{' '}
                  {formatMoney(current().remainingCents)} unused. It does not roll over.
                </p>
              </section>
            </Show>

            <Show when={current().benefit.redemptionSteps.length > 0}>
              <section class="sheet-section">
                <h3 class="sheet-section__title">How to redeem</h3>
                <ol class="sheet-steps">
                  <For each={current().benefit.redemptionSteps}>
                    {(step, index) => (
                      <li class="sheet-steps__item">
                        <span class="sheet-steps__n numeric">{index() + 1}</span>
                        <span class="sheet-steps__text">{step}</span>
                      </li>
                    )}
                  </For>
                </ol>
              </section>
            </Show>

            <Show when={current().benefit.notes}>
              {(note) => (
                <section class="sheet-section">
                  <div class="panel row" style={{ 'align-items': 'flex-start' }}>
                    <Ph name="info" size={14} color="var(--color-neutral-500)" />
                    <p class="grow section-note">{note()}</p>
                  </div>
                </section>
              )}
            </Show>

            <section class="sheet-section">
              <h3 class="sheet-section__title">Reminder ladder</h3>
              <p class="section-note">
                {current().benefit.lastCallOnly
                  ? 'One alert only, on the last call.'
                  : `${cadenceLabel(current().benefit.cadence)} credits get ${
                      ladderFor(current().benefit).length
                    } nudges, easing from a heads-up to a last call.`}
              </p>
              <ul class="sheet-ladder">
                <For each={ladderFor(current().benefit)}>
                  {(rung) => {
                    const reached = () =>
                      currentRung(current().benefit, current().daysRemaining) === rung
                    return (
                      <li class="sheet-ladder__rung" classList={{ 'is-now': reached() }}>
                        <Ph
                          name={
                            rung.tone === 'urgent'
                              ? 'warning'
                              : rung.tone === 'notice'
                                ? 'bell'
                                : 'hand-waving'
                          }
                          fill={rung.tone === 'urgent'}
                          size={13}
                        />
                        <span class="grow">
                          {rung.daysBefore === 0
                            ? 'On the last day'
                            : `${rung.daysBefore} days out`}
                        </span>
                        <span class="sheet-ladder__label">{rung.label}</span>
                      </li>
                    )
                  }}
                </For>
              </ul>

              <div class="panel row row--between" style={{ 'margin-top': 'var(--space-3)' }}>
                <span class="grow">
                  <span style={{ display: 'block', 'font-size': '12px' }}>Last call only</span>
                  <span class="section-note">
                    Skip the earlier rungs and warn once, at the end.
                  </span>
                </span>
                <Switch
                  label={`Last call only for ${current().benefit.name}`}
                  checked={current().benefit.lastCallOnly}
                  onChange={(next) =>
                    app.updateBenefit(current().benefit.id, { lastCallOnly: next })
                  }
                />
              </div>

              <div class="panel row row--between" style={{ 'margin-top': 'var(--space-2)' }}>
                <span class="grow">
                  <span style={{ display: 'block', 'font-size': '12px' }}>Silence this credit</span>
                  <span class="section-note">
                    Keeps tracking it, sends nothing. Status stays{' '}
                    {statusLabel(status() ?? 'available').toLowerCase()}.
                  </span>
                </span>
                <Switch
                  label={`Silence reminders for ${current().benefit.name}`}
                  checked={current().benefit.muted}
                  onChange={() => app.toggleBenefitMute(current().benefit.id)}
                />
              </div>
            </section>

            <a class="sheet-edit" href={`/benefit/${current().benefit.id}`}>
              <Ph name="pencil-simple" size={14} />
              Edit this credit
            </a>
          </>
        )}
      </Show>
    </Sheet>
  )
}
