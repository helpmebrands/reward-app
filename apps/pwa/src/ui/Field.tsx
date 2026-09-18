import { createSignal, type JSX, Show } from 'solid-js'

/**
 * A labelled control with a hint and an error slot (WCAG 3.3.1, 3.3.2).
 *
 * The field owns *when* an error shows: after the control has been left
 * once, or once the form has been submitted, never on the first keystroke.
 * The parent owns *whether* there is one, as a pure rule from
 * `src/domain/validation.ts`. The control is rendered by the caller so any
 * element can sit here; it is handed the ids and states to spread on itself.
 */

export interface ControlProps {
  id: string
  required: boolean | undefined
  'aria-invalid': 'true' | undefined
  'aria-describedby': string | undefined
  onBlur: () => void
}

interface FieldProps {
  id: string
  label: string
  hint?: JSX.Element
  /** The current rule result for the value. */
  error?: string | null
  required?: boolean
  /** True once the form has been submitted; forces errors into view. */
  submitted?: boolean
  children: (control: ControlProps) => JSX.Element
}

export function Field(props: FieldProps) {
  const [touched, setTouched] = createSignal(false)
  const visibleError = () => ((touched() || props.submitted) && props.error) || null
  const hintId = () => `${props.id}-hint`
  const errorId = () => `${props.id}-error`

  const control: ControlProps = {
    get id() {
      return props.id
    },
    get required() {
      return props.required
    },
    get 'aria-invalid'() {
      return visibleError() ? 'true' : undefined
    },
    get 'aria-describedby'() {
      const ids = [props.hint ? hintId() : null, visibleError() ? errorId() : null].filter(Boolean)
      return ids.length ? ids.join(' ') : undefined
    },
    onBlur: () => setTouched(true),
  }

  return (
    <div class="field">
      <label class="field__label" for={props.id}>
        {props.label}
        <Show when={props.required}>
          <span class="field__required" aria-hidden="true">
            {' '}
            *
          </span>
        </Show>
      </label>
      {props.children(control)}
      <Show when={props.hint}>
        <p class="section-note" id={hintId()}>
          {props.hint}
        </p>
      </Show>
      {/* Always present, so a message arriving in it is announced. */}
      <p class="field__error" id={errorId()} aria-live="polite">
        {visibleError()}
      </p>
    </div>
  )
}

/** Moves focus to the first control showing an error, after the DOM settles. */
export function focusFirstInvalid(): void {
  queueMicrotask(() => document.querySelector<HTMLElement>('[aria-invalid="true"]')?.focus())
}
