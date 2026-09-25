import { describe, expect, it } from 'vitest'
import type { AppData, Card } from '../src/domain/types.ts'
import { DATA_VERSION, emptyData, migrate } from '../src/services/db.ts'
import { makeCard } from './factories.ts'

/**
 * The snapshot migration. A field added after release is defaulted here so
 * an older record loads rather than rendering with holes.
 */
describe('migrate', () => {
  // @lat: [[pwa-tests#The store#An older snapshot gains a card kind]]
  it('gives a card saved before kinds existed the personal kind', () => {
    const { kind: _dropped, ...legacy } = makeCard()
    const raw = { version: 1, cards: [legacy as Card], benefits: [], claims: [] }
    const data = migrate(raw as Partial<AppData>)
    expect(data.version).toBe(DATA_VERSION)
    expect(DATA_VERSION).toBe(2)
    expect(data.cards[0]?.kind).toBe('personal')
    expect(emptyData().version).toBe(2)
  })

  it('leaves a business card business', () => {
    const data = migrate({ version: 2, cards: [makeCard({ kind: 'business' })] })
    expect(data.cards[0]?.kind).toBe('business')
  })
})
