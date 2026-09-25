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

`apps/mobile/lib/theme/nocturne_tokens.dart` carries Nocturne's ramps verbatim, as the PWA's `tokens.css` recorded them, plus this app's `--tone-*` and layout additions expressed in Nocturne's vocabulary. Nothing hard-codes a hex.

Theme is a setting (`system`, `light`, `dark`); the app applies it as `MaterialApp.themeMode` ([[mobile-architecture#Theme]]).

### Semantic aliases

Three aliases carry the roles a contrast fix has to reach, so each theme sets them once. Text aliases hold 4.5:1 and control aliases 3:1 on every ground they sit on, pinned by [[mobile-tests#Token contrast]].

`--text-secondary` is screen subtitles, section notes, `.muted`, row sublines and legends. `--control-border` is inputs, buttons, segments and the switch track. `--chart-missed` is the Value chart's missed bar and its swatch. Dark points them at neutral-500 and neutral-600 and leaves Nocturne's ramp verbatim.

### The light ramp

Light has a neutral ramp of its own rather than the dark ramp read in reverse, because the inversion put a 1.85:1 grey on secondary text.

The light steps are blended from the ink to the ground and spaced so 400 to 600 clear 4.5:1 on every surface and 700 clears 3:1 for boundaries. Light also overrides accent-100 and accent-200 to ink, since they are text on the accent grounds (selected segments, the split bar, the skip link).

### Type scale

Every text size is a `--type-*` token in `rem`, so a browser font-size preference reaches all of them (WCAG 1.4.4). The root is the browser's own size; `body` is `--type-base`, 0.9375rem, the 15px the screens were drawn at.

The scale keeps the sizes the screens were drawn at rather than rounding them to a shorter ramp, named by role from `--type-2xs` (9.5px kickers) through `--type-base` to `--type-symbol` (28px). Today's number is `--type-display`, `clamp(2.25rem, 14.5vw, 3.625rem)`, so it is 58px at the design width and shrinks with the viewport instead of forcing a sideways scroll at 320px (WCAG 1.4.10). Icon glyph sizes stay in px. Checked by [[mobile-tests#Text scaling]].

### Glows axe can measure

The bloom behind each screen is the box-shadow of a one-pixel element in `--color-bloom`, and the feature card's section colour is an inset glow rather than a gradient background.

axe cannot judge text over a gradient or under a large pseudo element, and any glow drawn as a shape leaves text straddling its rectangle's edge undecidable, wherever a layout puts it. A shadow has no rectangle, so text is measured against the page, and the token test checks every text colour that can sit in the top of a screen against the bloom's peak instead. The peak is accent-900 at 60% over the page, dim enough that the accent itself clears 4.5:1 on it. A glow box clips the bloom to the content column so it never runs under the navigation rail.

## Screens

Four tabs, each answering a different question, plus editors and Settings.

- **Today**: one number, a countdown, and the rows behind them. The headline counts only what is claimable; locked credits get their own section ([[domain#Status ladder#Locked is not unclaimed]]). Shows up to three overlaps.
- **Credits**: the full ledger, including what Today hides. Four totals, and an opted-out figure per year once anything is opted out, never a mixed sum ([[domain#The five totals]]).
- **Cards**: each card against its fee, with a verdict that leads with an action rather than a score. It refuses to price lounge access or status; putting a number on those would be the one judgement the app should not fake.
- **Value**: captured against missed by month, cards ranked worst-first on a percentage-of-fee axis ([[domain#Card value and the cardmember year]]), and the biggest leaks.
- **Add a card**: pick a product, then say whose it is and when the cardmember year turns over. The holder is asked for, never inferred.
- **Card and benefit editors**: the benefit editor shows the window a cadence and anchor produce, live, because those two fields decide whether a reminder arrives in time and are the ones users most often get wrong.
- **Settings**: reminders, the ladder table, theme, and import/export.

### Forms and errors

Validation is inline and announced, never silent (WCAG 3.3.1 to 3.3.3). `Field` wraps a labelled control with a hint and an error slot; the control gets `aria-invalid` and `aria-describedby`, and the error text says what to enter.

Errors show once a field has been left or the form submitted, never on the first keystroke. Save buttons are never disabled: pressing Save with an invalid form shows the errors and focuses the first invalid control. Required fields carry `required` and a `*` explained once above the form. The rules are pure functions in [[domain#Form rules]]; the live editors keep what was typed in a draft and only write valid values to the store.

## Undo over confirmation

Logging a credit is the app's main destructive-feeling action and far more common than correcting one. So the flow is optimistic: the claim is written immediately and the snackbar offers to take it back, rather than asking "are you sure?" every time.

`CreditActions` is shared by every list that renders a row, so a swipe behaves identically to the same action taken from the sheet, and every logged claim and every mute toggle returns an Undo through `SnackbarState`.

There are two ways back, so undo is never a race against a clock (WCAG 2.2.1):

- **The snackbar.** An undo stays up for twenty seconds, not Material's six. The clock stops while the pointer or keyboard focus is on the snackbar and restarts in full when they leave. The Undo button's accessible name says what it undoes ("Undo logging Uber Cash"), since the visible word alone does not.
- **The sheet.** The credit sheet lists everything logged this period under "Logged this period", newest first, each with a Remove that deletes that one claim (`AppStore.removeClaim`). This is the path that needs no timer at all.

## Partial logging

The credit sheet (`CreditSheet`) makes logging a partial amount as easy as logging the whole thing. Quick amounts are a quarter, a half and a round figure, all capped at what is actually left and rounded to whole dollars, because nobody logs $37.53.

## Household filter

The app has no household filter. Cards carry a label instead of a holder, so there is no member to filter Today or Credits by, and sign-in brings real members ([[domain#Card]]).

The retired PWA had one: a holder filter narrowing Today and Credits to one member, a native `<select>` over a styled row so mobile got the OS picker, hidden when there was only one person.

## Responsive layout

Three width classes, Material's compact, medium and expanded, decide the navigation and the content column on every client. The phone design is the compact class; the wider ones re-flow it and never re-order it.

| Class | Width | Content column | Screen padding | Navigation |
| --- | --- | --- | --- | --- |
| Compact | under 600 | 402 | 20 | bottom tab bar |
| Medium | 600 to 1023 | 560 | 24 | rail, icons over labels, 80 wide |
| Expanded | 1024 and up | 720 | 28 | rail, labels beside icons, 200 wide |

Units are CSS pixels in the PWA and logical pixels in Flutter, which are the same size on a device. From medium the column is centred beside the rail and is the only thing that scrolls; the tab bar and the rail are the same four destinations in the same order. Today pairs its overlap cards from medium and splits into two columns from expanded, with the headline across both; Cards go two across from medium and one wide row each from expanded; editors pair short fields from expanded. Reading order and focus order are the phone's at every width.

Orientation is never locked, and a landscape phone keeps the compact class with the short-viewport form under *Accessibility*. The app realises the classes in [[mobile-architecture#Responsive layout]].

## Accessibility

The product targets WCAG 2.2 AA. The PWA is measured against it directly; the Flutter app carries the same requirements in platform terms ([[mobile-architecture#Accessibility]]), because the standard is written for the web but its intent is not.

Every client must: re-flow to the width classes above with nothing scrolling sideways (1.4.10); let text follow the platform size preference to 200% without clipping or overlap (1.4.4); keep text at 4.5:1 and controls at 3:1 against every ground they sit on, from the same tokens (1.4.3, 1.4.11); never lock orientation (1.3.4); give every gesture a keyboard, switch or screen-reader route (2.5.1, 2.1.1); and offer undo rather than confirmation (2.2.1).

The shell has a skip link; sheets are `role="dialog"` with `aria-modal`, a focus trap, and focus moved in on open. Deadlines have a screen-reader form (`describeDeadline`) alongside the terse visual one.

Every screen has exactly one level-one heading and a window title of its own ([[mobile-tests#Routing#Every route has exactly one heading and its title]]). Today's heading is visually hidden behind the logotype, which is decoration with an empty `alt`.

Orientation is never locked. Under 480px of height, a phone on its side, the shell drops the bloom and most of its top padding, the tab bar goes icon-only with the labels kept for screen readers, Today's number steps down to 40px, and sheets cap at 85% of the height so a strip of the screen stays visible behind them.

### Pointer accelerators and their keyboard routes

Every gesture is an accelerator with a keyboard route, proved by [[mobile-tests#Swipe row]].

| Pointer only | Keyboard route |
| --- | --- |
| Swipe a row right to log the whole credit | Enter on the row opens the sheet; "Mark the full … used" logs it |
| Swipe a row left to silence it | The bell button on every row, or "Silence this credit" in the sheet |
| Drag the sheet's handle to dismiss | Escape, or the Close button |
| Tap the scrim to close a sheet | Escape |
