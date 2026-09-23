import { describe, expect, it } from 'vitest'
import { benefitsFromTemplate, type CardTemplate } from '../src/domain/catalog.ts'

const template: CardTemplate = {
  id: 't',
  issuer: 'Issuer',
  product: 'Product',
  network: 'visa',
  annualFeeCents: 0,
  benefits: [
    {
      name: 'Ended',
      category: 'other',
      icon: 'x',
      valueCents: 1000,
      cadence: 'monthly',
      anchor: 'calendar',
      endsOn: '2026-06-30',
    },
    {
      name: 'Ending',
      category: 'other',
      icon: 'x',
      valueCents: 1000,
      cadence: 'monthly',
      anchor: 'calendar',
      endsOn: '2026-12-31',
    },
    {
      name: 'Open',
      category: 'other',
      icon: 'x',
      valueCents: 1000,
      cadence: 'monthly',
      anchor: 'calendar',
    },
  ],
}

describe('benefitsFromTemplate', () => {
  // @lat: [[tests#Card catalogue#A template credit that has already ended lands inactive]]
  it('copies the end date and lands an already-ended credit inactive', () => {
    const benefits = benefitsFromTemplate(template, 'card-9', '2026-09-16T00:00:00.000Z', () => 'id')
    expect(benefits.map((b) => [b.endsOn, b.active])).toEqual([
      ['2026-06-30', false],
      ['2026-12-31', true],
      [undefined, true],
    ])
  })
})
