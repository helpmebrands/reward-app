import { useNavigate, useParams } from '@solidjs/router'
import { createMemo, For, Show } from 'solid-js'
import { cadenceLabel, cycleFor } from '../domain/cycles.ts'
import { formatDate } from '../domain/format.ts'
import { ladderSummary } from '../domain/ladder.ts'
import { categoryLabel } from '../domain/selectors.ts'
import type { Benefit, BenefitCategory, Cadence, CycleAnchor } from '../domain/types.ts'
import { useApp } from '../stores/app.tsx'
import { Ph } from '../ui/Ph.tsx'
import { useSnackbar } from '../ui/Snackbar.tsx'
import { Switch } from '../ui/Switch.tsx'
import { TopBar } from '../ui/TopBar.tsx'

const CADENCES: Cadence[] = ['monthly', 'quarterly', 'semiannual', 'annual', 'manual']
const CATEGORIES: BenefitCategory[] = [
  'travel',
  'dining',
  'shopping',
  'entertainment',
  'rideshare',
  'wellness',
  'lodging',
  'airline',
  'streaming',
  'fee_credit',
  'other',
]

/**
 * Editing one credit.
 *
 * The cadence and anchor controls show the window they produce, live: "Sep 1 –
 * Sep 30" under a monthly calendar credit, and a cardmember window under an
 * anniversary one. Those two fields decide whether a reminder arrives in time,
 * and they are the ones users most often get wrong.
 */
export function BenefitEditor() {
  const app = useApp()
  const params = useParams<{ id: string }>()
  const navigate = useNavigate()
  const snackbar = useSnackbar()

  const benefit = createMemo(() => app.data.benefits.find((b) => b.id === params.id))
  const card = createMemo(() => app.data.cards.find((c) => c.id === benefit()?.cardId))

  const preview = createMemo(() => {
    const current = benefit()
    const owner = card()
    if (!current || !owner) return null
    return cycleFor(current, owner, app.today())
  })

  function patch(changes: Partial<Benefit>) {
    const current = benefit()
    if (current) app.updateBenefit(current.id, changes)
  }

  function remove() {
    const current = benefit()
    if (!current) return
    const confirmed = window.confirm(
      `Delete ${current.name} and everything logged against it? This cannot be undone.`,
    )
    if (!confirmed) return
    app.deleteBenefit(current.id)
    snackbar.show('Credit deleted.')
    navigate(card() ? `/cards/${card()?.id}` : '/cards')
  }

  return (
    <Show
      when={benefit()}
      fallback={
        <>
          <TopBar title="Credit not found" onBack={() => navigate('/credits')} />
          <p class="screen__pad section-note">That credit is no longer here.</p>
        </>
      }
    >
      {(current) => (
        <>
          <TopBar
            title={current().name}
            subtitle={card()?.holder}
            onBack={() => navigate(card() ? `/cards/${card()?.id}` : '/credits')}
            action={{ icon: 'trash', label: 'Delete this credit', onAct: remove }}
          />

          <div class="screen__pad stack stack--loose">
            <div class="field">
              <label class="field__label" for="benefit-name">
                Name
              </label>
              <input
                id="benefit-name"
                class="input"
                value={current().name}
                onInput={(e) => patch({ name: e.currentTarget.value })}
              />
            </div>

            <div class="field">
              <label class="field__label" for="benefit-value">
                Value each period
              </label>
              <input
                id="benefit-value"
                class="input numeric"
                type="number"
                inputmode="decimal"
                min="0"
                step="0.01"
                value={(current().valueCents / 100).toString()}
                onInput={(e) =>
                  patch({ valueCents: Math.round(Number(e.currentTarget.value || 0) * 100) })
                }
              />
            </div>

            <div class="field">
              <label class="field__label" for="benefit-cadence">
                How often it resets
              </label>
              <select
                id="benefit-cadence"
                class="input"
                value={current().cadence}
                onChange={(e) => patch({ cadence: e.currentTarget.value as Cadence })}
              >
                <For each={CADENCES}>
                  {(cadence) => <option value={cadence}>{cadenceLabel(cadence)}</option>}
                </For>
              </select>
              <Show when={current().cadence !== 'manual'}>
                <p class="section-note">
                  Reminders at {ladderSummary(current().cadence)} days out.
                </p>
              </Show>
            </div>

            <div class="field">
              <span class="field__label">Measured from</span>
              <div class="seg">
                <button
                  type="button"
                  class="seg__opt"
                  aria-pressed={current().anchor === 'calendar'}
                  onClick={() => patch({ anchor: 'calendar' as CycleAnchor })}
                >
                  The calendar
                </button>
                <button
                  type="button"
                  class="seg__opt"
                  aria-pressed={current().anchor === 'anniversary'}
                  onClick={() => patch({ anchor: 'anniversary' as CycleAnchor })}
                >
                  Card anniversary
                </button>
              </div>
              <Show when={preview()}>
                {(cycle) => (
                  <p class="section-note">
                    This period runs {formatDate(cycle().start)} &ndash; {formatDate(cycle().end)} (
                    {cycle().label}).
                  </p>
                )}
              </Show>
            </div>

            <div class="field">
              <label class="field__label" for="benefit-category">
                Category
              </label>
              <select
                id="benefit-category"
                class="input"
                value={current().category}
                onChange={(e) => patch({ category: e.currentTarget.value as BenefitCategory })}
              >
                <For each={CATEGORIES}>
                  {(category) => <option value={category}>{categoryLabel(category)}</option>}
                </For>
              </select>
            </div>

            <div class="field">
              <label class="field__label" for="benefit-merchant">
                Where it must be spent (optional)
              </label>
              <input
                id="benefit-merchant"
                class="input"
                value={current().merchant ?? ''}
                placeholder="Resy"
                onInput={(e) => patch({ merchant: e.currentTarget.value })}
              />
              <p class="section-note">Used to spot the same credit sitting on two cards.</p>
            </div>

            <div class="panel row row--between">
              <span class="grow">
                <span style={{ display: 'block', 'font-size': '12px' }}>Needs enrolment</span>
                <span class="section-note">
                  Until it is enrolled the credit is Locked, and never counted as money you are
                  failing to spend.
                </span>
              </span>
              <Switch
                label="Needs enrolment"
                checked={current().enrollmentRequired}
                onChange={(next) => patch({ enrollmentRequired: next })}
              />
            </div>

            <Show when={current().enrollmentRequired}>
              <div class="panel row row--between">
                <span class="grow">
                  <span style={{ display: 'block', 'font-size': '12px' }}>Enrolled</span>
                  <span class="section-note">
                    <Show when={current().enrolledAt} fallback="Not yet — the credit is locked.">
                      {(at) => `Confirmed ${formatDate(at().slice(0, 10))}.`}
                    </Show>
                  </span>
                </span>
                <Switch
                  label="Enrolled"
                  checked={Boolean(current().enrolledAt)}
                  onChange={(next) =>
                    next ? app.confirmEnrollment(current().id) : app.revokeEnrollment(current().id)
                  }
                />
              </div>

              <div class="field">
                <label class="field__label" for="benefit-enrol-url">
                  Enrolment page (optional)
                </label>
                <input
                  id="benefit-enrol-url"
                  class="input"
                  type="url"
                  inputmode="url"
                  value={current().enrollmentUrl ?? ''}
                  placeholder="https://"
                  onInput={(e) => patch({ enrollmentUrl: e.currentTarget.value })}
                />
              </div>
            </Show>

            <div class="field">
              <label class="field__label" for="benefit-steps">
                How to redeem
              </label>
              <textarea
                id="benefit-steps"
                class="input"
                value={current().redemptionSteps.join('\n')}
                placeholder={'One step per line'}
                onInput={(e) =>
                  patch({
                    redemptionSteps: e.currentTarget.value
                      .split('\n')
                      .map((line) => line.trim())
                      .filter(Boolean),
                  })
                }
              />
            </div>

            <div class="panel row row--between">
              <span class="grow">
                <span style={{ display: 'block', 'font-size': '12px' }}>Track this credit</span>
                <span class="section-note">
                  Turn off to keep its history without counting it or reminding you.
                </span>
              </span>
              <Switch
                label="Track this credit"
                checked={current().active}
                onChange={(next) => patch({ active: next })}
              />
            </div>

            <a class="btn btn--block" href={card() ? `/cards/${card()?.id}` : '/credits'}>
              <Ph name="check" size={14} />
              Done
            </a>
          </div>
        </>
      )}
    </Show>
  )
}
