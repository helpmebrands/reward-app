import { describe, expect, it } from 'vitest'
import {
  benefitsFromTemplate,
  type CardTemplate,
  templateAnnualValueCents,
} from '../src/domain/catalog.ts'

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
    const benefits = benefitsFromTemplate(
      template,
      'card-9',
      '2026-09-16T00:00:00.000Z',
      () => 'id',
    )
    expect(benefits.map((b) => [b.endsOn, b.active])).toEqual([
      ['2026-06-30', false],
      ['2026-12-31', true],
      [undefined, true],
    ])
  })
})

describe('a rolling template credit', () => {
  const rolling: CardTemplate = {
    ...template,
    benefits: [
      {
        name: 'Global Entry',
        category: 'travel',
        icon: 'x',
        valueCents: 12_000,
        cadence: 'rolling',
        anchor: 'anniversary',
        intervalMonths: 48,
      },
      {
        name: 'Open',
        category: 'other',
        icon: 'x',
        valueCents: 1500,
        cadence: 'monthly',
        anchor: 'calendar',
      },
    ],
  }

  // @lat: [[tests#Card catalogue#A template amortises a rolling credit]]
  it('prices a rolling credit at its amortised value and copies the interval', () => {
    expect(templateAnnualValueCents(rolling)).toBe(21_000)
    const [benefit] = benefitsFromTemplate(
      rolling,
      'card-9',
      '2026-09-16T00:00:00.000Z',
      () => 'id',
    )
    expect(benefit?.cadence).toBe('rolling')
    expect(benefit?.intervalMonths).toBe(48)
  })
})

describe('templateAnnualValueCents', () => {
  // @lat: [[tests#Card catalogue#A template prices its year without its spend-gated credits]]
  it('prices a template without its spend-gated credits', () => {
    const gated: CardTemplate = {
      ...template,
      benefits: [
        {
          name: 'Gated',
          category: 'other',
          icon: 'x',
          valueCents: 120_000,
          cadence: 'annual',
          anchor: 'calendar',
          spendThresholdCents: 25_000_000,
        },
        {
          name: 'Open',
          category: 'other',
          icon: 'x',
          valueCents: 1500,
          cadence: 'monthly',
          anchor: 'calendar',
        },
      ],
    }
    expect(templateAnnualValueCents(gated)).toBe(18_000)
  })
})
