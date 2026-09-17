import { render } from '@solidjs/testing-library'
import { beforeEach, describe, expect, it } from 'vitest'
import { CARD_TEMPLATES, findTemplate } from '../src/domain/catalog.ts'
import { AppProvider, type AppStore, useApp } from '../src/stores/app.tsx'

/**
 * Store tests.
 *
 * These drive the real provider rather than a stub, so the reactive wiring —
 * memos recomputing after a mutation — is covered along with the mutations.
 */
function mountStore(): AppStore {
  let store: AppStore | undefined
  function Probe() {
    store = useApp()
    return null
  }
  render(() => (
    <AppProvider>
      <Probe />
    </AppProvider>
  ))
  if (!store) throw new Error('store did not mount')
  return store
}

function addPlatinum(store: AppStore, holder: string) {
  const template = findTemplate('amex-platinum')
  if (!template) throw new Error('missing template')
  return store.addCardFromTemplate(template, { holder, anniversaryOn: '2021-03-14' })
}

describe('adding a card', () => {
  it('brings its catalogue credits with it', () => {
    const store = mountStore()
    const card = addPlatinum(store, 'Jim')
    const template = findTemplate('amex-platinum')

    expect(store.data.cards).toHaveLength(1)
    expect(store.data.benefits).toHaveLength(template?.benefits.length ?? 0)
    expect(store.data.benefits.every((b) => b.cardId === card.id)).toBe(true)
  })

  it('records who holds it, so two of the same card stay apart', () => {
    const store = mountStore()
    addPlatinum(store, 'Jim')
    addPlatinum(store, 'Kathy')

    expect(store.data.cards.map((c) => c.holder)).toEqual(['Jim', 'Kathy'])
    expect(new Set(store.data.cards.map((c) => c.id)).size).toBe(2)
  })

  it('carries the enrolment flags through from the template', () => {
    const store = mountStore()
    addPlatinum(store, 'Jim')
    const locked = store.data.benefits.filter((b) => b.enrollmentRequired)

    expect(locked.length).toBeGreaterThan(0)
    expect(locked.every((b) => b.enrolledAt === undefined)).toBe(true)
  })
})

describe('claiming', () => {
  let store: AppStore

  beforeEach(() => {
    store = mountStore()
    addPlatinum(store, 'Jim')
  })

  it('defaults to the balance left, not the face value', () => {
    const instance = store.instances().find((i) => i.benefit.cadence === 'monthly')
    if (!instance) throw new Error('no monthly credit')

    store.claim(instance, 500)
    const afterFirst = store.instances().find((i) => i.benefit.id === instance.benefit.id)
    if (!afterFirst) throw new Error('credit vanished')
    expect(afterFirst.remainingCents).toBe(instance.benefit.valueCents - 500)

    // A second claim with no amount must take the remainder, never the whole
    // face value again — otherwise the total would overshoot.
    store.claim(afterFirst)
    const afterSecond = store.instances().find((i) => i.benefit.id === instance.benefit.id)
    expect(afterSecond?.remainingCents).toBe(0)
    expect(afterSecond?.claimedCents).toBe(instance.benefit.valueCents)
    expect(afterSecond?.status).toBe('captured')
  })

  it('undoes the whole cycle when unclaimed', () => {
    const instance = store.instances().find((i) => i.benefit.cadence === 'monthly')
    if (!instance) throw new Error('no monthly credit')

    store.claim(instance, 300)
    store.claim(instance, 200)
    expect(store.data.claims).toHaveLength(2)

    store.unclaim(instance.benefit.id, instance.cycle.key)
    expect(store.data.claims).toHaveLength(0)
    expect(store.instances().find((i) => i.benefit.id === instance.benefit.id)?.status).toBe(
      'use_soon',
    )
  })
})

describe('enrolment', () => {
  it('unlocks a credit and can be taken back', () => {
    const store = mountStore()
    addPlatinum(store, 'Jim')
    const locked = store.instances().find((i) => i.status === 'locked')
    if (!locked) throw new Error('expected a locked credit')

    store.confirmEnrollment(locked.benefit.id)
    expect(store.instances().find((i) => i.benefit.id === locked.benefit.id)?.status).not.toBe(
      'locked',
    )

    store.revokeEnrollment(locked.benefit.id)
    expect(store.instances().find((i) => i.benefit.id === locked.benefit.id)?.status).toBe('locked')
  })
})

describe('muting', () => {
  it('silences a credit without changing where it stands', () => {
    const store = mountStore()
    addPlatinum(store, 'Jim')
    const instance = store.instances()[0]
    if (!instance) throw new Error('no credits')

    store.toggleBenefitMute(instance.benefit.id)
    const after = store.instances().find((i) => i.benefit.id === instance.benefit.id)
    expect(after?.muted).toBe(true)
    expect(after?.status).toBe(instance.status)
  })

  it('muting a card silences every credit on it', () => {
    const store = mountStore()
    const card = addPlatinum(store, 'Jim')

    store.toggleCardMute(card.id)
    expect(store.instances().every((i) => i.muted)).toBe(true)
  })
})

describe('deleting', () => {
  it('removes a card along with its credits and their claims', () => {
    const store = mountStore()
    const jim = addPlatinum(store, 'Jim')
    addPlatinum(store, 'Kathy')

    const jimsCredit = store.instances().find((i) => i.card.id === jim.id)
    if (!jimsCredit) throw new Error('no credit')
    store.claim(jimsCredit, 100)

    store.deleteCard(jim.id)
    expect(store.data.cards).toHaveLength(1)
    expect(store.data.benefits.every((b) => b.cardId !== jim.id)).toBe(true)
    expect(store.data.claims).toHaveLength(0)
  })

  it('leaves the other holder untouched', () => {
    const store = mountStore()
    const jim = addPlatinum(store, 'Jim')
    addPlatinum(store, 'Kathy')
    const before = store.data.benefits.filter((b) => b.cardId !== jim.id).length

    store.deleteCard(jim.id)
    expect(store.data.benefits).toHaveLength(before)
    expect(store.data.cards[0]?.holder).toBe('Kathy')
  })
})

describe('import and export', () => {
  it('round-trips the whole dataset', () => {
    const store = mountStore()
    addPlatinum(store, 'Jim')
    const exported = store.exportJson()

    store.deleteCard(store.data.cards[0]?.id ?? '')
    expect(store.data.cards).toHaveLength(0)

    store.importJson(exported)
    expect(store.data.cards).toHaveLength(1)
    expect(store.data.benefits.length).toBe(findTemplate('amex-platinum')?.benefits.length)
  })

  it('refuses a file that is not an export', () => {
    const store = mountStore()
    expect(() => store.importJson('{"hello":"world"}')).toThrow(/HelpMe Reward export/)
  })
})

describe('the catalogue', () => {
  it('gives every template an icon and a cadence for each credit', () => {
    for (const template of CARD_TEMPLATES) {
      for (const benefit of template.benefits) {
        expect(benefit.icon, `${template.id}/${benefit.name}`).toBeTruthy()
        expect(benefit.valueCents, `${template.id}/${benefit.name}`).toBeGreaterThan(0)
      }
    }
  })
})
