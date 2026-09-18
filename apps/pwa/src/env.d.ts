/// <reference types="vite/client" />
/// <reference types="vite-plugin-pwa/client" />

/**
 * The Phosphor package exposes its stylesheets through subpath exports that
 * resolve to `.css`. Vite handles them, but TypeScript wants a declaration for
 * a side-effect import it cannot type.
 */
declare module '@phosphor-icons/web/regular'
declare module '@phosphor-icons/web/fill'

interface ImportMetaEnv {
  /** VAPID public key. Absent means push is off and the SW replays locally. */
  readonly VITE_VAPID_PUBLIC_KEY?: string
  /** Base URL of a push backend, if one is deployed. */
  readonly VITE_PUSH_API?: string
  /** Set to register the service worker during `vite dev`. */
  readonly VITE_ENABLE_SW?: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}
