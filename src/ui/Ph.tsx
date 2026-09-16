import { Show } from 'solid-js'
/**
 * A Phosphor icon, the set Nocturne specifies.
 *
 * The stylesheets are bundled from npm rather than loaded from a CDN so the
 * service worker can precache them: an icon font fetched at runtime leaves
 * every glyph as an empty box on a cold offline launch.
 */
import '@phosphor-icons/web/regular'
import '@phosphor-icons/web/fill'

interface PhProps {
  /** Phosphor name without the prefix, e.g. `car-profile`. */
  name: string
  /** Fill weight, for the urgent states Nocturne marks with a solid glyph. */
  fill?: boolean
  size?: number | string
  color?: string
  class?: string
  /**
   * Accessible label. Omit for icons that only decorate adjacent text — most
   * icons here sit beside a label that already says the same thing, and
   * announcing both is noise.
   */
  label?: string
}

export function Ph(props: PhProps) {
  const className = () =>
    `${props.fill ? 'ph-fill ph-' : 'ph ph-'}${props.name}${props.class ? ` ${props.class}` : ''}`

  const style = () => ({
    'font-size': typeof props.size === 'number' ? `${props.size}px` : props.size,
    ...(props.color ? { color: props.color } : {}),
    'flex-shrink': 0,
  })

  return (
    <Show
      when={props.label}
      fallback={<i class={className()} style={style()} aria-hidden="true" />}
    >
      {(label) => <i class={className()} style={style()} role="img" aria-label={label()} />}
    </Show>
  )
}
