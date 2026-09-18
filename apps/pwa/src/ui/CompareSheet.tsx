import { For, Show } from 'solid-js'
import { formatDate, formatMoney } from '../domain/format.ts'
import type { OverlapGroup } from '../domain/selectors.ts'
import { cardLabel, statusLabel } from '../domain/selectors.ts'
import { useApp } from '../stores/app.tsx'
import { Ph } from './Ph.tsx'
import { Sheet } from './Sheet.tsx'
import './CompareSheet.css'

/**
 * Side by side, when the household holds the same credit twice.
 *
 * The advice is concrete about the thing people actually get wrong — that one
 * booking draws on one card — and stops short of ranking the two people, which
 * is not the app's business.
 */

interface CompareSheetProps {
  overlap: OverlapGroup | null
  onClose: () => void
  onOpenCredit: (benefitId: string) => void
}

function advice(overlap: OverlapGroup): string {
  const [first, second] = overlap.instances
  if (!first || !second) return ''

  const behind = first.remainingCents >= second.remainingCents ? first : second
  const ahead = behind === first ? second : first

  if (behind.status === 'locked' && ahead.status !== 'locked') {
    return `${behind.card.holder}'s side is still behind an enrolment box, so only ${ahead.card.holder}'s ${formatMoney(
      ahead.remainingCents,
    )} can actually be spent today. Unlock it first — the money is already on the card.`
  }
  if (behind.remainingCents === ahead.remainingCents) {
    return `Both sides are untouched at ${formatMoney(
      behind.remainingCents,
    )} each. They cannot be combined, so this needs two separate purchases — not one larger one.`
  }
  return `${behind.card.holder}'s side is the one at risk: ${formatMoney(
    behind.remainingCents,
  )} against ${ahead.card.holder}'s ${formatMoney(
    ahead.remainingCents,
  )}. One purchase cannot draw on both cards, so clear the larger one first.`
}

export function CompareSheet(props: CompareSheetProps) {
  const app = useApp()

  return (
    <Sheet
      open={props.overlap !== null}
      onClose={props.onClose}
      title={props.overlap?.label ?? 'Compare'}
    >
      <Show when={props.overlap}>
        {(overlap) => (
          <>
            <header class="sheet-head">
              <div class="grow">
                <div class="row" style={{ gap: 'var(--space-2)' }}>
                  <Ph name="arrows-split" size={14} color="var(--color-accent-400)" />
                  <span class="kicker" style={{ color: 'var(--color-accent-400)' }}>
                    {overlap().sameProduct ? 'Same card, held twice' : 'Same spend, two cards'}
                  </span>
                </div>
                <h2 class="sheet-head__title">{overlap().label}</h2>
                <p class="muted" style={{ 'font-size': 'var(--type-note)' }}>
                  {formatMoney(overlap().remainingCents)} unclaimed across{' '}
                  {overlap().instances.length} cards
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

            <div class="compare">
              <For each={overlap().instances}>
                {(instance) => (
                  <button
                    type="button"
                    class="compare__side"
                    classList={{ 'compare__side--locked': instance.status === 'locked' }}
                    onClick={() => props.onOpenCredit(instance.benefit.id)}
                  >
                    <span class="kicker kicker--quiet">
                      {instance.card.holder || cardLabel(instance.card)}
                    </span>
                    <span class="compare__amount numeric">
                      {formatMoney(instance.remainingCents)}
                    </span>
                    <span class="compare__of numeric">
                      of {formatMoney(instance.benefit.valueCents)}
                    </span>
                    <span class="bar" style={{ margin: 'var(--space-3) 0' }}>
                      <span
                        class="bar__fill"
                        style={{
                          width: `${
                            (instance.claimedCents / Math.max(1, instance.benefit.valueCents)) * 100
                          }%`,
                        }}
                      />
                    </span>
                    <span class="tag" classList={{ 'tag--locked': instance.status === 'locked' }}>
                      {statusLabel(instance.status)}
                    </span>
                    <span class="compare__note">
                      <Show
                        when={instance.daysRemaining >= 0}
                        fallback={`Closed ${formatDate(instance.cycle.end)}`}
                      >
                        Closes {formatDate(instance.cycle.end)}
                      </Show>
                    </span>
                  </button>
                )}
              </For>
            </div>

            <div class="feature" style={{ margin: 'var(--space-6) 0' }}>
              <span class="kicker" style={{ color: 'var(--color-accent-400)' }}>
                What to do
              </span>
              <p class="compare__advice">{advice(overlap())}</p>
            </div>

            <div class="stack stack--tight">
              <For each={overlap().instances}>
                {(instance) => (
                  <Show when={instance.status !== 'locked'}>
                    <button
                      type="button"
                      class="btn btn--block"
                      onClick={() => {
                        app.claim(instance)
                        props.onClose()
                      }}
                    >
                      <Ph name="check-circle" size={14} />
                      Log {formatMoney(instance.remainingCents)} on {instance.card.holder}
                      &rsquo;s card
                    </button>
                  </Show>
                )}
              </For>
            </div>
          </>
        )}
      </Show>
    </Sheet>
  )
}
