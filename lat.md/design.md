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

## Screens

Four tabs, each answering a different question, plus editors and Settings. The tab bar is `src/ui/TabBar.tsx`.

- **Today** (`src/routes/Today.tsx`): one number, a countdown, and the rows behind them. The headline counts only what is claimable; locked credits get their own section ([[domain#Status ladder#Locked is not unclaimed]]). Shows up to three overlaps and the "Preview nudge" button.
- **Credits** (`src/routes/Credits.tsx`): the full ledger, including what Today hides. Four totals, never a mixed sum ([[domain#The four totals]]).
- **Cards** (`src/routes/Cards.tsx`): each card against its fee, with a verdict that leads with an action rather than a score. It refuses to price lounge access or status; putting a number on those would be the one judgement the app should not fake.
- **Value** (`src/routes/Value.tsx`): captured against missed by month, cards ranked worst-first on a percentage-of-fee axis ([[domain#Card value and the cardmember year]]), and the biggest leaks.
- **Add a card** (`src/routes/AddCard.tsx`): pick a product, then say whose it is and when the cardmember year turns over. The holder is asked for, never inferred.
- **Card and benefit editors**: the benefit editor shows the window a cadence and anchor produce, live, because those two fields decide whether a reminder arrives in time and are the ones users most often get wrong.
- **Settings**: reminders, the ladder table, theme, and import/export.

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

## Partial logging

The credit sheet ([[src/ui/CreditSheet.tsx#CreditSheet]]) makes logging a partial amount as easy as logging the whole thing. Quick amounts are a quarter, a half and a round figure, all capped at what is actually left and rounded to whole dollars, because nobody logs $37.53.

## Household filter

[[src/ui/HolderFilter.tsx#HolderFilter]] narrows Today and Credits to one member. A native `<select>` sits invisibly over a styled row so mobile gets the OS picker.

A custom dropdown would be worse in every way that matters: no keyboard accessory, no scroll wheel, no VoiceOver rotor. The control hides itself when there is only one person, because a filter with one option is furniture.

## Accessibility

The shell has a skip link; sheets are `role="dialog"` with `aria-modal`, a focus trap, and focus moved in on open. Deadlines have a screen-reader form ([[src/domain/format.ts#describeDeadline]]) alongside the terse visual one.

Conformance is checked by axe at two levels ([[tests#Accessibility tests]]): in jsdom on every route as part of `npm test`, and in Chromium at four widths and both themes as the `a11y` job of the verify gate.
