interface SwitchProps {
  checked: boolean
  onChange: (next: boolean) => void
  /** Required: the control carries no visible text of its own. */
  label: string
  disabled?: boolean
}

/**
 * A switch.
 *
 * `role="switch"` rather than a styled checkbox, so assistive technology
 * announces "on"/"off" instead of "checked" — the setting is a state, not a
 * selection. The 48px tap target is added by the stylesheet.
 */
export function Switch(props: SwitchProps) {
  return (
    <button
      type="button"
      class="switch"
      role="switch"
      aria-checked={props.checked}
      aria-label={props.label}
      disabled={props.disabled}
      onClick={() => props.onChange(!props.checked)}
    >
      <span class="switch__knob" />
    </button>
  )
}
