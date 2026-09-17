# Architecture

HelpMe Reward is a static single-page PWA: a pure domain layer, a single Solid store snapshotted to IndexedDB, a thin services layer over browser APIs, and a hand-written service worker that shares the same database.

There is no server. A deploy carries no migration and no data risk, which is why the rollback runbook is short ([[deployment]]).

## Layers

Dependencies point inward: routes and UI depend on stores, stores on services and domain, services on domain, and the domain on nothing.

- **`src/domain/`** is pure logic with no framework imports. This is the part the unit tests cover ([[tests]]) and the part `scripts/make-sample.ts` reuses to build a fixture the app will agree with.
- **`src/services/`** wraps IndexedDB, notifications and service-worker registration.
- **`src/stores/`** holds two Solid contexts: [[architecture#The app store]] and [[architecture#UI state]].
- **`src/ui/`** and **`src/routes/`** are components and screens. Every list renders rows through one shared actions hook so a swipe and a sheet button behave identically ([[design#Undo over confirmation]]).
- **`src/sw.ts`** is the worker ([[reminders#Service-worker replay]]).

## Persistence

The whole dataset is one IndexedDB record. A household's cards, benefits and claims are measured in kilobytes, so snapshot writes are cheaper than per-entity stores, and the service worker can read the same database without a schema to agree on.

`src/services/db.ts` names the database (`cardvantage`), store (`state`) and keys: `app-data` for the snapshot, `reminder-schedule` for the worker. `DATA_VERSION` is bumped when a migration is needed; [[src/services/db.ts#migrate]] brings any older snapshot up to shape by defaulting missing fields, and is also applied on import.

[[src/services/db.ts#loadData]] never throws: a corrupt or blocked IndexedDB starts the app empty rather than white-screening, because empty is recoverable and a crash is not.

## The app store

[[src/stores/app.tsx#AppProvider]] owns a Solid store of `AppData`, every mutation, and the memos the screens read: `instances` (every active credit resolved against today, by urgency), `missed`, `cardSummaries`, and `visibleInstances` narrowed by the household filter.

Two boot-time subtleties:

- The persisted snapshot is loaded asynchronously and applied with `reconcile`, but only if nothing has been written locally in the meantime. The UI is gated on `loading()`, so in the app this cannot happen; a caller that does not wait (a test, or future programmatic use) would otherwise have its change silently discarded. The user's action wins.
- The save effect reads the whole store as a JSON snapshot so it tracks every field, then bails out while loading, so the empty default never overwrites a real snapshot.

Mutations go through a `write` wrapper that marks local changes. Notable ones: `claim` defaults to the remaining balance ([[domain#Claims]]), `deleteCard` cascades to benefits and claims, and `replaceAll` runs [[src/services/db.ts#migrate]] over imported data.

### Keeping today fresh

A PWA is resumed rather than reloaded, so a date captured at boot goes stale overnight and would show yesterday's deadlines. [[src/stores/app.tsx#createToday]] re-reads the clock every minute, on `visibilitychange`, and on `focus`.

### Import and export

`exportJson` dumps the store; `importJson` refuses anything without a `cards` array and otherwise migrates and replaces everything. Since nothing is uploaded anywhere, this export is the only backup a user has.

## UI state

[[src/stores/ui.tsx#UiProvider]] holds transient state: which credit sheet is open, which overlap is being compared, and whether the nudge preview is showing.

It is a context rather than props because the shell renders the sheets while the screens open them, and the two are on opposite sides of the router's layout boundary. Sheets track a benefit *id*, never a resolved instance: instances are recomputed on every claim, and holding one would leave the sheet showing a balance that went stale the moment the user logged something.

## The shell and routing

[[src/App.tsx#Shell]] is the router's root layout. It has to sit inside the router because the tab bar and the notification handler both use router primitives, and it renders the sheets so a credit opened from Today, Credits or a compare all share one instance.

Routes: `/` Today, `/credits`, `/cards`, `/cards/new`, `/cards/:id`, `/benefit/:id`, `/value`, `/settings`, and a not-found fallback.

The shell also owns three effects: republishing the reminder schedule on every data change (cheap, and a stale schedule is a missed reminder), stamping `data-theme` on the document element where the token sheet can see it, and listening for the worker's `navigate` message when a notification is tapped.

## Service worker lifecycle

The worker is hand-written and Workbox only injects the precache manifest (`injectManifest`), because reminder replay and push handling cannot be expressed by a generated worker.

Reminders are time-critical: a tab left open for a week on an old worker would keep replaying a stale schedule. So a new worker takes over immediately, at both ends: the worker calls `skipWaiting` on install and `clients.claim` on activate, and [[src/services/sw-register.ts#registerServiceWorker]] activates a waiting update straight away rather than waiting for every tab to close. There is no server-side state to be out of step with, and the app re-reads IndexedDB on load, so the immediate swap is safe.

Other decisions in `vite.config.ts` and `src/sw.ts`:

- Registration is skipped in `vite dev` unless `VITE_ENABLE_SW` is set, because precaching fights hot reload. Use `npm run preview` to test offline, installation and notifications.
- Phosphor's 3 MB SVG fallback fonts are excluded from the precache; every current browser loads the woff2 files. Bundling the icon stylesheets from npm rather than a CDN is what lets them be precached at all.
- Navigations resolve to the app shell, except `/api/` paths, so a future push backend is not swallowed.

## PWA manifest

The app installs as a standalone, portrait-only app with two shortcuts: "Expiring soon" (`/?filter=expiring`) and "Add a card" (`/cards/new`). Icons include a maskable variant.

### Brand assets

Everything in `public/icons/` is rendered from the HelpMe Reward icon SVG, whose master lives with the other HelpMe logos outside this repo.

`favicon.svg` is that SVG, the PNG icons are renders of it, the maskable icon is the same art with square corners so the gradient bleeds to every edge, and `badge-72.png` is a white silhouette with the diamond cut out for the Android status bar.

The Today header shows the horizontal logotype from `public/brand/` rather than text. Both the light-ground and dark-ground PNGs are in the DOM, and `Today.css` shows the one matching the `[data-theme]` attribute that `App.tsx` sets. PNGs are used because the logotype SVG depends on the Roboto font, which the app does not load.

## Environment variables

Three build-time variables, all optional. Vite inlines `import.meta.env.*` at build time, so they must be present when the bundle is built (the Dockerfile takes them as build args), not set on the running service.

| Variable | Effect |
| --- | --- |
| `VITE_VAPID_PUBLIC_KEY` | Enables Web Push subscription. A public key; nothing secret is baked in. |
| `VITE_PUSH_API` | Where the push subscription is POSTed (`/subscriptions`). |
| `VITE_ENABLE_SW` | Registers the worker during `vite dev`. |
