import { type Accessor, createContext, createSignal, type ParentProps, useContext } from 'solid-js'
import type { Reminder } from '../domain/reminders.ts'

/**
 * Transient UI state: which sheet is open, and whether the nudge preview is up.
 *
 * Kept in a context rather than passed down, because the shell renders the
 * sheets while the screens open them, and the two are on opposite sides of the
 * router's layout boundary.
 *
 * Sheets track a benefit *id*, never a resolved instance: the instance is
 * recomputed on every claim, and holding one would leave the sheet showing a
 * balance that went stale the moment the user logged something.
 */
export interface UiStore {
  openBenefitId: Accessor<string | null>
  openCredit(benefitId: string): void
  closeCredit(): void

  openOverlapLabel: Accessor<string | null>
  openOverlap(label: string): void
  closeOverlap(): void

  nudge: Accessor<Reminder | null>
  showNudge(reminder: Reminder): void
  dismissNudge(): void
}

const UiContext = createContext<UiStore>()

export function UiProvider(props: ParentProps) {
  const [openBenefitId, setOpenBenefitId] = createSignal<string | null>(null)
  const [openOverlapLabel, setOpenOverlapLabel] = createSignal<string | null>(null)
  const [nudge, setNudge] = createSignal<Reminder | null>(null)

  const store: UiStore = {
    openBenefitId,
    openCredit: (benefitId) => setOpenBenefitId(benefitId),
    closeCredit: () => setOpenBenefitId(null),

    openOverlapLabel,
    openOverlap: (label) => setOpenOverlapLabel(label),
    closeOverlap: () => setOpenOverlapLabel(null),

    nudge,
    showNudge: (reminder) => setNudge(reminder),
    dismissNudge: () => setNudge(null),
  }

  return <UiContext.Provider value={store}>{props.children}</UiContext.Provider>
}

export function useUi(): UiStore {
  const store = useContext(UiContext)
  if (!store) throw new Error('useUi must be used inside <UiProvider>')
  return store
}
