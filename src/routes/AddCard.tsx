import { useNavigate } from '@solidjs/router'
import { createMemo, createSignal, For, Show } from 'solid-js'
import {
  CARD_TEMPLATES,
  type CardTemplate,
  templateAnnualValueCents,
  templateEnrollmentNames,
} from '../domain/catalog.ts'
import { todayIso } from '../domain/dates.ts'
import { formatMoney } from '../domain/format.ts'
import { holders } from '../domain/selectors.ts'
import { anniversaryError, requiredError } from '../domain/validation.ts'
import { useApp } from '../stores/app.tsx'
import { Field, focusFirstInvalid } from '../ui/Field.tsx'
import { Ph } from '../ui/Ph.tsx'
import { useSnackbar } from '../ui/Snackbar.tsx'
import { TopBar } from '../ui/TopBar.tsx'
import './AddCard.css'
import { useScreenTitle } from '../ui/useScreenTitle.ts'

/**
 * Add a card, in two steps: pick the product, then say whose it is and when the
 * cardmember year turns over.
 *
 * The holder is asked for rather than inferred, because the whole app turns on
 * telling two identical Platinums apart.
 */
export function AddCard() {
  const app = useApp()
  useScreenTitle(() => 'Add a card')
  const navigate = useNavigate()
  const snackbar = useSnackbar()

  const [picked, setPicked] = createSignal<CardTemplate | null>(null)
  const [holder, setHolder] = createSignal(holders(app.data)[0] ?? '')
  const [anniversary, setAnniversary] = createSignal(todayIso())
  const [nickname, setNickname] = createSignal('')
  const [issuer, setIssuer] = createSignal('')
  const [product, setProduct] = createSignal('')

  const catalogue = createMemo(() => CARD_TEMPLATES.filter((t) => t.id !== 'blank'))
  const blank = () => CARD_TEMPLATES.find((t) => t.id === 'blank')

  const isBlank = () => picked()?.id === 'blank'
  const [submitted, setSubmitted] = createSignal(false)

  const errors = {
    issuer: () => (isBlank() ? requiredError(issuer(), 'Enter who issues the card.') : null),
    product: () => (isBlank() ? requiredError(product(), 'Enter the name of the card.') : null),
    holder: () => requiredError(holder(), 'Enter whose card this is.'),
    anniversary: () => anniversaryError(anniversary()),
  }
  const hasErrors = () => Object.values(errors).some((rule) => rule() !== null)

  function save() {
    const template = picked()
    if (!template) return
    // Pressing Save with an invalid form shows the errors rather than doing
    // nothing: a disabled button never says why.
    setSubmitted(true)
    if (hasErrors()) {
      focusFirstInvalid()
      return
    }

    const card = app.addCardFromTemplate(template, {
      holder: holder().trim(),
      anniversaryOn: anniversary(),
      ...(nickname().trim() ? { nickname: nickname().trim() } : {}),
      ...(isBlank() ? { issuer: issuer().trim(), product: product().trim() } : {}),
    })

    const count = template.benefits.length
    snackbar.show(
      count > 0
        ? `Added with ${count} credit${count === 1 ? '' : 's'}. Check the terms — issuers change them.`
        : 'Card added. Add its credits next.',
    )
    navigate(`/cards/${card.id}`)
  }

  return (
    <>
      <TopBar
        title={picked() ? 'Card details' : 'Add a card'}
        subtitle={picked() ? '2 of 2' : '1 of 2'}
        onBack={() => (picked() ? setPicked(null) : navigate('/cards'))}
      />

      <div class="screen__pad">
        <Show
          when={picked()}
          fallback={
            <>
              <p class="section-note" style={{ 'margin-bottom': 'var(--space-6)' }}>
                Pick a card and its credits arrive pre-filled, including which ones need enrolment.
                Everything stays editable — treat the catalogue as a starting point, not gospel.
              </p>

              <div class="stack">
                <For each={catalogue()}>
                  {(template) => (
                    <button
                      type="button"
                      class="catalog"
                      onClick={() => {
                        setPicked(template)
                        setIssuer(template.issuer)
                        setProduct(template.product)
                      }}
                    >
                      <span class="catalog__head">
                        <span class="kicker kicker--quiet">{template.issuer}</span>
                        <span class="catalog__name">{template.product}</span>
                      </span>
                      <span class="catalog__figures numeric">
                        <span>{formatMoney(template.annualFeeCents)} fee</span>
                        <span class="catalog__value">
                          {formatMoney(templateAnnualValueCents(template))} in credits
                        </span>
                      </span>
                      <span class="catalog__meta">
                        {template.benefits.length} credits
                        <Show when={templateEnrollmentNames(template).length > 0}>
                          {' '}
                          &middot; {templateEnrollmentNames(template).length} need enrolment
                        </Show>
                      </span>
                      <Ph name="caret-right" size={14} class="catalog__chevron" />
                    </button>
                  )}
                </For>

                <button
                  type="button"
                  class="btn btn--dashed"
                  onClick={() => {
                    const template = blank()
                    if (!template) return
                    setPicked(template)
                    setIssuer('')
                    setProduct('')
                  }}
                >
                  <Ph name="pencil-simple" size={14} />
                  Set one up by hand
                </button>
              </div>
            </>
          }
        >
          {(template) => (
            <div class="stack stack--loose">
              <Show when={!isBlank()}>
                <div class="panel">
                  <span class="kicker kicker--quiet">{template().issuer}</span>
                  <p class="addcard__picked">{template().product}</p>
                  <p class="section-note">
                    {template().benefits.length} credits worth{' '}
                    {formatMoney(templateAnnualValueCents(template()))} a year against a{' '}
                    {formatMoney(template().annualFeeCents)} fee.
                  </p>
                </div>
              </Show>

              <p class="form-note">Fields marked * are required.</p>

              <Show when={isBlank()}>
                <Field
                  id="issuer"
                  label="Issuer"
                  required
                  error={errors.issuer()}
                  submitted={submitted()}
                >
                  {(control) => (
                    <input
                      {...control}
                      class="input"
                      value={issuer()}
                      placeholder="American Express"
                      onInput={(e) => setIssuer(e.currentTarget.value)}
                    />
                  )}
                </Field>
                <Field
                  id="product"
                  label="Card"
                  required
                  error={errors.product()}
                  submitted={submitted()}
                >
                  {(control) => (
                    <input
                      {...control}
                      class="input"
                      value={product()}
                      placeholder="Platinum"
                      onInput={(e) => setProduct(e.currentTarget.value)}
                    />
                  )}
                </Field>
              </Show>

              <Field
                id="holder"
                label="Whose card is it?"
                required
                error={errors.holder()}
                submitted={submitted()}
                hint="Two people holding the same product is the case this app exists for — the name is how their credits stay apart."
              >
                {(control) => (
                  <>
                    <input
                      {...control}
                      class="input"
                      value={holder()}
                      placeholder="Jim"
                      list="known-holders"
                      onInput={(e) => setHolder(e.currentTarget.value)}
                    />
                    <datalist id="known-holders">
                      <For each={holders(app.data)}>{(name) => <option value={name} />}</For>
                    </datalist>
                  </>
                )}
              </Field>

              <Field
                id="anniversary"
                label="Account opened / renews on"
                required
                error={errors.anniversary()}
                submitted={submitted()}
                hint="Anniversary-based credits run from this date, not from 1 January. Getting it wrong is the commonest way a credit is lost."
              >
                {(control) => (
                  <input
                    {...control}
                    class="input"
                    type="date"
                    value={anniversary()}
                    onInput={(e) => setAnniversary(e.currentTarget.value)}
                  />
                )}
              </Field>

              <div class="field">
                <label class="field__label" for="nickname">
                  Nickname (optional)
                </label>
                <input
                  id="nickname"
                  class="input"
                  value={nickname()}
                  placeholder="The travel one"
                  onInput={(e) => setNickname(e.currentTarget.value)}
                />
              </div>

              <button type="button" class="btn btn--primary btn--block" onClick={save}>
                <Ph name="check" size={14} />
                Add this card
              </button>
            </div>
          )}
        </Show>
      </div>
    </>
  )
}
