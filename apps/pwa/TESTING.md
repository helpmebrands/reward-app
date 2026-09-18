# Trying HelpMe Reward yourself

The app is a static PWA with no backend, so running it is `npm install` and a
dev server. Two things need the *production* build rather than `npm run dev` —
the service worker and notifications — so both paths are below.

## 1. Get it running

Requires **Node 22 or newer** (`node -v`).

```sh
git clone https://github.com/helpmebrands/reward-app.git
cd reward-app
git checkout claude/festive-franklin-ohfp5z
npm install

npm run dev          # http://localhost:5173 — fast reload, no service worker
```

For anything involving offline, installation or notifications, use the real
build instead:

```sh
npm run build
npm run preview      # http://localhost:4173
```

`localhost` counts as a secure context, so notifications and the service worker
work there without HTTPS.

Open your browser's device toolbar and pick a phone (iPhone 16 Pro is what the
screens were drawn at, 402×874). The layout is capped at that width, so a
desktop window shows the app centred rather than stretched.

## 2. Load the sample household

A fresh install is empty, and most of what is worth judging — the Value tab, the
missed ledger, a card that has not earned back its fee — only exists once there
is history behind it.

Open **Settings** — the gear beside *Preview nudge*, top right of Today — then
**Your data → Import a backup**, and pick `samples/sample-household.json`.

That gives you the scenario the design was drawn around: **two Platinums, one
household**. Jim stays on top of his; Kathy does not. Dated to 16 September 2026,
which is the app's "today" for this data.

| | Jim | Kathy |
| --- | --- | --- |
| Captured this cardmember year | $592 — 66% of the fee | $30 — 3% of the fee |
| Locked behind enrolment | — | $500 (Equinox, Oura) |
| Days to renewal | 179 | 289 |

Household-wide that is **$1,658.90 still claimable**, **$500 locked** and
**$1,672.20 already missed** — eight months of small monthly credits on both
cards, plus the whole of Kathy's H1 hotel credit.

> **One number that looks wrong but isn't.** The Value tab says $1,450 captured
> while the Cards tab says $592 for Jim and $30 for Kathy. They are different
> windows on purpose: Value covers the last nine calendar months, while a card's
> figure covers *its own* cardmember year — Jim's started 14 March and Kathy's
> 2 July, so anything either of them captured before those dates is real but
> belongs to the previous fee period. A credit only pays for the fee it was
> issued against.

To get back to an empty app: Import a file you exported first, or clear the
site's storage in DevTools (Application → Storage → Clear site data).

## 3. What to actually poke at

**The headline.** Today shows one number — what you can still claim. Note what
it deliberately *excludes*: Kathy's $500 of locked credits are in their own
section, because that is money you cannot spend rather than money you are
failing to spend. The Credits tab keeps all four figures apart for the same
reason; claimable and missed are never summed.

**Swipe a row** (needs a touch device or DevTools device mode — the gesture
ignores mouse input deliberately):

- Swipe **right** to log a credit in full. It parks open rather than firing on
  release; tap the revealed button to commit. Every log leaves an **Undo** in
  the snackbar.
- Swipe **left** to silence that credit's reminders.
- Try a fast *vertical* flick across a row — it should scroll and never
  half-open the row.

**Log a partial amount.** Tap any credit → *Log what you spent*. $40 of a $100
dining credit is the normal case; the quick amounts and "Other…" both cap at
what is actually left. Watch the Today headline move as you do it.

**The overlap card.** Today → "Two cards, one benefit" → *Compare*. This is the
premise: the same credit exists twice and one booking cannot draw on both.

**A locked credit.** Open one of Kathy's (Equinox or Oura). It offers "I've
enrolled — unlock this credit" rather than asking you to spend it. Unlock it and
watch it move out of the Locked pile into the headline.

**The Value tab.** Cards are plotted as a percentage of their *own* fee, so the
100% line is break-even for both despite identical fees — and Jim at 66% versus
Kathy at 3% is legible at a glance.

## 4. Notifications

**Settings (the gear on Today) → Reminders → Send me reminders.** Your browser will ask for
permission. Then:

- **Send a test notification** shows what one looks like immediately.
- **Preview nudge** (top right of Today) shows the *next real* reminder with
  your own numbers in it, in-app, without needing permission at all.
- Settings lists how many reminders are scheduled and when the next one fires.

To see one actually arrive, set **"Send them at"** to a minute or two from now,
then close the tab. The service worker fires anything that came due the next
time it wakes.

The timing rules are per-cadence — monthly credits warn at 23 / 7 / 0 days out,
annual ones at 180 / 90 / 30 / 7 — and everything due on the same day is grouped
into **one** notification led by the biggest loss. Settings → The ladder shows
the full table.

> **Caveats.** Chrome and Edge on desktop or Android are the best test. Firefox
> has no Periodic Background Sync, so reminders land when you next open the app.
> **iOS only delivers notifications to apps added to the Home Screen** — the app
> detects this and tells you before asking for permission.

## 5. Installing it, and offline

With `npm run preview` running, Chrome shows an install icon in the address bar
(or ⋮ → *Cast, save and share* → *Install page as app*). Once installed:

- It opens without browser chrome, in portrait.
- **Offline:** open DevTools → Network → *Offline*, then reload. Everything
  works; the data was never on a server to begin with.

## 6. Testing on a real phone

This is where it gets fiddly, and it is worth knowing why. Vite already serves on
your LAN (`npm run preview -- --host` prints an address), which is fine for
checking **layout** on a real device. But `http://192.168.x.x` is not a secure
context, so the **service worker and notifications will not run** there.

For those on a phone you need real HTTPS. Easiest is a tunnel:

```sh
npm run preview
npx cloudflared tunnel --url http://localhost:4173   # or: ngrok http 4173
```

Open the HTTPS URL it prints on your phone. On iOS, add it to the Home Screen
first, then enable notifications from inside the installed app.

## 7. Running the checks

```sh
npm test         # 94 unit tests: date maths, cycles, statuses, overlaps, reminders
npm run lint     # Biome
npm run build    # typecheck, then production build
```

The tests are the fastest way to see what the app believes. `tests/cycles.test.ts`
covers the calendar arithmetic (leap years, month-end clamping, cardmember years
versus calendar years); `tests/reminders.test.ts` covers when a notification
fires and what it says.

## 8. Regenerating the sample

```sh
node --experimental-strip-types scripts/make-sample.ts
```

It builds the fixture with the app's own cycle functions, so the claim keys
always match what the app computes. Edit the dates in that script to explore
other scenarios — a card that clears its fee, a month with nothing missed.
