# HelpMe Reward

A local-first PWA for households that hold more premium credit cards than they can track. On opening it answers one question, "what am I about to lose?", and warns before each credit lapses.

There is no account and no backend. Everything lives in the browser's IndexedDB, and the export in Settings is the only backup. See [[architecture]] for how the pieces fit, [[domain]] for the concepts, and [[reminders]] for the part that is the product.

## The household premise

The hard case is not two different cards with clashing offers. It is the same card held twice: two Platinums in one household means every credit exists twice, and one booking cannot draw on both.

So the app is a *household* deadline manager. Cards belong to people (`Card.holder`), and credits are matched across them by [[domain#Overlaps]]. The holder is asked for at add time rather than inferred, because telling two identical Platinums apart is the whole point.

## Three distinctions that drive everything

Most of the design decisions in the domain layer trace back to one of these three.

- **Cycles are calendar objects.** A monthly credit is "September", not "the last 30 days", and a Sapphire Reserve travel credit runs on the cardmember year. The anchor is recorded per credit, never guessed from the cadence. See [[domain#Benefit#Cycle anchors]].
- **Locked is not unclaimed.** A credit behind an unticked enrolment box is money you *cannot* spend, not money you are failing to spend. It is counted separately and never dunned. See [[domain#Status ladder#Locked is not unclaimed]].
- **Partial use is normal.** $40 of a $100 dining credit is the common case. An app that only offers a tick mark trains people to lie to it. See [[domain#Claims]].

## Stack

TypeScript 7, Solid 1.9, Vite 8, vite-plugin-pwa in `injectManifest` mode, Biome 2, Vitest 5. No CSS framework and no component library: the design system is the component library (see [[design]]).

State is a single Solid store snapshotted to IndexedDB ([[architecture#Persistence]]). The service worker is hand-written because it owns reminder replay ([[reminders#Service-worker replay]]).

## Source layout

Each directory maps to a layer described in [[architecture#Layers]].

| Path | What lives there |
| --- | --- |
| `src/domain/` | Pure logic with no framework imports: dates, cycles, ladder, selectors, reminders, catalogue |
| `src/services/` | IndexedDB persistence, notification plumbing, service-worker registration |
| `src/stores/` | Solid contexts: app data and transient UI state |
| `src/ui/` | Components: rows, sheets, swipe, tab bar, snackbar |
| `src/routes/` | Screens: Today, Credits, Cards, Value, editors, Settings |
| `src/sw.ts` | Service worker: precache, push, reminder replay |
| `samples/`, `scripts/` | An importable sample household and the script that generates it |
| `deploy/`, `infra/`, `.github/` | nginx config, Pulumi, CI/CD ([[deployment]]) |
| `design-reference/` | Vendored Nocturne tokens and the original design canvas |

## Known caveats

These are deliberate limits, not bugs.

- The card catalogue is a starting point, not a source of truth. Issuers change terms constantly; everything it creates is an ordinary editable credit. See [[domain#Card catalogue]].
- Web Push needs a backend that is not in this repository. Without it the app falls back to service-worker replay, which only fires while the browser runs or on next launch. See [[reminders#Delivery paths]].
- Solid 2.0 is in release candidate; the app targets stable 1.9.
