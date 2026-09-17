import {
  type Accessor,
  createContext,
  createEffect,
  createMemo,
  createSignal,
  onCleanup,
  type ParentProps,
  useContext,
} from 'solid-js'
import { createStore, produce, reconcile } from 'solid-js/store'
import { benefitsFromTemplate, type CardTemplate } from '../domain/catalog.ts'
import { todayIso } from '../domain/dates.ts'
import {
  type CardSummary,
  currentInstances,
  type MissedCycle,
  missedCycles,
  summarizeCard,
} from '../domain/selectors.ts'
import type {
  AppData,
  Benefit,
  BenefitInstance,
  Card,
  Claim,
  IsoDate,
  NotificationSettings,
  Settings,
} from '../domain/types.ts'
import { emptyData, loadData, migrate, saveData } from '../services/db.ts'

export function newId(): string {
  return crypto.randomUUID()
}

function nowIso(): string {
  return new Date().toISOString()
}

/**
 * The current date, kept fresh.
 *
 * A PWA is resumed rather than reloaded, so a date captured at boot goes stale
 * overnight and would show yesterday's deadlines to someone who left the app
 * open. This re-reads the clock when the tab becomes visible and on a slow
 * interval.
 */
function createToday(): Accessor<IsoDate> {
  const [today, setToday] = createSignal(todayIso())
  const refresh = () => setToday(todayIso())

  const timer = setInterval(refresh, 60_000)
  document.addEventListener('visibilitychange', refresh)
  window.addEventListener('focus', refresh)

  onCleanup(() => {
    clearInterval(timer)
    document.removeEventListener('visibilitychange', refresh)
    window.removeEventListener('focus', refresh)
  })

  return today
}

export interface AppStore {
  data: AppData
  today: Accessor<IsoDate>
  /** True until the persisted snapshot has been read. */
  loading: Accessor<boolean>
  /** Every active credit resolved against today, sorted by urgency. */
  instances: Accessor<BenefitInstance[]>
  /** Windows that closed with money left in them. */
  missed: Accessor<MissedCycle[]>
  /** Per-card totals for the Cards and Value screens. */
  cardSummaries: Accessor<CardSummary[]>
  /** `instances`, narrowed by the household filter in settings. */
  visibleInstances: Accessor<BenefitInstance[]>

  addCardFromTemplate(template: CardTemplate, overrides: Partial<Card> & { holder: string }): Card
  updateCard(id: string, patch: Partial<Card>): void
  toggleCardMute(id: string): void
  archiveCard(id: string): void
  deleteCard(id: string): void

  addBenefit(benefit: Omit<Benefit, 'id' | 'createdAt' | 'updatedAt'>): Benefit
  updateBenefit(id: string, patch: Partial<Benefit>): void
  toggleBenefitMute(id: string): void
  /** Records that the user has ticked the issuer's enrolment box. */
  confirmEnrollment(id: string): void
  revokeEnrollment(id: string): void
  deleteBenefit(id: string): void

  /** Logs a use of a credit. Omit `amountCents` to claim everything left. */
  claim(instance: BenefitInstance, amountCents?: number, note?: string): Claim
  /** Removes every claim recorded against one cycle. */
  unclaim(benefitId: string, cycleKey: IsoDate): void

  updateSettings(patch: Partial<Settings>): void
  updateNotificationSettings(patch: Partial<NotificationSettings>): void

  replaceAll(data: AppData): void
  exportJson(): string
  importJson(json: string): void
}

const AppContext = createContext<AppStore>()

export function AppProvider(props: ParentProps) {
  const [data, setData] = createStore<AppData>(emptyData())
  const [loading, setLoading] = createSignal(true)
  const today = createToday()

  /**
   * Set by any mutation. The UI is gated on `loading()`, so in the app nothing
   * can be written before the snapshot arrives — but a caller that does not
   * wait (a test, or any future programmatic use) would otherwise have its
   * change silently discarded when the read resolves. The user's action wins.
   */
  let hasLocalChanges = false

  const write: typeof setData = ((...args: Parameters<typeof setData>) => {
    hasLocalChanges = true
    return (setData as (...a: Parameters<typeof setData>) => void)(...args)
  }) as typeof setData

  void loadData().then((loaded) => {
    if (!hasLocalChanges) setData(reconcile(loaded))
    setLoading(false)
  })

  createEffect(() => {
    // Read the whole store so the effect tracks every field, then bail out
    // during boot so the empty default never overwrites a real snapshot.
    const snapshot = JSON.parse(JSON.stringify(data)) as AppData
    if (loading()) return
    void saveData(snapshot).catch((error) => console.error('Could not save data', error))
  })

  const instances = createMemo(() => currentInstances(data, today()))
  const missed = createMemo(() => missedCycles(data, today()))
  const cardSummaries = createMemo(() =>
    data.cards
      .filter((card) => !card.archived)
      .map((card) => summarizeCard(card, data, instances(), missed(), today())),
  )
  const visibleInstances = createMemo(() => {
    const holder = data.settings.holderFilter
    return holder ? instances().filter((i) => i.card.holder === holder) : instances()
  })

  const store: AppStore = {
    data,
    today,
    loading,
    instances,
    missed,
    cardSummaries,
    visibleInstances,

    addCardFromTemplate(template, overrides) {
      const now = nowIso()
      const card: Card = {
        id: newId(),
        issuer: template.issuer,
        product: template.product,
        network: template.network,
        annualFeeCents: template.annualFeeCents,
        anniversaryOn: todayIso(),
        muted: false,
        archived: false,
        createdAt: now,
        updatedAt: now,
        ...overrides,
      }
      const benefits = benefitsFromTemplate(template, card.id, now, newId)
      write(
        produce((draft) => {
          draft.cards.push(card)
          draft.benefits.push(...benefits)
        }),
      )
      return card
    },

    updateCard(id, patch) {
      write(
        produce((draft) => {
          const card = draft.cards.find((c) => c.id === id)
          if (card) Object.assign(card, patch, { updatedAt: nowIso() })
        }),
      )
    },

    toggleCardMute(id) {
      const card = data.cards.find((c) => c.id === id)
      if (card) store.updateCard(id, { muted: !card.muted })
    },

    archiveCard(id) {
      store.updateCard(id, { archived: true })
    },

    deleteCard(id) {
      write(
        produce((draft) => {
          const benefitIds = new Set(draft.benefits.filter((b) => b.cardId === id).map((b) => b.id))
          draft.cards = draft.cards.filter((c) => c.id !== id)
          draft.benefits = draft.benefits.filter((b) => b.cardId !== id)
          draft.claims = draft.claims.filter((c) => !benefitIds.has(c.benefitId))
        }),
      )
    },

    addBenefit(input) {
      const now = nowIso()
      const benefit: Benefit = { ...input, id: newId(), createdAt: now, updatedAt: now }
      write(produce((draft) => void draft.benefits.push(benefit)))
      return benefit
    },

    updateBenefit(id, patch) {
      write(
        produce((draft) => {
          const benefit = draft.benefits.find((b) => b.id === id)
          if (benefit) Object.assign(benefit, patch, { updatedAt: nowIso() })
        }),
      )
    },

    toggleBenefitMute(id) {
      const benefit = data.benefits.find((b) => b.id === id)
      if (benefit) store.updateBenefit(id, { muted: !benefit.muted })
    },

    confirmEnrollment(id) {
      store.updateBenefit(id, { enrolledAt: nowIso() })
    },

    revokeEnrollment(id) {
      write(
        produce((draft) => {
          const benefit = draft.benefits.find((b) => b.id === id)
          if (benefit) {
            delete benefit.enrolledAt
            benefit.updatedAt = nowIso()
          }
        }),
      )
    },

    deleteBenefit(id) {
      write(
        produce((draft) => {
          draft.benefits = draft.benefits.filter((b) => b.id !== id)
          draft.claims = draft.claims.filter((c) => c.benefitId !== id)
        }),
      )
    },

    claim(instance, amountCents, note) {
      // Default to what is left rather than the credit's face value, so a
      // second claim against a partly-used credit cannot overshoot.
      const claim: Claim = {
        id: newId(),
        benefitId: instance.benefit.id,
        cycleKey: instance.cycle.key,
        amountCents: amountCents ?? instance.remainingCents,
        claimedAt: nowIso(),
        ...(note ? { note } : {}),
      }
      write(produce((draft) => void draft.claims.push(claim)))
      return claim
    },

    unclaim(benefitId, cycleKey) {
      write(
        produce((draft) => {
          draft.claims = draft.claims.filter(
            (c) => !(c.benefitId === benefitId && c.cycleKey === cycleKey),
          )
        }),
      )
    },

    updateSettings(patch) {
      write(produce((draft) => void Object.assign(draft.settings, patch)))
    },

    updateNotificationSettings(patch) {
      write(produce((draft) => void Object.assign(draft.settings.notifications, patch)))
    },

    replaceAll(next) {
      write(reconcile(migrate(next)))
    },

    exportJson() {
      return JSON.stringify(data, null, 2)
    },

    importJson(json) {
      const parsed = JSON.parse(json) as Partial<AppData>
      if (!parsed || typeof parsed !== 'object' || !Array.isArray(parsed.cards)) {
        throw new Error('That file does not look like a HelpMe Reward export.')
      }
      store.replaceAll(migrate(parsed))
    },
  }

  return <AppContext.Provider value={store}>{props.children}</AppContext.Provider>
}

export function useApp(): AppStore {
  const store = useContext(AppContext)
  if (!store) throw new Error('useApp must be used inside <AppProvider>')
  return store
}
