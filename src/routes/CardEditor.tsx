import { useNavigate, useParams } from '@solidjs/router'
import { createMemo, For, Show } from 'solid-js'
import { cadenceLabel } from '../domain/cycles.ts'
import { formatMoney } from '../domain/format.ts'
import { cardLabel, isLocked } from '../domain/selectors.ts'
import { useApp } from '../stores/app.tsx'
import { Ph } from '../ui/Ph.tsx'
import { useSnackbar } from '../ui/Snackbar.tsx'
import { TopBar } from '../ui/TopBar.tsx'
import './CardEditor.css'

/** Editing a card: its details, and the list of credits attached to it. */
export function CardEditor() {
  const app = useApp()
  const params = useParams<{ id: string }>()
  const navigate = useNavigate()
  const snackbar = useSnackbar()

  const card = createMemo(() => app.data.cards.find((c) => c.id === params.id))
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

          <div class="screen__pad stack stack--loose">
            <div class="field">
              <label class="field__label" for="card-holder">
                Cardholder
              </label>
              <input
                id="card-holder"
                class="input"
                value={current().holder}
                onInput={(e) => app.updateCard(current().id, { holder: e.currentTarget.value })}
              />
            </div>

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

            <div class="field">
              <label class="field__label" for="card-fee">
                Annual fee
              </label>
              <input
                id="card-fee"
                class="input numeric"
                type="number"
                inputmode="decimal"
                min="0"
                step="1"
                value={(current().annualFeeCents / 100).toString()}
                onInput={(e) =>
                  app.updateCard(current().id, {
                    annualFeeCents: Math.round(Number(e.currentTarget.value || 0) * 100),
                  })
                }
              />
            </div>

            <div class="field">
              <label class="field__label" for="card-anniversary">
                Renews on
              </label>
              <input
                id="card-anniversary"
                class="input"
                type="date"
                value={current().anniversaryOn}
                onInput={(e) =>
                  app.updateCard(current().id, { anniversaryOn: e.currentTarget.value })
                }
              />
            </div>

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
