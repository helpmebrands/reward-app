# Mobile tests

What the Flutter widget suites in `apps/mobile/test/` guard, run by the `flutter` job of the verify gate ([[deployment#Pipeline]]).

## Theme

`theme_test.dart` pins the theme to the Nocturne tokens so a re-theme is a deliberate token change rather than drift ([[mobile-architecture#Theme]]).

### Both themes carry the Nocturne token colours

Each theme's primary, surface, on-surface and scaffold colours are the `tokens.css` values for its mode, and each carries its token set as the extension.

Dark: `#9184d9`, `#232532`, `#e9e9ed`, `#161826`. Light: `#5d5294`, `#ffffff`, `#232532`, `#f3f5fe`.

### The app follows the platform brightness

With the platform reporting dark, the running app resolves the dark accent as primary and the dark "use soon" ground from the extension, so the system setting is what picks the theme.

## Today

`today_screen_test.dart` renders the screen over the PWA's sample household with today fixed at 16 September 2026 and compares it with what the PWA shows for that date ([[mobile-architecture#Today screen]]).

The expected rows are `test/fixtures/sample-today.json`, dumped by `apps/pwa/scripts/today-snapshot.ts`.

### The sample household renders the PWA's rows, order and tones

Every `CreditRow` on the screen, in order, has the name, holder, tone and amount of the PWA's use-soon, locked and captured rows for that date, so the two apps agree on what is at risk and how it is drawn.

### The headline counts only what is claimable

The headline digits are the claimable total from the fixture, the subtitle names the nearest reset, and the section titles carry the reset date and the captured total.

### Overlaps show the three largest

The three largest overlaps from the fixture appear as cards with their label, count and combined unclaimed value.

### Medium pairs the overlap cards

`today_layout_test.dart` renders Today bare inside a `WidthClassScope`. At medium the first two overlap cards share a top edge and sit side by side and the third starts a new row under the first; at compact they stack.

### Expanded splits the body in two under the headline

At expanded the headline block spans the full inner width, the use-soon and captured titles start at the left padding, the locked title starts past the centre on the same line as use-soon, and the first credit row ends before the centre.

### The screen reader hears the phone order at every width

The labels of the semantics tree in traversal order at expanded are exactly the labels at compact, so the two-column layout does not change what is read or in what sequence.

### A fresh install shows the first-run screen

With no snapshot the screen shows "Start with one card" and no rows.

## Today interactions

`today_interactions_test.dart` pumps the whole app at 402 wide over the sample household, dated 16 September 2026, with the ui state injected, and drives Today the way a user does ([[mobile-architecture#Today screen#Today's interactions]]).

### A row opens the sheet and logging moves it to captured

Tapping Kathy's Resy row opens its sheet; "Mark the full $100 used" closes it, drops the headline from $1,658.90 to $1,558.90, draws that row in the captured tone and shows the undo snackbar.

### Swiping a row logs it with an undo

A 60 pixel swipe on the same row and a tap on "Log it" drops the headline the same way, and "Undo logging Resy Dining Credit" restores it.

### The household filter narrows the screen

The filter reads "Everyone in the household"; choosing Jim writes the setting, leaves only Jim's rows, and the headline becomes the claimable total of Jim's instances.

### One holder has no filter

With only Jim's card and benefits the filter is not rendered.

### An overlap card opens the compare sheet

Tapping "Hotel Credit (FHR / THC) × 2" opens the compare sheet with Jim's and Kathy's sides, "Both sides are untouched at $300", and a log button per side; "Log $300 on Jim's card" closes it and records a $300 claim on Jim's hotel credit.

### A compare side opens that credit

Tapping Kathy's side closes the compare and opens the credit sheet for Kathy's hotel credit.

### Preview nudge shows the stand-in when nothing is scheduled

With reminders off, "Preview nudge" shows "$1,658.90 on the line — one week left" and its body, and the preview is gone seven seconds later.

### Preview nudge shows the next scheduled reminder

With reminders on, the preview is the first reminder `buildSchedule` produces after the clock, by id, title and body; "Dismiss preview" clears it.

## Shell

`shell_test.dart` pumps the app at 402, 768 and 1280 logical pixels wide over the sample household and checks the width class the shell realises ([[mobile-architecture#Responsive layout]], [[mobile-architecture#Navigation]]).

### Compact keeps the phone layout

At 402 wide the four destinations are a `NavigationBar` in the order Today, Credits, Cards, Value, the content column is the full 402, and Today's list is padded 20.

### Medium shows the rail beside a 560 column

At 768 wide the destinations are an 80-wide, full-height `NavigationRail` with icons over labels at the leading edge, in the same order; the column is 560 wide, centred in the space beside the rail, and padded 24.

### Expanded extends the rail beside a 720 column

At 1280 wide the rail is 200 wide and extended, the column is 720 wide and centred beside it, the padding is 28, and the destination order is unchanged.

### A destination opens its branch

Choosing Cards from the bar, or Value from the rail, shows that branch's placeholder screen and selects its index, so the shell and the router are wired together.

## Text scaling

`text_scale_test.dart` carries WCAG 1.4.4 into Flutter terms ([[mobile-architecture#Accessibility]]): the platform text scale is honoured and Today survives 200% on a phone-width viewport.

### No widget overrides the platform text scale

No Dart file under `lib/` mentions `textScaler` or `textScaleFactor`, so nothing caps or ignores the user's size preference.

### Today at 200% neither overflows nor clips

Today over the sample household at a 2.0 platform text scale and 402 wide raises no `RenderFlex` overflow, no paragraph exceeds its maximum lines, and every text's painted rectangle lies inside the viewport width.

### Controls and text do not overlap at 200%

At the same scale no two credit rows and no two texts overlap, so nothing draws over anything else; a text inside its own row is the one permitted nesting.

### The headline shrinks to fit at 200%

The headline number's painted width at 2.0 is smaller than its natural width and its right edge stays inside the padded column, so it scales down rather than overflowing.

## Token contrast

`contrast_test.dart` computes WCAG ratios over the theme extension's token set for light and dark, the way `apps/pwa/tests/contrast.test.ts` does over `tokens.css`, so a copied token cannot drift ([[mobile-architecture#Accessibility]], [[pwa-tests#Token contrast]]).

The tone lines around rows and the surface lines are decorative and are not asserted; WCAG 1.4.11 exempts them.

### Secondary text reaches 4.5:1 on every ground

`textSecondary` clears 4.5:1 on the page, the raised, sunken and quiet surfaces and the captured row's ground in both modes.

### Control boundaries reach 3:1

`controlBorder` clears 3:1 on the same five grounds in both modes.

### Each tone's text holds on its own ground

The soon, available, locked, captured and missed foregrounds each clear 4.5:1 on their own ground in both modes.

### The overlap card's text holds on the section ground

Today is rendered in each theme and every `Text` inside an overlap card is read back with its own style colour; each clears 4.5:1 on the section ground.

The light theme's secondary text does not clear it there, which is why the card's body is neutral-300 as in the PWA.

## Store

`snapshot_store_test.dart` covers persistence and the app store ([[mobile-architecture#The snapshot store]], [[mobile-architecture#The store]]).

### A snapshot round-trips through shared preferences

Saving the sample household and loading it back yields equal JSON, under the `app-data` key.

### A corrupt snapshot starts the app empty

A record that is not JSON loads as null rather than throwing.

### The app store resolves today's instances

After `load` the store reports its cards, the first use-soon credit, the claimable total and the next reset for the fixed date, all from the domain selectors.

`app_store_test.dart` is the mutation suite ([[mobile-architecture#The store#Mutations]]): plain Dart over a `MemorySnapshotStore` with the clock fixed at 16 September 2026, counting notifications. After every mutation the saved snapshot and the store's snapshot are the same JSON, so a write that skipped the store would fail every case.

### A template becomes a card with its credits

`addCardFromTemplate` on an empty household adds one card with the template's issuer and product, the given holder, nickname and anniversary, and one benefit per template credit; one notification.

Both card timestamps are the clock's instant, and each benefit has a distinct id and the new card's id.

### A blank template takes the typed issuer and product

The blank template with `issuer` and `product` overrides yields a card named by them with no benefits, and its anniversary defaults to today.

### Card patches stamp updatedAt

`updateCard` applies the `copyWith` patch (nickname, last four), keeps `createdAt` and stamps `updatedAt` with the clock; one notification.

### Mute and archive are card patches

`toggleCardMute` flips `muted` each call and `archiveCard` sets `archived`, after which `hasCards` is false; three calls, three notifications.

### Deleting a card cascades

With two cards, three benefits and three claims, `deleteCard` leaves the other card, its benefit and its claim only; one notification.

### A benefit draft gets its identity from the store

`addBenefit` keeps the draft's fields but replaces its id and sets both timestamps to the clock's instant, appending it after the existing benefits.

### Benefit patches stamp updatedAt

`updateBenefit` applies a name and value patch and stamps `updatedAt`; `toggleBenefitMute` flips `muted`; two notifications.

### Enrolment is confirmed and revoked

On a benefit that requires enrolment, `confirmEnrollment` stamps `enrolledAt` and the credit leaves the locked list; `revokeEnrollment` clears it to null and the credit is locked again.

### Deleting a benefit takes its claims

`deleteBenefit` removes the benefit and its claims and leaves the other benefit's claim.

### A claim defaults to what is left

On a $25 credit with $10 claimed, `claim` without an amount records $15 with the note, the instance's benefit id and cycle key, and the clock's instant, and the instance becomes captured.

### A partial claim records its amount

`claim` with an amount records that amount with no note, and the instance's remaining value drops by it.

### Removing one claim keeps the cycle's others

`removeClaim` deletes one claim and leaves the cycle's other claim and the older cycle's; `unclaim` then clears the whole cycle and leaves the older one.

### Settings patches keep the rest

`updateSettings` changes the holder filter and theme and keeps the horizon; `updateNotificationSettings` turns reminders on at a new time, keeps the floor, and leaves the holder filter as set.

### A write before load wins

With a snapshot store whose load is held open, `addCardFromTemplate` lands first; when the load resolves the store still holds the new card, that card is what was saved, and `loading` is false, with one notification per event.

## UI state

`ui_state_test.dart` covers the transient ui notifier as plain Dart ([[mobile-architecture#State management#UI state]]).

### Sheets track an id and notify once

Opening a credit sets the benefit id and notifies once, opening another replaces it, closing clears it, and closing an already closed sheet notifies nobody.

### The compare sheet and the nudge are the other two

The overlap label and the nudge reminder are opened and cleared the same way, one notification each.

## Credit sheet

`credit_sheet_test.dart` opens the sheet through `UiState` on a household with a $100 Resy credit ($10 then $20 logged), a locked Equinox credit and a captured Uber credit, dated 16 September 2026 ([[mobile-architecture#The credit sheet]]).

It checks the content, the actions and the presentation at 402, 800 and 1280.

### Quick amounts are a quarter and a half in whole dollars

`quickAmounts` gives $25 and $50 for $100, $23 and $45 for $90, $4 and $8 for $15, and $2 and $3 for $6, each rounded to whole dollars.

### Quick amounts never reach the remainder

Nothing for $0 or under $5; every amount is a whole dollar, at least $1, and below the remainder.

### The sheet shows the live balance

Opening by id shows $70 left of $100, the full-amount button and the $18 and $35 quick amounts; after a $20 claim through the store the sheet, still open, shows $50 with $13 and $25.

### Marking the full amount logs the remainder and closes

"Mark the full $70 used" records a $70 claim and closes the sheet.

### A quick amount logs that amount

Tapping $35 records a $35 claim.

### A custom amount is capped at what is left

"Other…" reveals the amount field; "lots" shows "Enter an amount in dollars." and records nothing; "500" records $70, the remainder.

### Logged this period lists newest first and removes one

The two claims appear newest first, $20 above $10; "Remove the $20 logged on Sep 10" leaves only the $10 claim and the balance reads $90.

### Silence and last call are switches on the sheet

The switch labelled "Silence reminders for …" mutes the benefit and "Last call only for …" sets `lastCallOnly`.

### A locked credit unlocks from the sheet

A locked credit shows the "Not enrolled." note and no logging; "I've enrolled — unlock this credit" stamps `enrolledAt` and the full-amount button appears.

### A captured credit can be undone

A captured credit shows "Fully captured." with Undo, which clears the cycle's claims and brings the logging section back.

### Compact is a bottom sheet with a scrim

At 402 the sheet is a `BottomSheet` over the scrim, full width, flush with the bottom edge and shorter than the screen.

### Medium is a centred dialog

At 800 it is a `Dialog`, at most 480 wide and 85% of the height, centred on the window.

### Expanded is a side panel beside a usable list

At 1280 there is no bottom sheet, dialog or scrim; the sheet is 380 wide, full height, on the trailing edge, the content column ends before it, and choosing Credits from the rail switches tabs with the sheet still open.

### Escape and back close the sheet

Escape closes the dialog; reopened, the system back is handled and closes it again.

### Every control on the sheet has a label

Walking the sheet's semantics, every button, text field and switch has a label or a tooltip.

### The sheet is a modal route that takes and returns focus

`SheetHost` alone: with a focused node on the screen behind, opening yields a node with `scopesRoute` and `namesRoute` labelled with the title, focus moves inside the sheet, and closing hands focus back to that node.

## Swipe row

`swipe_row_test.dart` pumps a list of interactive `CreditRow`s at 402 wide, twelve open credits so the list scrolls and one captured, recording which callbacks fire, and measures how far each row's content has slid ([[mobile-architecture#The swipe row]]).

### A drag right parks the row open on Log

A 60 pixel drag right parks the row at the 84 pixel action width with "Log it" tappable and nothing logged; tapping it logs once and closes the row; opened again, a tap on another row closes it without logging.

### A short drag springs back

A 40 pixel drag, under 55% of the width, springs back to rest and logs nothing.

### A vertical drag scrolls the list

A drag of 6 across and 40 down scrolls the list and leaves the row at rest.

### A flick commits before the distance

A 30 pixel fling at 1200 pixels per second parks the row open although it never reached 55%.

### A drag left parks the row open on Silence

A 60 pixel drag left parks the row at minus 84 with "Silence" tappable; tapping it silences and closes.

### A captured row has nothing to log

A captured row dragged right stays at rest and logs nothing.

### Every gesture is a semantics action

The row's semantics node carries custom actions "Log the full credit" and "Silence"; performing each fires the matching callback with the row still at rest.

### The bell silences by name

Tapping the node labelled "Silence reminders for Credit 0" silences that credit and does not open it.

### Tap opens, at 200% too

At a 2.0 text scale a tap opens the credit and a 60 pixel drag still parks the row open with "Log it" tappable and no layout exception.

## Credit actions

`credit_actions_test.dart` drives `CreditActions` as plain Dart over a `MemorySnapshotStore` and a `SnackbarState`, on a $100 Resy credit with $30 logged and a locked Equinox credit ([[mobile-architecture#Undo and the snackbar]]).

### Logging writes at once and Undo removes that claim

`logAll` records the $70 remainder immediately and shows "Logged $70 on Resy Dining Credit." with an Undo labelled "Undo logging Resy Dining Credit"; acting on it removes that claim and leaves the earlier one.

### A partial log names its amount

`log` with $35 records $35 and says "Logged $35 on …".

### Muting has an Undo that restores the previous state

`toggleMute` silences with "Silenced … It is still tracked." and "Undo silencing …", whose Undo unmutes; from muted it says "Reminders back on for …" with "Undo reminders back on for …", whose Undo mutes again.

### Unlocking has an Undo that revokes

`confirmEnrollment` stamps `enrolledAt`, says "Equinox Credit unlocked." with "Undo unlocking Equinox Credit", and the Undo clears it.

### Removing and clearing report without an Undo

`removeClaim` says "Removed $30 from …" and `unclaimAll` "Cleared what was logged against …", each with no action.

## Snackbar

`snackbar_test.dart` pumps `SnackbarHost` bare with the test clock, then the whole app at 1280 and 402 ([[mobile-architecture#Undo and the snackbar]]).

### An undo stays up for twenty seconds

A message with an action is still there at 19 seconds and gone at 21.

### A plain message leaves sooner

A message without an action shows no Undo, is there at 3 seconds and gone at 4.

### Focus pauses the timer and leaving restarts it

Focusing the Undo at 5 seconds holds the bar through 30; blurring restarts the full 20, so it is there at 49 and gone at 51.

### The pointer pauses the timer too

A mouse over the bar at 5 seconds holds it through 30; moving away restarts the 20 the same way.

### The undo button says what it undoes

An action with a semantics label yields a button found by "Undo logging Uber Cash" whose visible text is "Undo"; tapping it acts once and dismisses the bar.

### A newer message replaces the older

A second message at 15 seconds replaces the first and is still up 15 seconds later, then gone after its own 20.

### The snackbar centres on the content column

At 1280 with the sample household, the bar's centre is the content column's centre, which is not the window's, and it is no wider than the column.

### The snackbar sits above the bar on a phone

At 402 the bar's bottom edge is at or above the `NavigationBar` and it is centred on the phone column.

## End to end

`integration_test/app_test.dart` drives the real app on a simulator or emulator through `make e2e` ([[mobile-architecture#Make targets]]); it is not part of the verify gate.

### A fresh install launches to the first-run screen

Booting the app with an empty snapshot store on a device reaches the Today screen and shows "Start with one card", proving the shell, the store and the screen wire together outside the test harness.
