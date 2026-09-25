import { Show } from 'solid-js'
import { cadenceLabel } from '../domain/cycles.ts'
import { formatDaysRemaining, formatMoney } from '../domain/format.ts'
import { cardLabel, statusLabel } from '../domain/selectors.ts'
import type { BenefitInstance } from '../domain/types.ts'
import { Ph } from './Ph.tsx'
import { SwipeRow } from './SwipeRow.tsx'

/**
 * One credit in a list.
 *
 * Every row is reachable three ways: tap to open the detail sheet, swipe right
 * to log the whole credit, swipe left to silence it. The swipe is an
 * accelerator — the sheet carries the same two actions — because a gesture
 * nobody discovers is not a feature.
 */

interface CreditRowProps {
  instance: BenefitInstance
  onOpen: () => void
  onLogAll: () => void
  onToggleMute: () => void
  /** Shows the card and holder in the subtitle. Off inside a per-card group. */
  showCard?: boolean
}

function subtitle(instance: BenefitInstance, showCard: boolean): string {
  const parts = [cadenceLabel(instance.benefit.cadence), instance.cycle.label]
  if (showCard) {
    // The holder, not the full card name: two identical Platinums differ only
    // by who holds them, and "American Express Plat…" truncates away the one
    // word that tells them apart.
    parts.push(instance.card.holder || cardLabel(instance.card))
  }
  return parts.join(' · ')
}

export function CreditRow(props: CreditRowProps) {
  const status = () => props.instance.status
  const claimable = () => status() === 'use_soon' || status() === 'available'

  const deadline = () => {
    const days = props.instance.daysRemaining
    if (status() === 'manual') return 'No deadline'
    if (status() === 'captured') return 'Captured'
    // A rolling credit's clock starts only when it is claimed.
    if (props.instance.benefit.cadence === 'rolling') return 'Eligible now'
    if (days < 0) return 'Expired'
    return formatDaysRemaining(days)
  }

  return (
    <SwipeRow
      // Nothing to log and nothing to silence on a captured or untracked row.
      disabled={!claimable() && status() !== 'locked'}
      {...(claimable()
        ? {
            leading: {
              label: 'Log it',
              icon: 'check-circle',
              tone: 'accent' as const,
              onAct: props.onLogAll,
            },
          }
        : {})}
      trailing={{
        label: props.instance.muted ? 'Unmute' : 'Silence',
        icon: props.instance.muted ? 'bell' : 'bell-slash',
        tone: 'quiet' as const,
        onAct: props.onToggleMute,
      }}
    >
      <div
        class="row-card"
        classList={{
          'row-card--soon': status() === 'use_soon',
          'row-card--locked': status() === 'locked',
          'row-card--captured': status() === 'captured' || status() === 'manual',
          'row-card--missed': status() === 'missed',
          'row-card--muted': props.instance.muted,
        }}
      >
        <button type="button" class="row-card__main" onClick={props.onOpen}>
          <span class="row-card__glyph">
            <Ph name={props.instance.benefit.icon ?? 'sparkle'} />
          </span>

          <span class="row-card__text">
            <span class="row-card__title truncate">{props.instance.benefit.name}</span>
            <span class="row-card__sub">{subtitle(props.instance, props.showCard ?? false)}</span>
          </span>

          <span class="row-card__amounts">
            <span class="row-card__amount numeric">
              {formatMoney(
                status() === 'captured'
                  ? props.instance.claimedCents
                  : props.instance.remainingCents,
              )}
            </span>
            <span class="row-card__of numeric">{deadline()}</span>
          </span>
        </button>

        <button
          type="button"
          class="icon-btn"
          classList={{ 'icon-btn--muted': props.instance.muted }}
          aria-pressed={props.instance.muted}
          // The row's own title is not enough context in a long list, so the
          // credit is named in the label rather than left to the visual order.
          aria-label={`${props.instance.muted ? 'Unsilence' : 'Silence'} reminders for ${
            props.instance.benefit.name
          }`}
          onClick={props.onToggleMute}
        >
          <Ph name={props.instance.muted ? 'bell-slash' : 'bell'} size={15} />
        </button>

        <Show when={status() === 'locked'}>
          <span class="visually-hidden">{statusLabel('locked')}</span>
        </Show>
      </div>
    </SwipeRow>
  )
}
