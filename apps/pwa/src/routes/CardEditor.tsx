import { useNavigate, useParams } from '@solidjs/router'
import { createMemo, createSignal, For, Show } from 'solid-js'
import { cadenceLabel } from '../domain/cycles.ts'
import { formatMoney } from '../domain/format.ts'
import { cardLabel, isLocked } from '../domain/selectors.ts'
import { anniversaryError, moneyError, parseMoney, requiredError } from '../domain/validation.ts'
import { useApp } from '../stores/app.tsx'
import { Field } from '../ui/Field.tsx'
import { Ph } from '../ui/Ph.tsx'
import { useSnackbar } from '../ui/Snackbar.tsx'
import { TopBar } from '../ui/TopBar.tsx'
import './CardEditor.css'
import { useScreenTitle } from '../ui/useScreenTitle.ts'

/** Editing a card: its details, and the list of credits attached to it. */
export function CardEditor() {
  const app = useApp()
  const params = useParams<{ id: string }>()
  const navigate = useNavigate()
  const snackbar = useSnackbar()

  const card = createMemo(() => app.data.cards.find((c) => c.id === params.id))
  useScreenTitle(() => {
    const current = card()
    return current ? cardLabel(current) : 'Card not found'
  })
  // What has been typed, kept apart from the store so an invalid value can
  // show its error without being written or snapped back.
  const [holderDraft, setHolderDraft] = createSignal<string | null>(null)
  const [feeDraft, setFeeDraft] = createSignal<string | null>(null)
  const [anniversaryDraft, setAnniversaryDraft] = createSignal<string | null>(null)
  const holderText = () => holderDraft() ?? card()?.holder ?? ''
  const feeText = () => feeDraft() ?? ((card()?.annualFeeCents ?? 0) / 100).toString()
  const anniversaryText = () => anniversaryDraft() ?? card()?.anniversaryOn ?? ''
  const errors = {
    holder: () => requiredError(holderText(), 'Enter whose card this is.'),
    fee: () => moneyError(feeText()),
    anniversary: () => anniversaryError(anniversaryText()),
  }

  const benefits = createMemo(() =>
    app.data.benefits
      .filter((b) => b.cardId === params.id)
      .sort((a, b) => a.name.localeCompare(b.name)),
  )

  function removeCard() {
    const current = card()
    if (!current) return
    // Deleting a card destroys its claim history, which no undo snackbar can
    // honestly cover, so this one asks first.
    const confirmed = window.confirm(
      `Delete ${cardLabel(current)} and everything logged against it? This cannot be undone.`,
    )
    if (!confirmed) return
    app.deleteCard(current.id)
    snackbar.show('Card deleted.')
    navigate('/cards')
  }

  return (
    <Show
      when={card()}
      fallback={
        <>
          <TopBar title="Card not found" onBack={() => navigate('/cards')} />
          <p class="screen__pad section-note">That card is no longer here.</p>
        </>
      }
    >
      {(current) => (
        <>
          <TopBar
            title={cardLabel(current())}
            subtitle={`${benefits().length} credits`}
            onBack={() => navigate('/cards')}
            action={{ icon: 'trash', label: 'Delete this card', onAct: removeCard }}
          />

          <div class="screen__pad stack stack--loose form-grid">
            <p class="form-note">Fields marked * are required.</p>

            <Field id="card-holder" label="Cardholder" required error={errors.holder()}>
              {(control) => (
                <input
                  {...control}
                  class="input"
                  value={holderText()}
                  onInput={(e) => {
                    setHolderDraft(e.currentTarget.value)
                    if (!errors.holder()) {
                      app.updateCard(current().id, { holder: e.currentTarget.value.trim() })
                    }
                  }}
                />
              )}
            </Field>

            <div class="field">
              <label class="field__label" for="card-nickname">
                Nickname
              </label>
              <input
                id="card-nickname"
                class="input"
                value={current().nickname ?? ''}
                placeholder={`${current().issuer} ${current().product}`}
                onInput={(e) => app.updateCard(current().id, { nickname: e.currentTarget.value })}
              />
            </div>

            <Field id="card-fee" label="Annual fee" required error={errors.fee()}>
              {(control) => (
                <input
                  {...control}
                  class="input numeric"
                  type="number"
                  inputmode="decimal"
                  min="0"
                  step="1"
                  value={feeText()}
                  onInput={(e) => {
                    setFeeDraft(e.currentTarget.value)
                    const cents = parseMoney(e.currentTarget.value)
                    if (cents !== null && cents >= 0) {
                      app.updateCard(current().id, { annualFeeCents: cents })
                    }
                  }}
                />
              )}
            </Field>

            <Field id="card-anniversary" label="Renews on" required error={errors.anniversary()}>
              {(control) => (
                <input
                  {...control}
                  class="input"
                  type="date"
                  value={anniversaryText()}
                  onInput={(e) => {
                    setAnniversaryDraft(e.currentTarget.value)
                    if (!anniversaryError(e.currentTarget.value)) {
                      app.updateCard(current().id, { anniversaryOn: e.currentTarget.value })
                    }
                  }}
                />
              )}
            </Field>

            <section>
              <div class="row row--between" style={{ 'margin-bottom': 'var(--space-4)' }}>
                <h2 class="section-title">Credits</h2>
                <button
                  type="button"
                  class="btn btn--small"
                  onClick={() => {
                    const benefit = app.addBenefit({
                      cardId: current().id,
                      name: 'New credit',
                      category: 'other',
                      valueCents: 0,
                      cadence: 'monthly',
                      anchor: 'calendar',
                      enrollmentRequired: false,
                      redemptionSteps: [],
                      muted: false,
                      lastCallOnly: false,
                      active: true,
                    })
                    navigate(`/benefit/${benefit.id}`)
                  }}
                >
                  <Ph name="plus" size={12} />
                  Add
                </button>
              </div>

              <div class="stack stack--tight">
                <For each={benefits()}>
                  {(benefit) => (
                    <a class="benefit-link" href={`/benefit/${benefit.id}`}>
                      <Ph name={benefit.icon ?? 'sparkle'} size={15} />
                      <span class="grow">
                        <span class="benefit-link__name truncate">{benefit.name}</span>
                        <span class="benefit-link__meta">
                          {cadenceLabel(benefit.cadence)} &middot; {formatMoney(benefit.valueCents)}
                          <Show when={isLocked(benefit)}> &middot; needs enrolment</Show>
                          <Show when={!benefit.active}> &middot; paused</Show>
                        </span>
                      </span>
                      <Ph name="caret-right" size={13} />
                    </a>
                  )}
                </For>
              </div>
            </section>
          </div>
        </>
      )}
    </Show>
  )
}
