import { describe, expect, it } from 'vitest'
import {
  benefitsFromTemplate,
  CARD_TEMPLATES,
  type CardTemplate,
  findTemplate,
  templateAnnualValueCents,
} from '../src/domain/catalog.ts'
import { annualValueOf } from '../src/domain/cycles.ts'

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

describe('the shipped catalogue', () => {
  function template(id: string): CardTemplate {
    const found = findTemplate(id)
    if (!found) throw new Error(`missing template ${id}`)
    return found
  }

  // @lat: [[tests#Card catalogue#Business Platinum is priced at its unconditional credits]]
  it('prices Business Platinum at its unconditional credits only', () => {
    const platinum = template('amex-business-platinum')
    const gated = platinum.benefits.filter((b) => b.spendThresholdCents !== undefined)
    expect(gated.map((b) => [b.name, b.spendThresholdCents])).toEqual([
      ['Dell Technologies Credit ($5K spend bonus)', 500_000],
      ['Amex Travel Flight Credit ($250K spend unlock)', 25_000_000],
      ['American Express One AP Credit ($250K spend unlock)', 25_000_000],
    ])
    const unconditional = platinum.benefits
      .filter((b) => b.spendThresholdCents === undefined)
      .reduce((sum, b) => sum + annualValueOf(b.valueCents, b.cadence, b.intervalMonths), 0)
    expect(templateAnnualValueCents(platinum)).toBe(unconditional)
    expect(templateAnnualValueCents(platinum)).toBeLessThan(platinum.annualFeeCents * 4)
  })

  // @lat: [[tests#Card catalogue#Every Global Entry credit rolls every 48 months]]
  it('amortises every Global Entry credit to $30 a year', () => {
    const entries = CARD_TEMPLATES.flatMap((t) =>
      t.benefits.filter((b) => b.name.startsWith('Global Entry')).map((b) => [t.id, b] as const),
    )
    expect(entries.length).toBeGreaterThan(0)
    for (const [id, benefit] of entries) {
      expect(benefit.cadence, `${id}/${benefit.name}`).toBe('rolling')
      expect(benefit.intervalMonths, `${id}/${benefit.name}`).toBe(48)
      expect(annualValueOf(benefit.valueCents, benefit.cadence, benefit.intervalMonths)).toBe(3000)
    }
    expect(CARD_TEMPLATES.flatMap((t) => t.benefits).some((b) => b.cadence === 'manual')).toBe(
      false,
    )
  })

  // @lat: [[tests#Card catalogue#Dated credits carry their end]]
  it('ends the credits the issuer has dated', () => {
    const endsOn = (id: string, name: string) =>
      template(id).benefits.find((b) => b.name === name)?.endsOn
    expect(endsOn('chase-sapphire-reserve', 'StubHub / viagogo Credit')).toBe('2027-12-31')
    expect(endsOn('chase-sapphire-reserve', 'Peloton Membership Credit')).toBe('2027-12-31')
    expect(endsOn('chase-sapphire-reserve', 'DoorDash Restaurant Promo')).toBe('2027-12-31')
    expect(endsOn('chase-sapphire-reserve', 'DoorDash Non-Restaurant Promos')).toBe('2027-12-31')
    expect(endsOn('chase-sapphire-reserve', 'Lyft Credit')).toBe('2027-09-30')
    expect(endsOn('chase-united-quest', 'Instacart $10 Monthly Credit')).toBe('2027-12-31')
    expect(endsOn('chase-united-quest', 'Instacart $5 Monthly Credit')).toBe('2027-12-31')
  })

  // @lat: [[tests#Card catalogue#The IHG spend credit is gated]]
  it('gates the IHG $20K spend credit', () => {
    const ihg = template('chase-ihg-one-rewards-premier').benefits.find(
      (b) => b.name === '$20K Spend Statement Credit',
    )
    expect(ihg?.spendThresholdCents).toBe(2_000_000)
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
