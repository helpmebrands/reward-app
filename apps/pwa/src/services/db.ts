import { createStore, del, get, set } from 'idb-keyval'
import type { AppData, Settings } from '../domain/types.ts'

/**
 * Persistence.
 *
 * The whole dataset is a single IndexedDB record. A user's cards, benefits and
 * claims are measured in kilobytes, so snapshot writes are cheaper than
 * maintaining per-entity stores — and the service worker can read the same
 * record without a schema to agree on.
 */

export const DB_NAME = 'cardvantage'
export const STORE_NAME = 'state'
export const DATA_KEY = 'app-data'
/** Reminder schedule, written by the app and read by the service worker. */
export const SCHEDULE_KEY = 'reminder-schedule'

/** Bump when a migration is needed; see {@link migrate}. */
export const DATA_VERSION = 1

const store = createStore(DB_NAME, STORE_NAME)

export const DEFAULT_SETTINGS: Settings = {
  notifications: {
    enabled: false,
    // 9am local: early enough to act on the day, late enough not to wake
    // anyone. Timing per credit comes from the ladder, not from here.
    timeOfDay: '09:00',
    minValueCents: 100,
    annualFeeReminder: true,
    enrollmentReminder: true,
  },
  useSoonDays: 30,
  theme: 'system',
  holderFilter: '',
}

export function emptyData(): AppData {
  return {
    version: DATA_VERSION,
    cards: [],
    benefits: [],
    claims: [],
    settings: DEFAULT_SETTINGS,
  }
}

/**
 * Brings a persisted snapshot up to the current shape. Fields added after
 * release must be defaulted here rather than assumed present.
 */
export function migrate(raw: Partial<AppData> | undefined): AppData {
  if (!raw) return emptyData()
  const base = emptyData()
  return {
    version: DATA_VERSION,
    cards: raw.cards ?? base.cards,
    benefits: raw.benefits ?? base.benefits,
    claims: raw.claims ?? base.claims,
    settings: {
      ...base.settings,
      ...raw.settings,
      notifications: { ...base.settings.notifications, ...raw.settings?.notifications },
    },
  }
}

export async function loadData(): Promise<AppData> {
  try {
    return migrate(await get<AppData>(DATA_KEY, store))
  } catch (error) {
    // A corrupt or blocked IndexedDB must not brick the app; starting empty is
    // recoverable, a white screen is not.
    console.error('Could not read saved data, starting empty', error)
    return emptyData()
  }
}

export async function saveData(data: AppData): Promise<void> {
  await set(DATA_KEY, data, store)
}

export async function clearData(): Promise<void> {
  await del(DATA_KEY, store)
}
