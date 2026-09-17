# Design and interaction

The screens come from the Nocturne design system, with Material Design supplying the mobile ergonomics Nocturne does not cover.

Every colour, space, radius and duration resolves to a token, so re-theming is a token swap rather than a sweep through components.

## Nocturne and Material

Where the two disagree on looks, Nocturne wins; where they disagree on touch behaviour, Material wins.

Nocturne's rules, followed by every component:

- A near-neutral blue-grey ground, Inter at medium weight, 8px radii, and a compact 0.7× density using the `--space-*` steps.
- A single blurple accent used as a line and a glow, never a flood. Primary actions are an accent *outline*, never a fill.
- Contrast comes from tonal ramps, not saturation. There is no alarm red: urgency is a saturated indigo ground and a filled glyph. The one sanctioned saturated ground is `--color-section`, used for the overlap cards.

Material supplies: 48px minimum touch targets, swipe actions, bottom-sheet behaviour, state layers and motion curves.

## Tokens and theming

`src/styles/tokens.css` carries Nocturne's ramps verbatim from the vendored copy under `design-reference/_ds/`, plus this app's `--tone-*` and layout additions expressed in Nocturne's vocabulary. Nothing hard-codes a hex.

Theme is a setting (`system`, `light`, `dark`). The shell stamps `data-theme` on the document element ([[architecture#The shell and routing]]); the token sheet's `[data-theme]` selectors do the rest.

### Semantic aliases

Three aliases carry the roles a contrast fix has to reach, so each theme sets them once. Text aliases hold 4.5:1 and control aliases 3:1 on every ground they sit on, pinned by [[tests#Token contrast]].

`--text-secondary` is screen subtitles, section notes, `.muted`, row sublines and legends. `--control-border` is inputs, buttons, segments and the switch track. `--chart-missed` is the Value chart's missed bar and its swatch. Dark points them at neutral-500 and neutral-600 and leaves Nocturne's ramp verbatim.

### The light ramp

Light has a neutral ramp of its own rather than the dark ramp read in reverse, because the inversion put a 1.85:1 grey on secondary text.

The light steps are blended from the ink to the ground and spaced so 400 to 600 clear 4.5:1 on every surface and 700 clears 3:1 for boundaries. Light also overrides accent-100 and accent-200 to ink, since they are text on the accent grounds (selected segments, the split bar, the skip link).

### Type scale

Every text size is a `--type-*` token in `rem`, so a browser font-size preference reaches all of them (WCAG 1.4.4). The root is the browser's own size; `body` is `--type-base`, 0.9375rem, the 15px the screens were drawn at.

The scale keeps the sizes the screens were drawn at rather than rounding them to a shorter ramp, named by role from `--type-2xs` (9.5px kickers) through `--type-base` to `--type-symbol` (28px). Today's number is `--type-display`, `clamp(2.25rem, 14.5vw, 3.625rem)`, so it is 58px at the design width and shrinks with the viewport instead of forcing a sideways scroll at 320px (WCAG 1.4.10). Icon glyph sizes stay in px. Checked by [[tests#Accessibility tests#Body text follows the browser font size]].

### Glows axe can measure

The bloom behind each screen is a solid, blurred ellipse in accent-900, and the feature card's section colour is an inset glow rather than a gradient background.

axe cannot judge text over a gradient or under a large pseudo element; over a solid colour it measures against the glow's peak, which the token test pins too.

## Screens

Four tabs, each answering a different question, plus editors and Settings. The tab bar is `src/ui/TabBar.tsx`.

- **Today** (`src/routes/Today.tsx`): one number, a countdown, and the rows behind them. The headline counts only what is claimable; locked credits get their own section ([[domain#Status ladder#Locked is not unclaimed]]). Shows up to three overlaps and the "Preview nudge" button.
- **Credits** (`src/routes/Credits.tsx`): the full ledger, including what Today hides. Four totals, never a mixed sum ([[domain#The four totals]]).
- **Cards** (`src/routes/Cards.tsx`): each card against its fee, with a verdict that leads with an action rather than a score. It refuses to price lounge access or status; putting a number on those would be the one judgement the app should not fake.
- **Value** (`src/routes/Value.tsx`): captured against missed by month, cards ranked worst-first on a percentage-of-fee axis ([[domain#Card value and the cardmember year]]), and the biggest leaks.
- **Add a card** (`src/routes/AddCard.tsx`): pick a product, then say whose it is and when the cardmember year turns over. The holder is asked for, never inferred.
- **Card and benefit editors**: the benefit editor shows the window a cadence and anchor produce, live, because those two fields decide whether a reminder arrives in time and are the ones users most often get wrong.
- **Settings**: reminders, the ladder table, theme, and import/export.

### Forms and errors

Validation is inline and announced, never silent (WCAG 3.3.1 to 3.3.3). [[src/ui/Field.tsx#Field]] wraps a labelled control with a hint and an error slot; the control gets `aria-invalid` and `aria-describedby`, and the error text says what to enter.

Errors show once a field has been left or the form submitted, never on the first keystroke. Save buttons are never disabled: pressing Save with an invalid form shows the errors and focuses the first invalid control. Required fields carry `required` and a `*` explained once above the form. The rules are pure functions in [[domain#Form rules]]; the live editors keep what was typed in a draft and only write valid values to the store.

## Swipe rows

Every credit row is reachable three ways: tap to open the sheet, swipe right to log the whole credit, swipe left to silence it. The swipe is an accelerator, never the only route, because a gesture nobody discovers is not a feature.

[[src/ui/SwipeRow.tsx#SwipeRow]] implements Material's swipe-to-act with the behaviours that make it usable on a phone:

- **Direction locking.** The gesture only becomes a swipe once horizontal movement clearly beats vertical (10px), so a fast flick down the list never half-opens a row. Pointer capture happens only after the swipe is committed, so scrolling is never stolen.
- **Rubber-banding** past the 84px action width.
- **Commit on velocity or distance:** past 55% of the width, or a flick over 0.45 px/ms.
- **A visible resting state.** Releasing past the threshold parks the row open with the button exposed rather than firing. An irreversible action should not be one accidental flick away.
- Mouse input is ignored on purpose; a tap anywhere else closes an open row.

## Bottom sheets

[[src/ui/Sheet.tsx#Sheet]] is a modal sheet with Material's behaviour on Nocturne's surfaces: a drag handle that actually drags, dismissal by distance (110px) or by downward flick (0.5 px/ms), a scrim that closes on tap, Escape to close, and a focus trap.

The drag listens on the handle only. Dragging from anywhere would fight the sheet's own scrolling, which matters because the credit sheet is taller than the screen. Body scroll is locked while open and focus is returned on close.

## Undo over confirmation

Logging a credit is the app's main destructive-feeling action and far more common than correcting one. So the flow is optimistic: the claim is written immediately and the snackbar offers to take it back, rather than asking "are you sure?" every time.

[[src/ui/useCreditActions.ts#useCreditActions]] is shared by every list that renders a row, so a swipe behaves identically to the same action taken from the sheet, and every logged claim and every mute toggle returns an Undo through [[src/ui/Snackbar.tsx#useSnackbar]].

There are two ways back, so undo is never a race against a clock (WCAG 2.2.1):

- **The snackbar.** An undo stays up for twenty seconds, not Material's six. The clock stops while the pointer or keyboard focus is on the snackbar and restarts in full when they leave. The Undo button's accessible name says what it undoes ("Undo logging Uber Cash"), since the visible word alone does not.
- **The sheet.** The credit sheet lists everything logged this period under "Logged this period", newest first, each with a Remove that deletes that one claim ([[src/stores/app.tsx#AppProvider]]'s `removeClaim`). This is the path that needs no timer at all.

## Partial logging

The credit sheet ([[src/ui/CreditSheet.tsx#CreditSheet]]) makes logging a partial amount as easy as logging the whole thing. Quick amounts are a quarter, a half and a round figure, all capped at what is actually left and rounded to whole dollars, because nobody logs $37.53.

## Household filter

[[src/ui/HolderFilter.tsx#HolderFilter]] narrows Today and Credits to one member. A native `<select>` sits invisibly over a styled row so mobile gets the OS picker.

A custom dropdown would be worse in every way that matters: no keyboard accessory, no scroll wheel, no VoiceOver rotor. The control hides itself when there is only one person, because a filter with one option is furniture.

## Accessibility

The shell has a skip link; sheets are `role="dialog"` with `aria-modal`, a focus trap, and focus moved in on open. Deadlines have a screen-reader form ([[src/domain/format.ts#describeDeadline]]) alongside the terse visual one.

Every screen has exactly one `<h1>` and a document title of its own ([[architecture#The shell and routing#Titles and focus]]). Today's heading is visually hidden behind the logotype, which is decoration with an empty `alt`.

Text is truncated with `.truncate` only where the full text is one tap away: a credit row's title opens the sheet that shows the whole name, a benefit link opens its editor, and the household filter's label sits over a native select. Subtitles, leak labels and screen titles wrap instead, so WCAG 1.4.12's spacing overrides lose nothing ([[tests#Accessibility tests#Text spacing overrides clip nothing]]).

Orientation is never locked. Under 480px of height, a phone on its side, the shell drops the bloom and most of its top padding, the tab bar goes icon-only with the labels kept for screen readers, Today's number steps down to 40px, and sheets cap at 85dvh so a strip of the screen stays visible behind them ([[tests#Accessibility tests#Landscape keeps the first row on screen]]).

Conformance is checked by axe at two levels ([[tests#Accessibility tests]]): in jsdom on every route as part of `npm test`, and in Chromium at four widths and both themes as the `a11y` job of the verify gate.
