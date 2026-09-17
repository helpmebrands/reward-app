# Tests

Unit tests under `tests/` cover the pure domain layer and the store's reactive wiring. They are the fastest way to see what the app believes about dates, cycles, statuses, overlaps and reminders.

Vitest runs in jsdom with `tests/factories.ts` supplying fixtures, so each test states only what it is about. The fixture card is an Amex Platinum held by Jim with a 14 March anniversary, and most tests are dated 16 September 2026, the same "today" as the sample household.

## Date arithmetic

`tests/dates.test.ts` guards the calendar-date discipline in [[domain#Calendar dates, not timestamps]].

- Month addition clamps to the end of a shorter month and handles leap years in both directions.
- Day addition does not drift across the US DST transitions on 8 March and 1 November 2026.
- `todayIso` reads the local calendar date, not the UTC one: 23:30 local on the 16th is still the 16th.

## Cycles

`tests/cycles.test.ts` covers window construction for every cadence and both anchors ([[domain#Cycle]]).

- Calendar anchors put quarters on Jan/Apr/Jul/Oct, halves on Jan/Jul, and resolve dates before the anchor year.
- Anniversary anchors run a cardmember year from the open date, place the day before the anniversary in the prior year, and do not drift for a 31st anniversary across short months.
- The invariant: consecutive cycles have no gaps and no overlaps, each starting the day after the last ends.
- Manual benefits have no window and never recur. `daysRemainingIn` is 0 on the final day and negative after. `annualValueCents` counts an untracked credit once.

## Statuses, totals and ledgers

`tests/selectors.test.ts` pins the status ladder and the derived views ([[domain#Status ladder]], [[domain#Missed ledger]]).

- Every rung: use soon inside 30 days, available beyond, captured when fully claimed (even while locked), partial claims summed, locked before enrolment and unlocked after, manual never at risk, archived cards and inactive credits skipped.
- Ordering puts what closes soonest first and locked below open.
- The four totals stay apart. `nextReset` reports the nearest open window.
- Overlaps: one credit on two cards is flagged with `sameProduct`; different issuers match by merchant; two credits on the same card do not overlap; the group totals what is still unclaimed.
- The missed ledger counts closed windows with nothing claimed, counts only the shortfall for partial use, never blames windows before tracking began, and ignores manual credits. Leaks group repeats and rank by money lost. Monthly totals bin claims by when logged and misses by when the window shut.
- `summarizeCard` reports net against the fee; `cardLabel` names the holder and prefers a nickname.

## Ladder and schedule

`tests/reminders.test.ts` covers when a notification fires and what it says ([[reminders#The ladder]], [[reminders#Schedule construction]]).

- Each cadence's rungs match the table, open permissive and end urgent, and collapse to one last call when opted out. `currentRung` reports the rung a credit stands on.
- The schedule is empty while reminders are off, fires a rung at the reminder time on the right day, never schedules in the past, and returns reminders in firing order.
- Same-day credits group into one notification led by the biggest loss; a mostly-locked group leads with the blocker; locked credits are silent when enrolment reminders are off.
- Muted credits, muted cards, fully claimed cycles, manual credits and sub-floor values are skipped; a partly used credit is reminded about for its balance.
- Ids are stable and unique across recomputes, so the worker's dedupe holds.
- `dueReminders` returns only what has come due and not been shown, and drops anything the device slept through for days.

## The store

`tests/store.test.tsx` mounts the real `AppProvider` so memos recomputing after a mutation are covered along with the mutations ([[architecture#The app store]]).

- Adding a card from a template brings its credits and enrolment flags, and records the holder so two identical cards stay apart.
- Claiming defaults to the balance left, never the face value again; unclaiming clears the whole cycle.
- Enrolment unlocks a credit and can be revoked. Muting a credit or a card changes `muted` without moving status.
- Deleting a card removes its credits and claims and leaves the other holder untouched.
- Export and import round-trip the dataset; a file that is not an export is refused.

### Removing one claim leaves the rest

Two claims against the same cycle; removing the first by id leaves the second, so the sheet's Remove never takes more than the row it sits on.
- Every catalogue template gives each credit an icon and a positive value.

## Infrastructure config

`tests/infra-config.test.ts` pins the committed Pulumi configuration and the runbooks that quote it ([[deployment#Infrastructure]]). Drift here is only noticed when a deploy is rejected at the auth step.

### Project is named reward-app

`infra/Pulumi.yaml` names the project `reward-app`, which is also the config namespace the program reads. The pre-rebrand name would recreate every resource once a stack exists.

### Project config declares no namespaced keys

Pulumi rejects a namespaced key such as `gcp:project` declared at project level without a value, so `infra/Pulumi.yaml` declares only the project's own unprefixed keys.

### Staging targets the decided project

`infra/Pulumi.staging.yaml` sets `gcp:project` to `helpme-reward-staging`, the project decided on epic #3, not the misspelt `helpme-rewards-staging`.

### Staging trusts this repository

`githubRepo` is `helpmebrands/reward-app`. The WIF attribute condition and the impersonation binding are built from it, so a wrong value rejects every deploy.

### No stale repository or project names

Nothing under `infra/`, `docs/` or `.github/` names `oravecz/cardvantage` or `helpme-rewards-`.

### No cardvantage in infrastructure names

Nothing under `infra/`, `docs/`, `.github/`, `deploy/` or the `Dockerfile` names `cardvantage`. Service, image, registry and service-account ids all derive from `reward-app`.


### Runbook names the real state backend

Runbook 01 logs Pulumi into `gs://helpme-reward-staging-pulumi-state` rather than offering a choice, so nobody initialises a second, competing copy of the state.

### README records the staging environment

`docs/runbooks/README.md` names the staging project, region, state bucket and `run.app` URL, so a new starter does not reverse-engineer which project is which from repository variables.

### Verify gate typechecks the Pulumi program

`verify.yml` has an `infra` job that runs `npm ci` and `npm run typecheck` in `infra/` with its own lockfile cache, so a type error in `infra/index.ts` fails review instead of the next hand-run `pulumi up`.

## Accessibility tests

Two axe gates for epic #21: `tests/a11y/` runs in jsdom as part of `npm test`, and `tests/e2e/` runs Playwright against the built app with `npm run test:e2e`. Both read one allowlist.

Both suites render every route with the sample household from `samples/sample-household.json`, so what axe sees is a populated screen rather than an empty state. `tests/a11y/allowlist.ts` names each rule currently disabled and the sub-issue that removes it; a sub-issue is not done until its entries are gone. The rule set is WCAG 2.1 A and AA plus axe's best practices.

`tests/a11y/mount.tsx` mounts the real shell ([[src/App.tsx#Shell]]) and route table ([[src/App.tsx#routes]]) on a memory router, so a screen is judged inside the same landmarks, sheets and tab bar it ships with.

The Playwright suite (`playwright.config.ts`) is one project per width and theme: 320, 402, 768 and 1280px, light and dark, against `vite preview` of `dist/`, so build first. Its `theme` option seeds the sample household into IndexedDB with that theme in settings, because the shell owns the `data-theme` attribute and would overwrite a stamp. In CI the `a11y` job of `verify.yml` runs it on the bundle the verify job built, and uploads the HTML report when it fails.

### Every route passes axe in jsdom

Each of the nine routes, including the editors and the not-found screen, renders with no axe violation outside the annotated allowlist.

jsdom has no layout, so this catches names, roles, labels, landmarks, headings and ARIA validity, and not contrast.

### The credit sheet passes axe

Today with the credit sheet open, since the sheet is the app's one modal dialog and is portalled outside `<main>`, renders with no axe violation.

### Landscape keeps the first row on screen

At 667×375, the landscape project of `playwright.config.ts`, every route's first credit row (or heading) can be brought fully into view, nothing scrolls sideways, and the chrome leaves at least 80% of the height to content.

Today's headline number is also visible without scrolling, which is what the short-viewport styles in `base.css`, `TabBar.css` and `Today.css` buy.

### The credit sheet works in landscape

At 667×375 the credit sheet opens no taller than 85% of the viewport, its body scrolls inside the panel, and Escape closes it.

### Every route sets a document title

`tests/a11y/navigation.test.tsx` renders each of the nine routes and expects `document.title` to be the screen's name followed by ` · HelpMe Reward`; the editors use the card label and the credit name.

### Navigation moves focus to the new heading

Moving the memory history from Cards to Add a card places `document.activeElement` on the Add a card `<h1>`, and going back places it on the Cards `<h1>`.

### A tab press keeps focus on the tab

Pressing the Credits tab with focus on it renders Credits and leaves focus on the tab, since the user is still on the control they pressed.

### Submitting with a blank holder shows a linked error

`tests/a11y/forms.test.tsx` picks a catalogue card, clears the holder and presses Save, which is not disabled.

The error sentence appears, the input carries `aria-invalid="true"` and an `aria-describedby` naming the error, and focus lands on the input.

### Correcting the field clears the error and saves

Typing a holder removes the error and `aria-invalid`, and pressing Save again adds the card with that holder.

### The sheet lists claims with a Remove

`tests/a11y/credit-sheet.test.tsx` logs the full balance from the sheet, reopens it, finds the claim under "Logged this period" and presses Remove; the balance returns to what it was and the row is gone.

### Nothing scrolls sideways at 320px

`tests/e2e/reflow.spec.ts`, on the 320px project, loads every route and asserts neither the document nor `#main` can scroll sideways, then repeats that on Today with the credit sheet and the compare sheet open (WCAG 1.4.10).

### Text spacing overrides clip nothing

The same spec injects WCAG 1.4.12's overrides and asserts no element with hidden overflow has content taller than itself, `.truncate` and `.visually-hidden` excepted, and that nothing scrolls sideways.

The overrides are line height 1.5, paragraph spacing 2em, letter spacing 0.12em and word spacing 0.16em. A screenshot of each route is attached to the report for review.

### Body text follows the browser font size

`tests/e2e/large-type.spec.ts` sets the root font size to 24px, which is what the browser preference changes, and expects body text to measure 22.5px: the rem scale following the root (WCAG 1.4.4).

### Controls keep clear of each other at 24px

At the same root size, the bounding boxes of the visible controls on Today and the benefit editor do not overlap and the page does not scroll sideways.

### The phone layout does not move

`tests/e2e/shell.spec.ts` at 320 and 402px compares the boxes of the main column, tab bar, tabs, heading, first row and other landmarks on every route against `tests/e2e/layout-baseline.json`.

The baseline was taken from develop before the responsive work. Positions and heights may drift a pixel, widths four, since shrink-to-fit text rasterises slightly wider on Linux than on macOS.

`UPDATE_LAYOUT_BASELINE=1` rewrites the file when a change to the phone layout is intended.

### The rail and the centred column at wider widths

At 768 and 1280px the main navigation starts at the leading edge, is 80 or 200px wide and full height, the content column is 560 or 720px wide and centred beside the rail, and the four tabs are reached by Tab in order.

### Every route passes axe in a real browser

Each route at each of the four widths and two themes has no axe violation and, unlike the jsdom suite, no *incomplete* result either.

An undecided check that nobody reviews is treated as a failure, which is what makes the contrast entry in the allowlist honest.

## PWA manifest

The manifest must not lock orientation ([[architecture#PWA manifest]], WCAG 1.3.4). Checked twice: on the source before a build exists, and on the built file.

### Manifest sets no orientation

`tests/manifest.test.ts` reads `vite.config.ts` and fails on any `orientation:` key in it, so the lock cannot quietly come back.

### Built manifest has no orientation key

The landscape Playwright project fetches `/manifest.webmanifest` from the preview server and asserts the key is absent from what the browser will actually read.

## Token contrast

`tests/contrast.test.ts` parses `src/styles/tokens.css`, resolves `var()` chains for both themes and checks each role pair on every ground it sits on ([[design#Tokens and theming#Semantic aliases]]). It runs before any build and independently of axe.

`--surface-line` dividers and neutral-900 hairlines are decorative and are not asserted; WCAG 1.4.11 exempts them.

### Secondary text reaches 4.5:1 on every ground

`--text-secondary`, neutral-400 and neutral-500 clear 4.5:1 on the page, the raised, sunken and quiet surfaces and the bloom's peak in both themes; captured rows clear it on their own ground.

### Accent and status text hold in both themes

Accent text on the page and on the accent grounds, the split bar and tag pairs, the locked, missed and soon tones on their grounds and on a raised surface, and the feature card's text at both ends of its glow all clear 4.5:1.

### Control boundaries reach 3:1

`--control-border` and `--chart-missed` clear 3:1 on the grounds controls sit on, as do the accent outline and the switch knob at rest.

## Form rules

`tests/validation.test.ts` covers each rule in [[domain#Form rules]] without the DOM.

### A required field must not be blank

Blank and whitespace-only values return the caller's sentence; any text returns null.

### Money must be a number, and a value must be above zero

Empty, non-numeric and negative amounts fail the money rule; zero passes it. The positive rule also fails zero and passes a cent.

### An anniversary must be a calendar date

Empty, impossible (month 13) and non-ISO dates fail; an ISO date passes.

### An enrolment page must be a web address

Nothing given passes; a bare domain or an ftp scheme fails; http and https pass.

## Snackbar timing

`tests/snackbar.test.tsx` drives the provider with fake timers ([[design#Undo over confirmation]]).

### An undo stays up for twenty seconds

A snackbar with an action is still there at 19 seconds and gone at 21.

### Focus pauses the timer and leaving restarts it

Focusing the Undo button at 5 seconds holds the snackbar through 30; blurring then restarts the full 20, so it is still there at 49 seconds and gone at 51.

### The undo button says what it undoes

An action given an `ariaLabel` renders a button whose accessible name is that label while its visible text stays "Undo".
