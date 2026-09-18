# PWA tests

What the reference PWA's own suites guard beyond the product spec in [[tests]]: the store's reactive wiring, accessibility in jsdom and Chromium, the manifest, token contrast and snackbar timing.

Vitest runs in jsdom under `apps/pwa/tests/` as part of `npm test`; Playwright runs against the built app with `npm run test:e2e`.

## The store

`apps/pwa/tests/store.test.tsx` mounts the real `AppProvider` so memos recomputing after a mutation are covered along with the mutations ([[architecture#The app store]]).

- Adding a card from a template brings its credits and enrolment flags, and records the holder so two identical cards stay apart.
- Claiming defaults to the balance left, never the face value again; unclaiming clears the whole cycle.
- Enrolment unlocks a credit and can be revoked. Muting a credit or a card changes `muted` without moving status.
- Deleting a card removes its credits and claims and leaves the other holder untouched.
- Export and import round-trip the dataset; a file that is not an export is refused.

### Removing one claim leaves the rest

Two claims against the same cycle; removing the first by id leaves the second, so the sheet's Remove never takes more than the row it sits on.
- Every catalogue template gives each credit an icon and a positive value.

## Accessibility tests

Two axe gates for epic #21: `apps/pwa/tests/a11y/` runs in jsdom as part of `npm test`, and `apps/pwa/tests/e2e/` runs Playwright against the built app with `npm run test:e2e`. Both read one allowlist.

Both suites render every route with the sample household from `samples/sample-household.json`, so what axe sees is a populated screen rather than an empty state. `apps/pwa/tests/a11y/allowlist.ts` names each rule currently disabled and the sub-issue that removes it; a sub-issue is not done until its entries are gone. The rule set is WCAG 2.1 A and AA plus axe's best practices.

`apps/pwa/tests/a11y/mount.tsx` mounts the real shell ([[apps/pwa/src/App.tsx#Shell]]) and route table ([[apps/pwa/src/App.tsx#routes]]) on a memory router, so a screen is judged inside the same landmarks, sheets and tab bar it ships with.

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

`apps/pwa/tests/a11y/navigation.test.tsx` renders each of the nine routes and expects `document.title` to be the screen's name followed by ` · HelpMe Reward`; the editors use the card label and the credit name.

### Navigation moves focus to the new heading

Moving the memory history from Cards to Add a card places `document.activeElement` on the Add a card `<h1>`, and going back places it on the Cards `<h1>`.

### A tab press keeps focus on the tab

Pressing the Credits tab with focus on it renders Credits and leaves focus on the tab, since the user is still on the control they pressed.

### Submitting with a blank holder shows a linked error

`apps/pwa/tests/a11y/forms.test.tsx` picks a catalogue card, clears the holder and presses Save, which is not disabled.

The error sentence appears, the input carries `aria-invalid="true"` and an `aria-describedby` naming the error, and focus lands on the input.

### Correcting the field clears the error and saves

Typing a holder removes the error and `aria-invalid`, and pressing Save again adds the card with that holder.

### The sheet lists claims with a Remove

`apps/pwa/tests/a11y/credit-sheet.test.tsx` logs the full balance from the sheet, reopens it, finds the claim under "Logged this period" and presses Remove; the balance returns to what it was and the row is gone.

### Nothing scrolls sideways at 320px

`apps/pwa/tests/e2e/reflow.spec.ts`, on the 320px project, loads every route and asserts neither the document nor `#main` can scroll sideways, then repeats that on Today with the credit sheet and the compare sheet open (WCAG 1.4.10).

### Text spacing overrides clip nothing

The same spec injects WCAG 1.4.12's overrides and asserts no element with hidden overflow has content taller than itself, `.truncate` and `.visually-hidden` excepted, and that nothing scrolls sideways.

The overrides are line height 1.5, paragraph spacing 2em, letter spacing 0.12em and word spacing 0.16em. A screenshot of each route is attached to the report for review.

### Body text follows the browser font size

`apps/pwa/tests/e2e/large-type.spec.ts` sets the root font size to 24px, which is what the browser preference changes, and expects body text to measure 22.5px: the rem scale following the root (WCAG 1.4.4).

### Controls keep clear of each other at 24px

At the same root size, the bounding boxes of the visible controls on Today and the benefit editor do not overlap and the page does not scroll sideways.

### The phone layout does not move

`apps/pwa/tests/e2e/shell.spec.ts` at 320 and 402px compares the boxes of the main column, tab bar, tabs, heading, first row and other landmarks on every route against `apps/pwa/tests/e2e/layout-baseline.json`.

The baseline was taken from develop before the responsive work. Positions and heights may drift a pixel, widths four, since shrink-to-fit text rasterises slightly wider on Linux than on macOS.

`UPDATE_LAYOUT_BASELINE=1` rewrites the file when a change to the phone layout is intended.

### The rail and the centred column at wider widths

At 768 and 1280px the main navigation starts at the leading edge, is 80 or 200px wide and full height, the content column is 560 or 720px wide and centred beside the rail, and the four tabs are reached by Tab in order.

### The sheet is a dialog from 600px

`apps/pwa/tests/a11y/sheet.test.tsx` mocks the 600px media query: the open credit sheet then renders no grip and carries no drag transform, and focus moves inside.

Without the mock the grip and the transform are there. `apps/pwa/tests/e2e/sheets.spec.ts` at 768px checks the panel is centred and at most 480px wide.

### The sheet still drags on a phone

At 402px a slow 60px drag on the grip springs back and a slow 130px drag dismisses, so the distance threshold is unchanged.

### The credit panel sits beside the list

At 1280px opening a credit shows the panel on the trailing edge at full height with the list column ending where it starts; Escape closes it and focus returns to the row that opened it.

### Wider screens use the column

`apps/pwa/tests/e2e/screens.spec.ts` on the 768 and 1280px shell projects asserts the layouts in [[interaction#Responsive layout#What each screen does with the width]].

Those are paired overlap cards, the two-column card grid, the locked section and the verdict beside their rows, and paired editor fields with a full-width text area.

It also screenshots each route and attaches it to the report; `UPDATE_SCREENSHOTS=1` writes them to `apps/pwa/tests/e2e/screenshots/` for review in a pull request. They are review references, not a pixel gate: CI rasterises fonts differently from a Mac.

### Reading order is the same at every width

On the 1280px project the sequence of headings and row titles on Today is read, the viewport is resized to 402px, and the sequence is read again and must be identical.

### Every control keeps a boundary in forced colours

`apps/pwa/tests/e2e/forced-colors.spec.ts` runs with Chromium's forced-colours emulation and, on every route and with the credit sheet open, lists any visible control whose border is zero on all four sides; the list must be empty.

Controls are buttons, inputs, selects, text areas, switches and the switch knob.

The off-screen file input, the sheet's scrim and a row's main button (which fills its bordered card) are excluded on purpose. A screenshot per route is attached to the report.

### Tab and Enter alone complete the five actions

`apps/pwa/tests/e2e/keyboard.spec.ts` starts each flow at the skip link and uses only Tab and Enter.

The flows: log a claim through the sheet with focus back on a row afterwards, silence a credit from its bell with focus still on it, add a catalogue card, toggle a benefit's tracking switch, and switch the theme to light.

### Every route passes axe in a real browser

Each route at each of the four widths and two themes has no axe violation and, unlike the jsdom suite, no *incomplete* result either.

An undecided check that nobody reviews is treated as a failure, which is what makes the contrast entry in the allowlist honest.

## PWA manifest

The manifest must not lock orientation ([[architecture#PWA manifest]], WCAG 1.3.4). Checked twice: on the source before a build exists, and on the built file.

### Manifest sets no orientation

`apps/pwa/tests/manifest.test.ts` reads `vite.config.ts` and fails on any `orientation:` key in it, so the lock cannot quietly come back.

### Built manifest has no orientation key

The landscape Playwright project fetches `/manifest.webmanifest` from the preview server and asserts the key is absent from what the browser will actually read.

## Token contrast

`apps/pwa/tests/contrast.test.ts` parses `apps/pwa/src/styles/tokens.css`, resolves `var()` chains for both themes and checks each role pair on every ground it sits on ([[design#Tokens and theming#Semantic aliases]]). It runs before any build and independently of axe.

`--surface-line` dividers and neutral-900 hairlines are decorative and are not asserted; WCAG 1.4.11 exempts them.

### Secondary text reaches 4.5:1 on every ground

`--text-secondary`, neutral-400 and neutral-500 clear 4.5:1 on the page, the raised, sunken and quiet surfaces and the bloom's peak in both themes; captured rows clear it on their own ground.

### Accent and status text hold in both themes

Accent text on the page and on the accent grounds, the split bar and tag pairs, the locked, missed and soon tones on their grounds and on a raised surface, and the feature card's text at both ends of its glow all clear 4.5:1.

### Control boundaries reach 3:1

`--control-border` and `--chart-missed` clear 3:1 on the grounds controls sit on, as do the accent outline and the switch knob at rest.

## Snackbar timing

`apps/pwa/tests/snackbar.test.tsx` drives the provider with fake timers ([[design#Undo over confirmation]]).

### An undo stays up for twenty seconds

A snackbar with an action is still there at 19 seconds and gone at 21.

### Focus pauses the timer and leaving restarts it

Focusing the Undo button at 5 seconds holds the snackbar through 30; blurring then restarts the full 20, so it is still there at 49 seconds and gone at 51.

### The undo button says what it undoes

An action given an `ariaLabel` renders a button whose accessible name is that label while its visible text stays "Undo".
