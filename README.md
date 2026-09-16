# Cardvantage

A PWA for households that hold more premium credit cards than they can keep
track of. It answers one question on opening — *what am I about to lose?* — and
warns before each credit lapses.

## The problem it models

The hard case is not two different cards with clashing offers. It is **the same
card held twice**: two Platinums in one household means every credit exists
twice, and a single booking cannot draw on both. So the domain is a *household*
deadline manager — cards belong to people, and credits are matched across them.

Three distinctions drive everything:

- **Cycles are calendar objects.** A monthly credit is "September", not "the
  last 30 days", and a Sapphire Reserve travel credit runs on the cardmember
  year rather than the calendar year. Mixing these up is the commonest way a
  credit is lost, so the anchor (`calendar` or `anniversary`) is recorded per
  credit rather than guessed from the cadence.
- **Locked is not unclaimed.** A credit behind an unticked enrolment box is not
  money you are failing to spend — it is money you *cannot* spend. It is counted
  separately, excluded from the headline, and never dunned as if you were being
  lazy.
- **Partial use is normal.** $40 of a $100 dining credit is the common case. An
  app that only offers a tick mark trains people to lie to it, after which every
  number it shows is wrong.

The status ladder is `Locked → Use soon → Available → Captured / Missed`, plus
`Manual` for credits no cycle can track (Global Entry every four years).

## Reminders

Reminder timing is the product. A monthly $15 credit and an annual $300 one
cannot share a schedule, so each cadence has its own ladder, and the tone climbs
along it from a permissive "you can use me" to a last call:

| Cadence | Rungs (days before the window shuts) |
| --- | --- |
| Monthly | 23 · 7 · last day |
| Quarterly | 30 · 14 · 3 |
| Semi-annual | 60 · 21 · 7 |
| Annual | 180 · 90 · 30 · 7 |

Reminders due on the same day are **grouped into one notification** that leads
with the single biggest loss. A household with two premium cards can have a
dozen credits lapsing in one week, and a dozen separate alerts is how an app
gets muted.

Delivery takes two paths, because no single one works everywhere:

1. **Web Push** — reaches a user whose browser is closed. Needs a server holding
   the VAPID private key; set `VITE_VAPID_PUBLIC_KEY` and `VITE_PUSH_API`.
2. **Service-worker replay** — the worker keeps the computed schedule in
   IndexedDB and fires anything that came due while the app was shut, on the
   next Periodic Background Sync, push, or launch. No server required. This is
   the path on iOS, where Periodic Sync is unavailable.

> **iOS:** notifications only reach apps added to the Home Screen. Settings
> detects this and says so before asking for permission.

## Design

The screens come from the **Nocturne** design system (`design-reference/`):
a near-neutral blue-grey ground, a single blurple accent used as a line and a
glow rather than a flood, Inter at medium weight, 8px radii and a compact 0.7×
density. Primary actions are an accent *outline*, never a fill. There is no
alarm red — urgency is carried by a saturated indigo ground and a filled glyph.

Material Design supplies the mobile *ergonomics* Nocturne (a system drawn for
pages) does not cover: 48px minimum touch targets, swipe actions, bottom-sheet
behaviour, state layers and motion curves. Where the two disagree on looks,
Nocturne wins; where they disagree on touch behaviour, Material wins.

Every colour, space, radius and duration resolves to a token in
`src/styles/tokens.css`, so re-theming is a token swap rather than a sweep
through components.

### Gestures

- **Swipe right** on a credit to log it in full; **swipe left** to silence it.
  The row parks open rather than firing on release — an action a flick away
  should still need a deliberate tap — and every logged claim returns an undo.
- **Drag the sheet handle down** to dismiss, by distance or by flick.
- Both gestures direction-lock, so a fast scroll never half-opens a row. Every
  swipe action is also a button in the detail sheet: a gesture nobody discovers
  is not a feature.

## Stack

TypeScript 7 · Solid 1.9 · Vite 8 · vite-plugin-pwa (injectManifest) · Biome 2 ·
Vitest 5. No CSS framework and no component library — the design system is the
component library.

State is a single Solid store snapshotted to IndexedDB. Everything stays on the
device; there is no account and nothing is uploaded, so the export in Settings
is the only backup.

## Running it

See [TESTING.md](TESTING.md) for a walkthrough, including the sample household
in `samples/` that fills the app with a year of history.

```sh
npm install
npm run dev        # http://localhost:5173
npm run build      # typecheck, then production build into dist/
npm run preview    # serve the build (needed to exercise the service worker)
npm test           # 94 unit tests
npm run lint       # Biome
npm run format     # Biome, writing fixes
```

The service worker is disabled in `vite dev` unless `VITE_ENABLE_SW` is set —
otherwise precaching fights hot reload. Use `npm run preview` to test offline
behaviour, installation and notifications.

## Layout

```
src/
  domain/      Pure logic, no framework imports — the part worth testing
    dates.ts       Calendar arithmetic (UTC-based; local Date drifts on DST)
    cycles.ts      Windows per cadence and anchor
    ladder.ts      The reminder ladder
    selectors.ts   Statuses, totals, overlaps, the missed ledger
    reminders.ts   Schedule construction and notification copy
    catalog.ts     Starting templates for known cards
  services/    IndexedDB persistence, notification plumbing
  stores/      Solid stores (app data, transient UI state)
  ui/          Components: rows, sheets, swipe, tab bar
  routes/      Today · Credits · Cards · Value, plus editors and settings
  sw.ts        Service worker: precache, push, reminder replay
samples/     An importable household, for trying the app with real history
scripts/     Generates that sample using the app's own cycle functions
```

`design-reference/` holds the Nocturne tokens and the original design canvas,
vendored so the implementation can be checked against the source.

## Caveats

- The card catalogue is a **starting point, not a source of truth**. Issuers
  change these terms constantly. Everything it creates is an ordinary editable
  credit, and the add-card flow says so.
- Web Push needs a backend that is not in this repository. Without it the app
  falls back to service-worker replay, which is fully functional but only fires
  while the browser is running or when the app is next opened.
- Solid 2.0 is in release candidate; this targets the current stable 1.9.
