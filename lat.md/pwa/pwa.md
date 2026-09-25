# Reference PWA

The Solid PWA in `apps/pwa` is the reference implementation of the product in [[overview]], and it is frozen: it keeps building, testing and deploying to staging, but takes no new features while the Flutter app catches up.

It keeps everything in the browser's IndexedDB and has no server sync; its export in Settings is how data leaves the browser.

- [[architecture]] — Layers, IndexedDB persistence, the app and UI stores, the shell, service-worker lifecycle and environment variables.
- [[delivery]] — Web Push and service-worker replay.
- [[interaction]] — Responsive layout, swipe rows, bottom sheets, forced colours and truncation.
- [[pwa-tests]] — The store, accessibility in jsdom and Chromium, the manifest, token contrast and snackbar timing.

## Stack

TypeScript 7, Solid 1.9, Vite 8, vite-plugin-pwa in `injectManifest` mode, Biome 2, Vitest 5. No CSS framework and no component library: the design system is the component library (see [[design]]).

State is a single Solid store snapshotted to IndexedDB ([[architecture#Persistence]]). The service worker is hand-written because it owns reminder replay ([[delivery#Service-worker replay]]).

## Source layout

The repository is an npm workspace: the PWA lives in `apps/pwa`, the Pulumi program in `infra`, and root scripts delegate to both. Each PWA directory maps to a layer described in [[architecture#Layers]].

| Path | What lives there |
| --- | --- |
| `package.json` | Root workspace (`apps/pwa`, `infra`) and the single lockfile; `npm test`, `lint`, `typecheck`, `build` run every workspace |
| `apps/pwa/src/domain/` | Pure logic with no framework imports: dates, cycles, ladder, selectors, reminders, catalogue |
| `apps/pwa/src/services/` | IndexedDB persistence, notification plumbing, service-worker registration |
| `apps/pwa/src/stores/` | Solid contexts: app data and transient UI state |
| `apps/pwa/src/ui/` | Components: rows, sheets, swipe, tab bar, snackbar |
| `apps/pwa/src/routes/` | Screens: Today, Credits, Cards, Value, editors, Settings |
| `apps/pwa/src/sw.ts` | Service worker: precache, push, reminder replay |
| `apps/pwa/tests/` | The Vitest and Playwright suites ([[tests]], [[pwa-tests]]) |
| `apps/pwa/samples/`, `apps/pwa/scripts/` | An importable sample household and the script that generates it |
| `apps/pwa/deploy/`, `apps/pwa/Dockerfile` | nginx config and the container ([[deployment#Container]]) |
| `apps/pwa/design-reference/` | Vendored Nocturne tokens and the original design canvas |
| `infra/`, `.github/`, `docs/runbooks/` | Pulumi, CI/CD and the operations runbooks ([[deployment]]) |

## Known caveats

These are deliberate limits, not bugs.

- The card catalogue is a starting point, not a source of truth. Issuers change terms constantly; everything it creates is an ordinary editable credit. See [[domain#Card catalogue]].
- The PWA's Web Push path was never connected to a backend. Without it the app falls back to service-worker replay, which only fires while the browser runs or on next launch. See [[delivery#Delivery paths]].
- Solid 2.0 is in release candidate; the app targets stable 1.9.
