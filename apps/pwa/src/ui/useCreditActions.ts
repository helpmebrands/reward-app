import { formatMoney } from '../domain/format.ts'
import type { BenefitInstance } from '../domain/types.ts'
import { useApp } from '../stores/app.tsx'
import { useSnackbar } from './Snackbar.tsx'

/**
 * The actions a credit row offers, with their feedback attached.
 *
 * Every list that renders a row shares this so a swipe behaves identically to
 * the same action taken from the detail sheet. It also guarantees the part that
 * matters: a swipe is easy to trigger by accident, so logging one always
 * returns an undo rather than silently altering a balance.
 */
export function useCreditActions() {
  const app = useApp()
  const snackbar = useSnackbar()

  return {
    /** Logs the whole remaining balance, with an undo. */
    logAll(instance: BenefitInstance) {
      const claim = app.claim(instance)
      snackbar.show(`Logged ${formatMoney(claim.amountCents)} on ${instance.benefit.name}.`, {
        label: 'Undo',
        ariaLabel: `Undo logging ${instance.benefit.name}`,
        onAct: () => app.removeClaim(claim.id),
      })
    },

    /** Silences or unsilences one credit, with an undo. */
    toggleMute(instance: BenefitInstance) {
      const wasMuted = instance.benefit.muted
      app.toggleBenefitMute(instance.benefit.id)
      snackbar.show(
        wasMuted
          ? `Reminders back on for ${instance.benefit.name}.`
          : `Silenced ${instance.benefit.name}. It is still tracked.`,
        {
          label: 'Undo',
          ariaLabel: wasMuted
            ? `Undo reminders back on for ${instance.benefit.name}`
            : `Undo silencing ${instance.benefit.name}`,
          onAct: () => app.toggleBenefitMute(instance.benefit.id),
        },
      )
    },
  }
}
