# Mobile tests

What the Flutter widget suites in `apps/mobile/test/` guard, run by the `flutter` job of the verify gate ([[deployment#Pipeline]]).

## Theme

`theme_test.dart` pins the theme to the Nocturne tokens so a re-theme is a deliberate token change rather than drift ([[mobile-architecture#Theme]]).

### Both themes carry the Nocturne token colours

Each theme's primary, surface, on-surface and scaffold colours are the `tokens.css` values for its mode, and each carries its token set as the extension.

Dark: `#d16f84`, `#232532`, `#e9e9ed`, `#161826`. Light: `#8d4253`, `#ffffff`, `#232532`, `#f3f5fe`.

### The app follows the platform brightness

With the platform reporting dark, the running app resolves the dark accent as primary and the dark "use soon" ground from the extension, so the system setting is what picks the theme.

### The accent takes the logo's maroon

In both themes the accent's OKLCH hue is within 10° of the logo's "reward" maroon `#933F53`, so the app's colour and the logo are one brand (#291).

### Use soon and missed are different colours

In both themes the "use soon" and "missed" tone lines are at least 70° apart in OKLCH hue, wider than the 60° they had before #291, so an urgent row never reads as a lost one.

## Control sizes

`control_sizes_test.dart` pumps each kind of control under both themes and measures its drawn surface apart from its tap padding, so the HIG floor in [[mobile-architecture#Theme]] cannot slip (#335).

### Buttons are drawn 44 and respond to 48

`FilledButton`, `OutlinedButton`, `TextButton` and their `.icon` variants each draw a `Material` exactly 44 high inside a box at least 48 high, in light and dark.

### Icon buttons are drawn 44 square

An `IconButton` draws a 44 x 44 surface around a 24 glyph, and its tap target is at least 48 x 48.

### Segmented buttons are drawn 44

A `SegmentedButton`'s painted outline is 44 high, measured from its paint calls because the segments fill the touch area, and the whole control is at least 48 high.

### Chips are drawn 40 and respond to 48

A selected and an unselected `ChoiceChip` and a selected `FilterChip` each draw 40 high in a box at least 48 high.

### A selected chip shows a check mark

A selected `ChoiceChip` is wider than the same chip unselected because it carries a check mark, and the theme gives the mark a colour.


## Brand lockup

`brand_lockup_test.dart` pumps `BrandLockup` in a box the width the app bar gives it (the window less 84) in both themes and checks which file is drawn and at what size ([[mobile-architecture#Brand lockup]]).

### The lockup fits down to a 308 window

At 402, 320 and 308 windows the lockup is drawn at 224 x 32, the `-dark` file in the dark theme and the other in the light.

### Below that the wordmark

At a 300 window the wordmark is drawn at 154 x 22, the `-dark` file in the dark theme.

### A narrower bar scales the wordmark down

At a 220 window the wordmark is narrower than 154, keeps its 7:1 shape, fits the box and nothing overflows.

### The text scale leaves the size alone

At text scale 2.0 the lockup is still 224 x 32: it is artwork, not text.

### An image, not a heading

The semantics tree has one node labelled "HelpMe reward", flagged as an image and not as a header, so each screen keeps its one level-one heading.

## Today

`today_screen_test.dart` renders the screen over the PWA's sample household with today fixed at 16 September 2026 and compares it with what the PWA shows for that date ([[mobile-architecture#Today screen]]).

The expected rows are `test/fixtures/sample-today.json`, dumped once by the retired PWA (#174) and pinned.

### The sample household renders the PWA's rows, order and tones

Every `CreditRow` on the screen, in order, has the name, holder, tone and amount of the PWA's use-soon, locked and captured rows for that date, so the two apps agree on what is at risk and how it is drawn.

The app stores no holder, so the test names each row's holder from its card id, card-0001 Jim's and card-0002 Kathy's.

### The headline counts only what is claimable

The headline digits are the claimable total from the fixture, the subtitle names the nearest reset, and the section titles carry the reset date and the captured total.

### The locked section says why

With a spend-gated Dell bonus added to the sample household, the section is titled "Locked behind enrollment and spend", its note mentions a spend threshold, and the bonus is listed in it.

### Overlaps show the three largest

The three largest overlaps from the fixture appear as cards with their label, count and combined unclaimed value.

### The household value bar sits under the headline

At compact, medium and expanded, Today draws one `ValueBar` whose breakdown is the sum of every active card's `cardYearToDateBreakdown`, below the headline and above the first row.

Its sentence is read after "Today" and before the "Use soon" section.

### Medium pairs the overlap cards

`today_layout_test.dart` renders Today bare inside a `WidthClassScope`. At medium the first two overlap cards share a top edge and sit side by side and the third starts a new row under the first; at compact they stack.

### Expanded splits the body in two under the headline

At expanded the headline block spans the full inner width, the use-soon and captured titles start at the left padding, the locked title starts past the centre on the same line as use-soon, and the first credit row ends before the centre.

### The screen reader hears the phone order at every width

The labels of the semantics tree in traversal order at expanded are exactly the labels at compact, so the two-column layout does not change what is read or in what sequence.

### A fresh install shows the first-run screen

With no snapshot the screen shows the empty state's heading, "Add a card to start tracking its credits", and no rows ([[mobile-tests#Today empty state]]).

## Empty card slot

`empty_card_slot_test.dart` pins the empty-state illustration ([[mobile-architecture#Today screen#Empty card slot]]).

### The illustration is a size by size box

`EmptyCardSlot(size: 160)` lays out as a 160 × 160 box.

### The illustration is hidden from the screen reader

The widget is wrapped in `ExcludeSemantics` and the semantics tree under it carries no label.

### Every edge clears 3:1 in both themes

Reading the palette the widget paints with, the dashed card edge, the plain card edge and the plus badge each reach 3:1 against every colour they are drawn on, in dark and in light.

## All caught up illustration

`all_caught_up_test.dart` pins the illustration Today shows once nothing is claimable ([[mobile-architecture#Today screen#All caught up illustration]]).

### Every edge clears 3:1 in both themes

The card edges, the accent ticks, the check badge and the check itself each reach 3:1 against every colour they are drawn on, the page included, in dark and in light.

### The illustration is hidden from the screen reader

The widget is wrapped in `ExcludeSemantics` and the semantics tree under it carries no label.

### The badge pops once

On the first frame the badge is drawn at 0.4 of its size; once the animation settles it is at full size.

### Reduce motion draws the badge at full size

With `MediaQuery.disableAnimations` set, the first frame draws the badge at full size and no animation runs.

## Value bar

`value_bar_test.dart` pins the `ValueBar` widget ([[mobile-architecture#Value bar]]).

### The four colours are tokens in both themes

`valueEarned`, `valueAvailable`, `valueMissed` and `valueOptOut` are `#6CC18E`, `#D16F84`, `#E3C25B`, `#595D6C` in dark and `#2E7D4F`, `#B7576D`, `#A87F12`, `#B9BBC5` in light.

### Segments run in order, sized by amount

At 360 wide, $540 · $770 · $180 · $360 draw Earned, Available, Missed and Opt out left to right, each 8 high, 2 apart and as wide as its share of the 354 left after the gaps, in each segment's token colour.

### A zero segment is not drawn

$30 earned and $70 available draw two segments, the first 30% of the width, with "$30 Earned" and "$70 Available" under them and nothing for Missed or Opt out.

### Labels sit centred under their segments

With two equal segments, each amount-and-label block is centred under its own segment, below the bar.

### Narrow neighbours never overlap

At 320 wide and 200% text, a $1,000 earned segment followed by three $5 ones places every label inside the bar's width, none overlapping another, and throws no overflow.

### The bar reads as one sentence

The four-segment bar is one semantics node labelled "$540 earned, $770 available, $180 missed, $360 opt out"; the amounts and labels are not read separately. A zero segment is left out of the sentence.

### An empty breakdown draws only the track

An all-zero breakdown draws the 8-high track, no segments and no text.

## Today all caught up

`today_all_caught_up_test.dart` pumps Today over the sample household cut down to its two Uber Cash credits, both used on 16 September 2026, and pins the state that replaces the number ([[mobile-architecture#Today screen#All caught up]]).

### Every open credit used shows All caught up

The `AllCaughtUp` illustration and "All caught up" replace `today-amount`, and the value bar and the captured section stay.

The line reads "You’ve used all $30 open this period across 2 cards.", Next up reads "Next up: Uber Cash, $15 × 2" and "Opens Oct 1, in 15 days".

### Locked credits change the wording

With Kathy's un-enrolled Oura credit added, the heading is "Everything you can use is used", the line says $200 is still locked, the locked section is present, and there is no Next up card and no "All caught up".

### A claimable credit brings the number back

Undoing one Uber Cash claim brings back `today-amount` at 15 on the next frame, with no illustration or heading.

### A muted unused credit is not done

With both Uber Cash credits unused and muted, Today keeps the normal headline: muting silences reminders and does not use a credit.

### No card and loading keep their screens

A household with no card still shows the empty state's heading, and a store that has not loaded shows the progress indicator; neither shows "All caught up".

### The screen reader hears the heading after Today

At compact and expanded the traversal reads "Today", then the heading, the line, Next up and the value bar sentence, and the heading is flagged as a header.

### The state holds at every width and at 2x

At compact, medium and expanded, at 1x and 2x text, both the all-caught-up and the locked variant lay out with no overflow.

## Today nothing due soon

`today_nothing_due_soon_test.dart` boots the app at Today on 2 October 2026 over the sample household cut to Kathy's Resy credit, open until 31 December, and pins the note ([[mobile-architecture#Today screen#Nothing due soon]]).

### Open money with nothing due soon shows the note

With the $100 Resy credit open and nothing use-soon, Today shows "Nothing closes in the next 30 days", "Resy Dining Credit is next, $100 by Dec 31." and the link, and no Use soon section.

### The link opens Credits

Tapping "See open credits on Credits" goes to the Credits tab.

### Use soon rows or nothing claimable hide it

With an unused Uber Cash credit closing on 31 October beside Resy, the Use soon section shows and the note does not; with only a used Uber Cash, Today is all caught up and there is no note.

### The note is a 48 target and holds at 2x

At 1x and 2x text the note and its link are each at least 48 high, stay inside 402, and nothing overflows.

## Today empty state

`today_empty_state_test.dart` boots the app at Today on a household with no active card, locally or through the fake service tier, and pins the empty state ([[mobile-architecture#Today screen#Today before any card]]).

### The heading is the screen's first header

With no cards, "Add a card to start tracking its credits" is shown and is the first node flagged as a header in traversal order.

### No value bar without a card

With no card, Today shows the empty state and no `ValueBar`.

### The body clears 4.5:1 in both themes

The body text is shown, and its painted colour against the page reaches 4.5:1 in light and in dark.

### Add your first card opens the catalogue and Back returns

"Add your first card" pushes `/cards/new`; Back from the catalogue pops to Today, which still shows the empty state.

### Only archived cards read Add a card

With one archived card and no active one, the empty state shows and its button reads "Add a card".

### Loading is not empty

Before the store has loaded, Today shows the progress indicator and not the empty state.

### The first card switches Today to its normal layout

Adding a card from a template while Today is open replaces the empty state with the headline, without a restart.

### A household with only locked credits is not empty

A card whose only credit needs enrollment shows the normal layout with its locked section, not the empty state.

### The invite button shows signed in and opens the join screen

Locally there is no invite button. Signed in, "Have an invite code?" opens the invite dialog, and a code typed there opens the join screen for it.

### Both buttons are 48 high

The Add button and the invite button are each at least 48 high.

### Stacked at compact and medium, side by side at expanded

At 402×874 and 768×1024 the illustration sits above the heading, nothing overflows and the Add button is on screen; at 1280×832 the illustration is left of the heading and the Add button is fully on screen without scrolling.

### The app bar and navigation stay

The empty state is inside the shell: the Settings gear and the navigation bar are present.

## Today interactions

`today_interactions_test.dart` pumps the whole app at 402 wide over the sample household, dated 16 September 2026, with the ui state injected, and drives Today the way a user does ([[mobile-architecture#Today screen#Today's interactions]]).

### A row opens the sheet and logging moves it to captured

Tapping Kathy's Resy row opens its sheet; "Mark the full $100 used" closes it, drops the headline from $1,898.90 to $1,798.90, draws that row in the captured tone and shows the undo snackbar.

### Swiping a row logs it with an undo

A 60 pixel swipe on the same row and a tap on "Log it" drops the headline the same way, and "Undo logging Resy Dining Credit" restores it.

### Today has no household filter

With two Platinums in the household no filter renders, and the headline is the claimable total of every card's instances.

### An overlap card opens the compare sheet

Tapping "Hotel Credit (FHR / THC) × 2" opens the compare sheet with a side per labelled Platinum, "Both sides are untouched at $300", and a log button per side.

The Platinums are labelled "Jim's Platinum" and "Kathy's Platinum"; "Log $300 on Jim's Platinum" closes the sheet and records a $300 claim on Jim's hotel credit.

### A compare side opens that credit

Tapping Kathy's side closes the compare and opens the credit sheet for Kathy's hotel credit.

### Today has no Preview nudge

Real push reminders replaced the in-app preview (#289), so Today draws no "Preview nudge" button, by text or by label.

## Credits

`credits_screen_test.dart` renders the screen over the sample household dated 16 September 2026 and compares it with `test/fixtures/sample-credits.json`, dumped once by the retired PWA (#174) and pinned ([[mobile-architecture#Credits screen]]).

The fixture carries the header counts, the four totals, every filter's rows as drawn under the card grouping, and every grouping's labels and figures.

### The header carries the counts and the four totals

"All credits" is headed by "14 open · 2 locked · 48 missed", and the Claimable, Locked, Captured and Missed tiles show the fixture's totals.

### Each filter shows the PWA's rows

All shows the 72 rows the PWA shows in its order, and choosing Use soon, Open, Locked, Captured and Missed in turn shows exactly the fixture's rows for each.

### Groupings produce the PWA's labels in order

Card, Cycle and Status produce the fixture's group labels and figures in the fixture's order.

### A group figure follows the filter and never mixes

Under Missed by card the figures are the fixture's, starting "$653.60 missed"; under Captured they start "$741 captured"; no figure mentions both.

### An empty filter says so

A household with only a locked credit shows "Nothing matches that filter." and no rows under Captured.

### Rows swipe and open the sheet in place

In the app on the Credits tab, Kathy's Resy row swipes left to "Silence" and a tap away closes it; tapping the row opens its sheet, "Mark the full $100 used" turns that same row captured in place.

### The totals re-flow with the width

At compact Claimable and Locked share a top edge and Captured sits below; at expanded all four share a top edge inside the padded column.

### Opted out is its own yearly figure

The "Opted out" tile is absent while nothing is opted out. Opting out the Oura Ring Credit shows its annual value as "… a year", read as "Opted out, … a year", and claimable drops.

### Five totals hold at compact and expanded

With a credit opted out, the fifth tile wraps below the others inside the compact column, and from medium all five sit in one row inside the column.

### Segments carry labels and a selected state

"All" and "Card" are selected, "Missed" and "Cycle" are not, the groups are labelled "Filter by status" and "Group credits by", and choosing Missed moves the selection.

### Credits at 200% clips nothing

At a 2.0 text scale on 402 the screen raises no layout exception and every text's painted rectangle ends inside the width.

## Cards

`cards_screen_test.dart` renders the screen over the sample household dated 16 September 2026 and compares it with `test/fixtures/sample-cards.json`, dumped once by the retired PWA (#174) and pinned ([[mobile-architecture#Cards screen]]).

The fixture carries the fee and captured totals and each active card's figures, verdict and tags.

### Each card carries the PWA's figures, verdict and tags

"Cards" is headed by the fee and captured totals; each card shows its issuer, label, fee, captured, net, percentage, days to renewal, verdict and edit button, and "Add a card from the catalog" is on the screen.

Each card's status group reads the fixture's tags joined by commas.

### Each card shows its value bar for the year to date

At compact, medium and expanded, every active card of the sample household draws a `ValueBar` whose breakdown is `cardYearToDateBreakdown` for that card on 16 September 2026, read as its sentence.

The bar sits under the Fee / Captured / Net row and above the percentage line. No `LinearProgressIndicator` and no "Share of the annual fee earned back" label remain.

### Add a card sits above the first card

"Add a card from the catalog" is laid out below the "Cards" title and above the first card, so it is reachable without scrolling past every card (#365).

### A card states its usable value, and its potential once anything is opted out

Jim's card reads "Credits worth … a year" with its usable value. After opting out the Oura Ring Credit it reads "… potential · … usable · … opted out", heard as "Credits worth … a year: … usable, … opted out".

### The verdict never counts opted-out credits

Opting out an open credit lowers the card's claimable by exactly that credit's remainder, leaves locked alone, and the verdict shown is the one worded from those figures.

### The value line holds at compact and expanded

With a credit opted out, the potential · usable · opted out line stays inside the card at compact and at expanded, and nothing overflows.

### A business card carries a Business mark

With Jim's card made `business`, his card shows a "Business" tag and Kathy's shows none.

### The verdict is the PWA's, case by case

`cardVerdict` over made-up summaries gives No fee, Keep with its body, Unlock first, Catch up with its body, and Decide with the lounge-access line.

### Mute from the menu offers an undo

"Menu for American Express Platinum — Jim" then Mute silences the card and shows "Silenced every credit on …" with "Undo silencing …", whose Undo unmutes; the menu then offers Mute again.

### Archive hides the card

Archive marks the card archived, removes it from the screen while the other stays, and shows "Archived …" with an Undo that brings it back.

### Delete asks first and cascades

Delete shows "Delete … and everything logged against it? This cannot be undone."; Cancel keeps the card; Delete removes the card and every benefit on it and says "Card deleted." with no Undo.

### One column, two across, then one wide row

At compact the second card is below the first; at medium the two share a top edge side by side; at expanded each card takes the full padded width, one per row, with the verdict block to the right of the figures block on the same band.

### The screen reader hears the phone order at every width

The semantics labels in traversal order at expanded are exactly those at compact.

### Status figures are read-only

On both sample cards the status group holds no ink, gesture, chip, button or bordered box, and its semantics node is neither a button nor tappable; Kathy's reads "$500 locked".

### Status figures reach 4.5:1 on the card

In light and dark, every text in every card's status group clears 4.5:1 on the raised card surface.

### Status figures wrap at 200%

At 2.0 on 402 Kathy's four figures (claimable, locked, missed, credits) sit inside her card and span more than one row, with no layout exception.

### Cards at 200% clips nothing

At a 2.0 text scale on 402 the screen raises no layout exception and every text's painted rectangle ends inside the width.

### Every control on a card has a label

Every button in the semantics tree has a label or a tooltip, and the menu is found by "Menu for …".

### No cards shows the first-run copy

With no cards the screen says "Start with one card", draws no card, and offers the catalogue through "Add your first card" alone, without the "Add a card from the catalog" button.

## Empty tabs

`empty_tabs_test.dart` opens Credits, Cards and Value in the app on a household with no active card, and pins the Add button they share with Today's empty state ([[mobile-architecture#Today screen#Today before any card]]).

### Each tab offers Add your first card

Each tab shows its empty message (Credits "No cards yet, so no credits to track.", Cards "Start with one card", Value its note) and one 48-high "Add your first card".

Credits does not say "Nothing matches that filter." and Cards drops its catalogue button.

### The button opens the catalogue and Back returns to the tab

On each tab the button pushes the catalogue, and Back returns to that tab.

### Archived cards read Add a card

With only an archived card the button reads "Add a card" on each tab.

## Single choices

`segmented_choices_test.dart` pins Apple's rule that a group offering exactly one choice is a segmented button, over the sample household (#331).

### Each single-choice group is a segmented button

Settings' Appearance, the benefit editor's Measured from, the card editor's Kind and Value's months shown each render as one `SegmentedButton` holding all their options, and no `ChoiceChip` remains on those screens.

### Each is drawn 44 and full width with a check on the selection

With the SDK's Roboto loaded so labels measure as on a device, each group's outline is drawn 44 high at 402 wide, its touch area is at least 48, it is as wide as its column allows, and its selected segment shows a check.

## Route guidelines

`route_guidelines_test.dart` runs Flutter's accessibility guidelines over every route so no later change can quietly shrink a control or fade a label below the HIG floor ([[mobile-architecture#Accessibility]], #334).

### Every route passes the four guidelines on both platforms

On `TargetPlatform.iOS` and `TargetPlatform.android`, in light and dark, at 402 wide, `iOSTapTargetGuideline`, `androidTapTargetGuideline`, `labeledTapTargetGuideline` and `textContrastGuideline` pass on each of these:

- Welcome, Sign in, Today, Today's empty state, Credits, Cards, Value and Settings.
- The benefit editor, Add card, the card editor, Change the terms, Join household and Not found.
- The credit sheet, open over Today.

Shrinking the theme's density or fading `textSecondary` turns it red.

### Icon buttons are drawn 44 and respond to 48

The app bar's gear, the editor's back and delete, the credit sheet's close, a row's reminder bell and a card's menu each draw a 44 x 44 surface in a tap box at least 48 x 48.

## Bezel spacing

`bezel_spacing_test.dart` pins Apple's spacing: about 12 between bezeled controls, measured between their drawn surfaces rather than their tap boxes (#332).

### Credits filter chips sit 12 apart

At a 1.6 text scale the Credits status chips wrap onto more than one row, and adjacent chips are at least 12 apart across and down.

### Sign in's buttons are 44 high, 12 apart and full width

"Continue with Google" and "Continue with Apple" are drawn 44 high with at least 12 between them, and "Have an invite code?" and "Learn more" are drawn 44 high and as wide as the Google button's column.

### Change the terms offers two full-width choices

"Make it mine" and "Keep it up to date" are each drawn 44 high, equally wide, and at least 12 apart.

### The 12 gap is a named token

`Space.bezel` is 12, so screens name the gap rather than repeat a bare literal.

## Switch rows

`switch_row_test.dart` pins Apple's rule that a switch row is one target: the row flips, not only the switch ([[mobile-architecture#Forms and the Field pattern#The editors]], #330).

### Tapping the title toggles on every screen

Tapping the title text flips Settings' "Send me reminders" and the card editor's "Silence every credit" and "Archive this card", each read back from the store.

### A disabled row ignores taps

A `SwitchRow` with a null `onChanged` stays off when its title or its switch is tapped, and its node reports disabled.

### Each row is one semantics node

The row's node carries its label, its note as the hint, the toggled state and a tap action, no child is a node of its own, and a semantics tap flips it.

### The credit sheet has no switch row of its own

`credit_sheet.dart` defines no private `_SwitchRow`; the sheet uses the shared `SwitchRow`.

## Field

`field_test.dart` pumps one required `Field` around a text field with the domain's `requiredError` and a second field to blur into ([[mobile-architecture#Forms and the Field pattern]]).

### The error waits for blur

Typing and clearing the field shows no error; leaving it shows "Enter whose card this is."; typing a name clears it.

### Submitting forces the error into view

With `submitted` true the error shows before the field has been touched.

### The label, the mark, the hint and the error reach the screen reader

The label reads "Whose card is it? *", the hint is drawn under the control, and the error's semantics node carries the sentence as a live region.

## Add a card

`add_card_screen_test.dart` opens the app at `/cards/new` over the sample household and walks the two steps ([[mobile-architecture#Forms and the Field pattern#Add a card]]).

### A template becomes a card with its credits

The catalogue shows the Platinum with its annual value; picking it shows "Card details", the required note, and the label "American Express Platinum (1)"; a date then "Add this card" adds the card.

The label is proposed because the sample household already holds two Platinums.

The card carries that label, date, issuer and product, its benefits match `benefitsFromTemplate` by name, value and enrollment, and the "Added with N credits" snackbar shows.

### A label another card shows is named and focused on submit

Typing "American Express Platinum" shows nothing; Save shows the "already called" sentence, adds nothing and focuses the label field.

A fresh label then clears the error and Save adds the card.

### Typing shows no error before blur

Typing a taken label shows no error until the anniversary field is tapped.

### A bad date shows the domain's sentence

"2026-13-40" shows "Enter the date the cardmember year starts." after blur, and the Save button stays enabled.

### Back with a draft asks first

System back on an untouched form returns to the catalogue; with a label typed it asks "Discard this card?", "Keep editing" stays, and "Discard" leaves to Cards.

### Short fields pair from expanded

At 402 the anniversary sits under the label; at 1280 they share a top edge side by side and the Save button spans the row.

### The form at 200% clips nothing

At a 2.0 text scale the form raises no layout exception and every text ends inside the width.

### The blank template asks for issuer and card

The top "Add card" button then Save shows "Enter who issues the card." and "Enter the name of the card."; filling them adds a personal card with no benefits and says "Card added. Add its credits next."

### Manual entry sits at the top, labelled by width

On first render the top button is on screen without scrolling and at least 48dp tall. It reads "Add card" at 402 wide and "Add card manually" at 1280.

### The end of the list offers manual entry

The list ends with "Don't see your card?" and a 48dp "Enter it manually" button, and "Set one up by hand" is gone. The button opens the Issuer and Card fields, and saving adds a card with no credits.

### The catalogue is ordered by annual value

The first template tile is the first template from `sortByValue`, which is worth at least as much a year as any other template.

### The catalogue at 200% clips nothing

At a 2.0 text scale at 402 wide, the catalogue raises no layout exception. Every text ends inside the width, down to the end-of-list button.

### A business template lands as a business card

Picking the Business Platinum and saving with a date adds a card whose kind is `business`, copied from the template.

## Catalogue filter

`catalog_filter_test.dart` opens the app at `/cards/new`, 1280 wide unless a case says otherwise, and drives the side panel and, at 402, the compact sheet ([[mobile-architecture#Forms and the Field pattern#Add a card#Catalogue filter]]).

### Checking an issuer narrows the list and adds a chip

The header starts at "16 of 16 cards". Checking Chase leaves 4 tiles, shows "4 of 16 cards" and adds a "Chase" chip. The chip's "Remove Chase filter" button restores all 16.

### Business narrows to business cards in the panel and the sheet

At 1280, checking Business in the panel adds a "Business" chip and leaves only the Business Platinum. At 402, checking it in the sheet shows "Show 1", which closes onto the same chip and tile.

### Facets combine and counts follow the other facets

With Chase checked, the fee bands count 2, 1, 0 and 1 for Under $100, $100–$399, $400–$599 and $600+. Checking $600+ as well leaves only the Sapphire Reserve, with a "$600+" chip.

### Search narrows per keystroke and Clear all resets everything

Typing "u", "ub", "ube" and "uber" shows each prefix's `filterTemplates` count. "Clear all" then empties the facets, both search fields and the chips, and hides itself.

### The merchant group shows six and searches its own options

Six merchant options show until "Show all" lists every one, and "Show fewer" returns to six. Typing "a" in the merchant sub-search lists every merchant containing it, hides the toggle and leaves the card count at 16.

### No match shows the empty state with manual entry

Searching "zzzz" leaves no tiles and shows "No cards match. Try removing a filter, or add your card manually.". Its button opens the blank form with Issuer and Card.

### The result count is a live region

The "N of 16 cards" text's semantics node carries the live-region flag, so a screen reader announces each change.

### The panel at 200% clips nothing

At 720 wide with a 2.0 text scale, and American Express and Adobe checked, no layout exception is raised and every text ends inside the width.

### A selected merchant tags the benefits it matched

No tile has a tag until Uber is checked. Then the Platinum shows "Uber Cash (monthly)" with an icon and "$15/mo", and "Uber Cash (December bonus)" with "$20/yr".

Every listed tile's tags equal its `matchedBenefits`, and the Platinum's semantics label contains "Matches Uber Cash (monthly)".

### The search tags only the benefits it matched

Searching "resy" tags each listed tile with exactly its `matchedBenefits`, and every tag names a Resy credit.

### The Filters badge counts selections, not search text

At 402 wide there is no panel, and the Filters button shows no badge. Checking $600+ and Visa in the sheet and typing search text gives a badge of "2".

### Show N reports the live count and closes the sheet

The sheet opens on "Show 16". Checking Chase turns it into "Show 4", and tapping it closes the sheet onto the Chase chip, "4 of 16 cards" and focus on the Filters button.

### The scrim and system back close the sheet and keep the selection

A scrim tap closes the sheet with Chase still chosen. Reopening, checking Citi and pressing system back closes only the sheet, leaving both chips on the catalogue.

### Growing past compact swaps the sheet for the panel

With the sheet open and Chase checked, widening to 1280 closes the sheet, removes the Filters button and shows the panel with Chase checked. Narrowing back keeps the chip and the count.

### The sheet keeps 48dp targets and clips nothing at 200%

At a 2.0 text scale the Filters button, "Show N" and every facet option are at least 48dp tall, the sheet raises no exception, and its text ends inside 402.

## Editors

`editors_test.dart` opens the app at the card editor for Jim's Platinum and at the benefit editor for his Uber Cash over the sample household ([[mobile-architecture#Forms and the Field pattern#The editors]]).

### The card editor writes valid values and shows errors for the rest

The editor is titled by the card with "12 credits"; a typed label reaches the store at once; an invalid fee or date shows its sentence after blur and is not written, and so does a label another card already shows.

The sample's two Platinums are labelled with the names the PWA shows for them, "American Express Platinum — Jim" and "— Kathy", here and in the Cards, Credits, Value and routing suites, so the PWA's fixtures still apply.

"abc" as the fee leaves the fee alone and shows "Enter the amount as a number, like 695."; "695" writes $695 and clears it; "2026-02-30" shows the date sentence.

### Mute, archive and network are on the card editor

The "Silence every credit" switch mutes the card, choosing Visa writes the network, and "Archive this card" archives it.

### The card kind is a choice on the card editor

Jim's card starts personal; tapping the "Business" segment writes `CardKind.business` and "Personal" writes it back.

### The credit list opens each editor and adds a credit

The twelve credits are listed by name in order; tapping Uber Cash opens its editor; "Add" adds a "New credit" on the card and opens its editor.

### Opted-out credits are grouped on the card editor and reactivate there

Opting out Uber Cash moves it under an "Opted out" heading below every tracked credit, with no "paused" tag anywhere. Its "Reactivate Uber Cash" button is at least 48dp tall and clears the opt-out with `trackedFrom` today.

### Deleting a card from its editor confirms, cascades and returns

"Delete this card" asks, Delete removes the card and every benefit on it, says "Card deleted." and lands on Cards.

### Back with an unsaved draft asks first

With nothing invalid, system back leaves for Cards at once; with "abc" as the fee it asks "Leave without saving?", Stay keeps the editor, Leave goes to Cards.

### An unknown id shows the not-found state

`/cards/nope` shows "Card not found" and "That card is no longer here."; `/benefit/nope` shows "Credit not found" and its line.

### The window follows the cadence and the anchor live

Uber Cash shows "This period runs Sep 1 – Sep 30 (Sep 2026)." and its ladder; choosing Quarterly shows "Jul 1 – Sep 30 (Q3 2026)" and writes the cadence.

"Card anniversary" then shows the window `cycleFor` gives for Jim's anniversary and writes the anchor.

### The benefit editor writes valid values and shows errors for the rest

"0" as the value shows "Enter a value above zero." and leaves $15; "45" writes $45 and clears it; a blank name shows its sentence and keeps the name; a merchant is written as typed.

### Enrollment, tracking and the switches write the benefit

"Needs enrollment" requires enrollment and shows "Not yet — the credit is locked."; "Enrolled" stamps it; "not a url" shows the address sentence and a real address is written.

"Opted out" stamps `optedOutAt` and leaves `active` alone. There is no "Track this credit" switch any more; the "Opted out" switch carries the note "You won’t use this. It stays off your lists and totals until you reactivate it."

### A rolling credit asks for its interval and hides the anchor

Choosing Rolling writes the cadence, removes the anchor segments and shows "Months between claims"; blank shows "Enter how many months between claims." and writes nothing; "48" writes it.

Emptying the field again keeps 48 and shows the sentence, so an invalid interval is never saved.

### A spend threshold and its reached switch write the benefit

"abc" in "Unlocks after spending" shows the money sentence after blur and writes nothing; "5000" writes $5,000 and reveals "Spend reached this year", which stamps `spendMetAt`; emptying the field clears the threshold.

### An end date is optional and validated

Uber Cash has no end date; "2026-13-40" in "Ends on" shows "Enter the last day it can be used as a date, or leave it blank." after blur and writes nothing; "2026-12-31" writes it and clears the sentence; emptying the field clears the date.

### Deleting a benefit takes its claims and returns to the card

"Delete this credit" then Delete removes the benefit and its claims, says "Credit deleted." and lands on the card editor.

### Editor fields pair from expanded and survive 200%

At 1280 the name and value fields share a top edge side by side; at a 2.0 text scale on 402 the benefit editor raises no layout exception and every text ends inside the width.

## Value

`value_screen_test.dart` renders the screen over the sample household dated 16 September 2026 and compares it with `test/fixtures/sample-value.json`, dumped once by the retired PWA (#174) and pinned ([[mobile-architecture#Value screen]]).

The fixture carries the nine-month totals and peak, each month's bars, the ranks and the leaks.

### The totals, the bars, the ranks and the leaks are the PWA's

Every figure on the screen equals the fixture: the scope line, the two totals, the expired lead, the tallest bar, the months, the ranks and the leaks.

That is "Last 9 months · 2 cards", the captured and missed totals, the lead naming the biggest leak, "Tallest bar = …", the month labels in order, the painter's months and peak with its scaling of the peak to the full height and of zero to nothing, the ranked labels and percentages, and the leaks' labels, spans and amounts.

### The chart reads every month's figures aloud

The chart's semantics label carries "Captured against missed, by month" and, for every month, "Jan: captured $453, missed $90.90" in that shape.

### The months segment re-bins the chart

Nine month labels by default; 6m shows six and retitles the screen "Last 6 months · 2 cards"; 12m shows twelve.

### The chart grows with the column

At each width class the chart is exactly the column's width less the padding.

### Value at 200% clips nothing

At a 2.0 text scale on 402 the screen raises no layout exception and every text ends inside the width.

### No cards shows the empty note

An empty household shows the note about what will appear, the Add button, and neither the ranks nor the leaks.

## Settings

`settings_screen_test.dart` opens the app at `/settings` over the sample household and drives each section ([[mobile-architecture#Settings screen]]).

### Each reminder control writes its field and reflects it

"Send me reminders" turns reminders on and reveals the time, the minimum and the locked switch; "08:30" writes the time of day; the locked switch writes its flag.

A fresh app over the same saved snapshot shows reminders on, the time, and the locked switch off.

### A bad minimum shows the error and writes nothing

"abc" shows "Enter the amount as a number, like 695." only after the field is left and leaves the minimum at $1; "5" writes $5 and clears the error.

### Choosing Dark overrides the platform and System follows it again

With the platform light, the app starts in system mode showing light; Dark writes the setting and switches the theme mode and the shown brightness to dark; System returns both to the platform; Light sets the light mode.

### The ladder table lists the four cadences

Monthly, Quarterly, Semi-annual and Annual each show their cadence label and `ladderSummary`; Manual is not listed.

### Settings keeps one column and survives 200%

At 1280 the minimum field spans the padded column and sits under the time field; at a 2.0 text scale on 402 nothing overflows and every text ends inside the width.

### Every switch and segment has a label and a state

Both switches are found by their labels and carry a toggled state; the appearance group is labelled and System is selected while Dark is not.

### Today leads to Settings

The gear labelled "Settings" in the bar on Today opens the Settings screen.

## Routing

`routing_test.dart` opens the app at a path over the sample household and checks the not-found screen, the headings and titles, focus on navigation and the notification handler ([[mobile-architecture#Navigation#Routes and the shell]]).

### An unknown path shows the not-found screen with a way back

`/nowhere` renders "That screen does not exist." with the window title "Not found · HelpMe Reward"; "Back to Today" leaves for Today.

### Every route has exactly one heading and its title

Each of the nine routes has exactly one level-one heading in its semantics, labelled with the screen's name, and the window title is that name followed by " · HelpMe Reward".

The names are Today, All credits, Cards, Value, Add a card, the card's label, the credit's name, Settings and the not-found line, whose window title is "Not found".

### Navigation moves focus to the heading, a tab press keeps it

After `go` to Credits the Credits heading's node has primary focus; after a press on the Cards destination the Cards heading does not, and no heading holds it.

### A notification payload opens its screen

A payload naming `/benefit/ben-0003` opens that editor above the shell and back leaves it; a payload with a web address, or none, changes nothing.

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


## Brand app bar

`brand_app_bar_test.dart` pumps the whole app over the sample household, dated 16 September 2026, and checks the one bar the four tabs share ([[mobile-architecture#Brand app bar]]).

### Every tab has the one bar and its gear

On Today, Credits, Cards and Value there is one `AppBar`, 64 high, holding the `BrandLockup` and one icon button, and exactly one "Settings" button on the screen.

### Today's heading draws the eyebrow

Today's header row is gone: its level-one heading, still labelled "Today", draws "WED 16 SEP · UNCLAIMED, OPEN PERIODS" above the total, and "HelpMe Reward" is no longer drawn as text.

### The gear opens Settings and back returns to the tab

From Credits, Cards and Value the gear opens Settings, and its Back returns to the same tab rather than to Today.

### From medium the bar sits over the column, not the rail

At 768 and 1280 the bar's content box starts and ends with the content column, the bar starts at or past the rail's right edge, and it is 64 high.

### The bar tints once content scrolls under it

On Credits at rest the bar is the page colour; after scrolling the list 300 up it is the theme's surface-container colour, which differs from the page colour.

### On a phone the lockup sits on the 20 margin

At 402 the lockup's left edge is 20 from the window, and the gear's 24 glyph ends 20 from the right edge.


## Pushed route bars

`pushed_route_bars_test.dart` opens Settings, the benefit editor, Add card, the card editor and Change the terms on the sample household at 402 wide and checks their bars ([[mobile-architecture#Brand app bar#Pushed routes]]).

### Back and the title in a 64-high bar

Each has one `AppBar`, 64 high like the tabs' bar, holding Back and the screen's `ScreenTitle`, and exactly one level-one heading on the screen.

### No gear on a pushed route

None of them draws the Settings gear or a "Settings" tooltip.

### The same colours as the tab bar

In a 500-high window, where Settings scrolls, its bar is the page colour at rest and the surface-container colour once its list scrolls under it.


## Landing screens

`landing_screens_test.dart` pumps Join household and Not found on their own, signed out, in both themes, and through the router with a signed-in session ([[mobile-architecture#Brand app bar#Landing screens]]).

### The lockup bar, with the gear only when signed in

Signed out, each has one 64-high bar holding the lockup, no Back and no "Settings" button; signed in, at `/invite/ABC123` and `/nowhere`, each shows the lockup and one "Settings" button.

### The two-line logo above the message

Each draws `helpmereward-logo.png`, the `-dark` file in the dark theme, and the logo ends above the screen's heading.

### Still one heading, the logo is an image

Each has exactly one level-one heading, and the two "HelpMe reward" nodes, the bar's lockup and the logo, are images and not headers.


## Entry logo

`entry_logo_test.dart` pumps Welcome and Sign in on their own, in both themes and on a small phone at a large text size ([[mobile-architecture#Sign-in#The stacked logo]]).

### The stacked logo replaces the piggy bank

Sign in does not draw `Icons.savings_outlined`; it draws `helpmereward-logo-vertical.png`, the `-dark` file in the dark theme, centred on the 402 window. Welcome has the lockup in its header instead ([[mobile-tests#Welcome layout]]).

### The buttons stay reachable on a small phone at 2.0

At 320 x 568 with text scale 2.0 nothing overflows, and Welcome's Next and Sign in's Google button can be scrolled fully into view.

### One heading, the logo is an image

Each has exactly one level-one heading, and the "HelpMe reward" node is an image, not a header.

## Welcome layout

`welcome_layout_test.dart` pumps `WelcomeScreen` on its own and pins the slideshow's layout ([[mobile-architecture#Sign-in#The welcome slideshow]]).

### Three slides in the new order

The slides read "All your rewards in one place", "Never miss another deadline" and "Get more from every card" with the benefit-first bodies from #315, and only the last button reads "Get started".

### The lockup heads the slideshow

The header draws `BrandLockup` left of Skip on the same line, no "HelpMe Reward" text, and Skip still calls `onDone`.

### The hero is decoration

Every slide has one `WelcomeHero`, and a child inside it is neither tappable nor present in the semantics tree.

### The hero has no panel

In both themes nothing between `WelcomeHero` and its child paints a background (no `ColoredBox` or `DecoratedBox`), and a `ClipRect` still clips the child at the hero's bounds.

### The hero ignores the text scale

Under a 2.0 system text scale the hero's child is laid out exactly 360 wide and sees a text scale of 1.0, with no overflow in a narrower hero.

### Text sits below the hero on a phone

At 402 x 874 the hero is over 40% of the window, the headline's top is at or below the hero's bottom, the body ends below the top third, and hero, headline and body share a left edge.

### A small phone at 2.0 drops the hero

At 320 x 568 with text scale 2.0 no slide has a hero or an overflow, the headline and body scroll into view, and the button stays on screen.

### The headline is the one heading

Each slide's headline is the screen's only level-one heading; the lockup is an image.

## Welcome heroes

`welcome_heroes_test.dart` pumps each slide's picture in a `WelcomeHero` over the sample household, in both themes ([[mobile-architecture#Sign-in#The welcome slideshow]]).

### Slide one is Today's headline and rows

`UpcomingRewardsHero` draws `TodayHeadline` with the sample household's claimable digits and at least three `CreditRow`s for its credits, covering the soon, available and locked tones, with no overflow.

### The first slide carries it

On `WelcomeScreen` the first slide's `WelcomeHero` holds the `UpcomingRewardsHero`.

### Slide two is a real reminder

`TimelyRemindersHero` draws a notification lookalike with "HelpMe Reward" and the first `notice` reminder's title and body, over the `CreditRow` of its biggest credit, in both themes.

The reminder is the one `buildSchedule` makes for the sample household on `sampleClock`, with the default preferences and reminders on.

### The second slide carries it

After Next, the second slide's `WelcomeHero` holds the `TimelyRemindersHero`.

### Slide three mocks the premium features

`PremiumFeaturesHero` draws a `CreditRow` marked "Tracked from your bank" and an insight card with one earn-more, one use-better and one missed insight, in both themes.

### The premium mocks use only tokens

`lib/screens/welcome_premium_mocks.dart` names no `Color(` or `Colors.` and says it is a placeholder.

### The third slide carries it

After Next twice, the third slide's `WelcomeHero` holds the `PremiumFeaturesHero`.

## Welcome logo

`welcome_logo_test.dart` cold-starts the whole `RewardApp` with `coldStart: true` and steps the logo sequence in fake time ([[mobile-architecture#Sign-in#The logo hand-off]]).

### The first frame is the splash icon

On the first frame of a signed-in cold start into Today the icon layer is the only one drawn, centred in the window at the splash's size (120 on iOS, 128 on Android), the cover is opaque, and the app bar's lockup is not painted.

### The icon follows the theme like the splash

The icon layer draws `helpmereward-icon-dark.png` in the dark theme and `helpmereward-icon.png` in light, the same icon the native splash drew in that theme (#320).

### The layers land on the lockup

Partway through, icon, wordmark and tagline form the stacked logo; at the end of the move icon and wordmark together cover exactly the screen's `BrandLockup` rect with no tagline, then layers and cover go.

It holds for Today, a first run into Welcome, Join and Not found.

### It plays once per process

After it settles, a theme change that rebuilds the app and a move to Credits draw no layers and no cover.

### It settles within a second

`logoHandOffDuration` is under a second, and 999 ms after the first frame no ticker is running, the screen is finished, and the Settings gear opens Settings.

### The cover blocks taps

Midway through, a tap on the Settings gear does nothing.

### Learn more opens on the lockup

After a cold start into Sign in has settled, "Learn more" opens Welcome with no layers, no cover and an opaque lockup.

### Reduced motion skips the sequence

With `disableAnimations` on, a cold start's first frame is already the finished screen with nothing animating.

### Too narrow for the lockup places it

In a 260-wide window the bar's lockup is narrower than 224, and the frame after the first is finished with no move.

### With no logo the layers fade in place

A cold start into Settings, whose Today underneath is never laid out, keeps the icon where the splash drew it midway, then settles with no layers and no cover.

### One logo node throughout

At the first frame, midway and after settling, the semantics tree has exactly one node labelled "HelpMe reward".

### Sign in starts from the splash icon

A signed-out cold start with the intro seen opens Sign in, whose first frame is the icon alone, centred at 120 on iOS, with the stacked logo not painted.

### Sign in lands on the stacked logo

At the end of the move the icon, two-line wordmark and tagline layers each cover their part of the 480 x 511 vertical artwork as fitted into the stacked `BrandLogo`'s rect; then layers and cover go and the logo is opaque.

### The stacked layers follow the theme

On Sign in the icon, `wordmark-stacked` and tagline layers draw their `-dark` files in the dark theme and the plain ones in light, like the native splash.

### Sign in settles or skips

On Sign in the sequence is over 999 ms after the first frame, and with `disableAnimations` the first frame is the finished screen with nothing animating.

### Sign in keeps one logo node

On Sign in, at the first frame, midway and after settling, exactly one node is labelled "HelpMe reward".

## Text scaling

`text_scale_test.dart` carries WCAG 1.4.4 into Flutter terms ([[mobile-architecture#Accessibility]]): the platform text scale is honoured and Today survives 200% on a phone-width viewport.

### No widget overrides the platform text scale

No Dart file under `lib/` mentions `textScaler` or `textScaleFactor`, so nothing caps or ignores the user's size preference.

### Today at 200% neither overflows nor clips

Today over the sample household at a 2.0 platform text scale and 402 wide raises no `RenderFlex` overflow, no paragraph exceeds its maximum lines, and every text's painted rectangle lies inside the viewport width.

### Controls and text do not overlap at 200%

At the same scale no two credit rows and no two texts overlap, so nothing draws over anything else; a text inside its own row is the one permitted nesting.

### Segmented choices wrap inside the viewport at 200%

At 2.0 on 402 x 874, Appearance, Measured from, Kind and the months shown each report no exception, and every segment label ends inside the viewport and inside its segmented button without exceeding its lines.

### The headline shrinks to fit at 200%

The headline number's painted width at 2.0 is smaller than its natural width and its right edge stays inside the padded column, so it scales down rather than overflowing.

## Token contrast

`contrast_test.dart` computes WCAG ratios over the theme extension's token set for light and dark, the way the retired PWA did over its `tokens.css`, so a changed token cannot slip below the ratios ([[mobile-architecture#Accessibility]]).

The tone lines around rows and the surface lines are decorative and are not asserted; WCAG 1.4.11 exempts them.

### Secondary text reaches 4.5:1 on every ground

`textSecondary` clears 4.5:1 on the page, the raised, sunken and quiet surfaces and the captured row's ground in both modes.

### Control boundaries reach 3:1

`controlBorder` clears 3:1 on the same five grounds in both modes.

### Each tone's text holds on its own ground

The soon, available, locked, captured and missed foregrounds each clear 4.5:1 on their own ground in both modes.

### The missed bar reaches 3:1 on the page

`chartMissed` clears 3:1 on the page background in both modes, so the Value chart's missed bar and its swatch stay visible.

### The overlap card's text holds on the section ground

Today is rendered in each theme and every `Text` inside an overlap card is read back with its own style colour; each clears 4.5:1 on the section ground.

The light theme's secondary text does not clear it there, which is why the card's body is neutral-300 as in the PWA.

### A selected chip's label holds on its fill

The theme's selected chip fill is a step of the accent ramp, and the label and check mark colour on it clear 4.5:1 in both modes.

### A selected segment's label holds on its fill

The theme's selected segment fill is a step of the accent ramp, and its label colour clears 4.5:1 on it in both modes.

### An unselected chip's outline reaches 3:1

An unselected chip's outline clears 3:1 and its label 4.5:1 on each of the five grounds in both modes.

## Store

`snapshot_store_test.dart` covers persistence and the app store ([[mobile-architecture#The snapshot store]], [[mobile-architecture#The store]]).

### A snapshot round-trips through shared preferences

Saving the sample household and loading it back yields equal JSON, under the `app-data` key.

### A corrupt snapshot starts the app empty

A record that is not JSON loads as null rather than throwing.

### The app store resolves today's instances

After `load` the store reports its cards, the first use-soon credit, the claimable total, the next reset and the next opening for the fixed date, all from the domain selectors.

`app_store_test.dart` is the mutation suite ([[mobile-architecture#The store#Mutations]]): plain Dart over a `MemorySnapshotStore` with the clock fixed at 16 September 2026, counting notifications. After every mutation the saved snapshot and the store's snapshot are the same JSON, so a write that skipped the store would fail every case.

### A template becomes a card with its credits

`addCardFromTemplate` on an empty household adds one card with the template's issuer and product, the given label and anniversary, and one benefit per template credit; one notification.

Both card timestamps are the clock's instant, and each benefit has a distinct id and the new card's id.

### A blank template takes the typed issuer and product

The blank template with `issuer` and `product` overrides yields a card named by them with no benefits, and its anniversary defaults to today.

### Card patches stamp updatedAt

`updateCard` applies the `copyWith` patch (label, last four), keeps `createdAt` and stamps `updatedAt` with the clock; one notification.

### Mute is the member's and archive is a card patch

`toggleCardMute` adds then removes the card in the saved `MemberPreferences` and leaves the household's JSON as it was; `archiveCard` sets `archived`, after which `hasCards` is false; three notifications.

### Deleting a card cascades

With two cards, three benefits and three claims, `deleteCard` leaves the other card, its benefit and its claim only; one notification.

### A benefit draft gets its identity from the store

`addBenefit` keeps the draft's fields but replaces its id and sets both timestamps to the clock's instant, appending it after the existing benefits.

### Benefit patches stamp updatedAt

`updateBenefit` applies a name and value patch and stamps `updatedAt`; one notification.

### Muting a credit leaves the household alone

`toggleBenefitMute` saves the credit's id in the member's preferences, leaves the household's JSON unchanged, marks the instance muted, and notifies once.

### Opting out stamps the credit and reactivating resumes it today

`optOutBenefit` stamps `optedOutAt` and the credit leaves `instances`; `reactivateBenefit` clears it, sets `trackedFrom` to today, and the credit returns. Each notifies once.

### Enrollment is confirmed and revoked

On a benefit that requires enrollment, `confirmEnrollment` stamps `enrolledAt` and the credit leaves the locked list; `revokeEnrollment` clears it to null and the credit is locked again.

### A spend threshold is confirmed and revoked

On a benefit gated behind $5,000 of spend, `confirmSpend` stamps `spendMetAt` with the clock's instant and the credit leaves the locked list; `revokeSpend` clears it to null and the credit is locked again; two notifications.

### Deleting a benefit takes its claims

`deleteBenefit` removes the benefit and its claims and leaves the other benefit's claim.

### A claim defaults to what is left

On a $25 credit with $10 claimed, `claim` without an amount records $15 with the note, the instance's benefit id and cycle key, and the clock's instant, and the instance becomes captured.

### A partial claim records its amount

`claim` with an amount records that amount with no note, and the instance's remaining value drops by it.

### Removing one claim keeps the cycle's others

`removeClaim` deletes one claim and leaves the cycle's other claim and the older cycle's; `unclaim` then clears the whole cycle and leaves the older one.

### Settings patches keep the rest

`updateSettings` changes the horizon and theme; `updatePreferences` turns reminders on at a new time, keeps the floor, saves the preferences apart from the snapshot, and leaves the horizon as set.

### Opted-out credits stay off the lists

`instances` and `instanceFor` leave out a credit with `optedOutAt`, so it reaches no screen list; its value is still in the opted-out figure.

### A write before load wins

With a snapshot store whose load is held open, `addCardFromTemplate` lands first; when the load resolves the store still holds the new card, that card is what was saved, and `loading` is false, with one notification per event.

## UI state

`ui_state_test.dart` covers the transient ui notifier as plain Dart ([[mobile-architecture#State management#UI state]]).

### Sheets track an id and notify once

Opening a credit sets the benefit id and notifies once, opening another replaces it, closing clears it, and closing an already closed sheet notifies nobody.

### The compare sheet is the other one

The overlap label is opened and cleared the same way, one notification each, and repeating either is not a change.

## Credit sheet

`credit_sheet_test.dart` opens the sheet through `UiState` on a household with a $100 Resy credit ($10 then $20 logged), locked Equinox, captured Uber, spend-gated Dell and rolling Global Entry credits, dated 16 September 2026 ([[mobile-architecture#The credit sheet]]).

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

### Opting out from the sheet closes it and leaves Today

"Opt out — I won't use this" closes the sheet, opts the credit out with the same snackbar as the swipe, and the credit's row leaves Today.

### A locked credit unlocks from the sheet

A locked credit shows the "Not enrolled." note and no logging; "I've enrolled — unlock this credit" stamps `enrolledAt` and the full-amount button appears.

### A rolling credit is eligible now and restarts when claimed

Global Entry reads "Eligible now — the clock restarts when you claim it"; marking the full $120 used closes the sheet, and reopening it reads "Eligible again Sep 16, 2030" with no logging.

### A spend-gated credit unlocks from the sheet

The $1,000 Dell bonus behind $5,000 of spend shows "Unlocks after $5,000 spend this year." and no enrollment note or logging; "I've reached it — unlock" stamps `spendMetAt`, says "Dell Bonus unlocked." and the full-amount button appears.

### The value bar splits the current window

Resy's sheet, $30 logged of $100, draws a `ValueBar` of $30 earned and $70 available with no Missed segment, and no "Claimed so far" progress bar; logging $20 with the sheet open moves it to $50 and $50.

### The value bar puts a locked credit in opt out

The un-enrolled $300 Equinox credit's bar is $300 opt out and nothing else. An opted-out credit never opens in the sheet, so its opt out is pinned in [[tests#Value breakdown]].

### The value bar shows a captured credit as earned

The fully used $15 Uber credit's bar is $15 earned and nothing else.

### A spend-gated credit has no value bar

The Dell bonus, gated behind $5,000 of spend, opens its sheet with no `ValueBar`.

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

### A drag left parks the row open on Silence and Opt out

A 120 pixel drag left parks the row at minus 168 with "Silence" and "Opt out" side by side, each at least 48dp. Tapping either fires it and closes the row; a tap elsewhere closes it without firing.

### A locked row offers both left actions

A locked row dragged left parks open on "Silence" and "Opt out" like an open one.

### A captured row has nothing to log

A captured row dragged right stays at rest and logs nothing.

### Every gesture is a semantics action

The row's semantics node carries custom actions "Log the full credit", "Silence" and "Opt out"; performing each fires the matching callback with the row still at rest.

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

### Opting out has an Undo that brings the credit back

`optOut` takes Resy off the store's instances and says "Opted out of Resy Dining Credit. Reactivate it from the card’s setup." with "Undo opting out of Resy Dining Credit"; the Undo brings it back without setting `trackedFrom`.

### Unlocking has an Undo that revokes

`confirmEnrollment` stamps `enrolledAt`, says "Equinox Credit unlocked." with "Undo unlocking Equinox Credit", and the Undo clears it.

### Removing and clearing report without an Undo

`removeClaim` says "Removed $30 from …" and `unclaimAll` "Cleared what was logged against …", each with no action.

## Snackbar

`snackbar_test.dart` pumps `SnackbarHost` bare with the test clock, then the whole app at 1280 and 402 ([[mobile-architecture#Undo and the snackbar]]).

### An undo stays up for eight seconds

Without assistive technology, a message with an action is still there at 7 seconds and gone at 9.

### Assistive technology keeps an undo for twenty seconds

With `MediaQuery.accessibleNavigation` on, a message with an action is still there at 19 seconds and gone at 21.

### A plain message leaves sooner

A message without an action shows no Undo, is there at 3 seconds and gone at 4, with or without assistive technology.

### Focus pauses the timer and leaving restarts it

Focusing the Undo at 5 seconds holds the bar through 30; blurring restarts the full 8, so it is there at 37 and gone at 39.

### The pointer pauses the timer too

A mouse over the bar at 5 seconds holds it through 30; moving away restarts the 8 the same way.

### The undo button says what it undoes

An action with a semantics label yields a button found by "Undo logging Uber Cash" whose visible text is "Undo"; tapping it acts once and dismisses the bar.

### A newer message replaces the older

A second message at 6 seconds replaces the first and is still up 6 seconds later, past the first's 8, then gone after its own 8.

### A swipe down dismisses without acting

Dragging the bar down removes it and clears the message, and the action's callback is not called.

### A screen reader can dismiss it too

The bar exposes a semantics dismiss action; performing it removes the bar without calling the action.

### The snackbar centres on the content column

At 1280 with the sample household, the bar's centre is the content column's centre, which is not the window's, and it is no wider than the column.

### The snackbar sits above the bar on a phone

At 402 the bar's bottom edge is at or above the `NavigationBar` and it is centred on the phone column.

## Sign-in

`sign_in_test.dart` launches the app with a `Session` over a fake `AuthService` and a `MemoryIntroStore`, and follows the router's redirect ([[mobile-architecture#Sign-in]]).

### First launch shows the slideshow

Signed out with the intro unseen, the app opens on `WelcomeScreen`; Skip goes to `SignInScreen` and sets `introSeen`.

### Finishing the slideshow leads to sign-in

Next through the slides to "Get started" goes to sign-in and sets `introSeen`.

### A returning signed-out launch goes to sign-in

With the intro seen the app opens on sign-in, never the slideshow; "Learn more" replays the slideshow, and Skip returns to sign-in.

### A signed-in launch opens Today

Signed in, the app opens on Today with no sign-in screen.

### Signing in opens Today

"Continue with Google" and "Continue with Apple" each call their provider once on the auth and land on Today.

### Signing out returns to sign-in

"Sign out" in Settings calls the auth once and returns to sign-in, not the slideshow.

### A failed sign-in says so

With `UnconfiguredAuth`, "Continue with Google" stays on sign-in and shows that sign-in is not set up.

### Staging Firebase options are built in

`firebase_config_test.dart` checks that an iOS and an Android build with no `--dart-define`s get staging's Firebase app id, API key, project and bundle id, and that macOS gets none.

## Api store

`api_store_test.dart` drives the store in its service-tier mode over a fake api that dedupes claims by idempotency key as the real one does, with an in-memory cache and outbox ([[mobile-architecture#The store#The service tier]]).

### Offline, the app starts from the cache

With the api unreachable, `load` shows the cached household and reports offline; once it is back, `refresh` shows the server's and writes it to the cache.

### An offline claim is pending, kept and sent once

A claim logged offline shows at once and is pending, and a new store over the same cache and outbox still shows it pending. Three concurrent flushes once the api is back post it once, empty the outbox and swap in the server's claim.

The same key queued and flushed again after it was stored leaves one claim on the server.

### Opting out and reactivating send the credit's state

Against the fake api, opting out sends only `{optedOutAt}` and reactivating only `{optedOutAt: null, trackedFrom}` to the state route; no terms are sent, and the refreshed household carries both.

### Offline edits are refused with a message

Renaming a card offline returns false, sets `offlineMessage`, changes nothing locally or on the server, and makes `canEdit` false; online the same rename lands. In the app, typing into the card editor offline shows the message in the snackbar.

### A cache of another version is discarded

A cache written with the previous `householdCacheVersion` is cleared on load, leaving no household, while the queued claim stays in the outbox and is posted when the api is back.

## Member mutes

`member_mutes_test.dart` drives mutes in the service-tier mode over a fake api that stores them and can hold or refuse `setMute`, pinning [[mobile-architecture#The store#Member mutes in flight]].

### Toggling twice mutes then unmutes

One `toggleBenefitMute` leaves the credit muted on the device and the server, and a second unmutes it on both; `toggleCardMute` does the same for a card. Before #352 the refresh and a local toggle cancelled out.

### In flight shows the requested state

While `setMute` is held, `isBenefitMuted` (and the instance's `muted`) or `isCardMuted` reports the requested state and `isMutePending` is true; once it completes, `isMutePending` is false.

### A refused or offline mute keeps the old state

When `setMute` throws `ApiError` or the api is offline, the credit or card ends unmuted, `isMutePending` is false and `problem` is set (`offlineMessage` when offline).

### An accepted mute survives a failed refresh

When the mute lands but the api drops before the follow-up refresh, the device still shows the requested state.

### Local mode flips at once

Without an api, `toggleBenefitMute` mutes before its future completes and `isMutePending` is never true.

### Card editor and row bell are disabled in flight

"Silence every credit" on the card editor and the bell on a Today row sit at the requested state with no callback while `setMute` is held, and are enabled again once it completes.

## Notification levels

`notification_levels_test.dart` drives the per-member level control over a fake api that stores mutes and last calls and can hold or refuse the level route, pinning [[mobile-architecture#The store#Notification levels in flight]].

### Each level goes to the api

`setNotificationLevel` to Last chance, Silence and Periodically each leaves the api's mute and last-call ids as `withLevel` says, and `notificationLevel` reads the level back.

### A level in flight shows the request

While the level route is held, `notificationLevel` reports the requested level and `isMutePending` is true; once it answers, it is false and the level stays.

### A refused level returns to the old one

A refused or offline level route leaves Periodically, nothing pending, and `problem` set (`offlineMessage` when offline).

### Unsilencing returns to Last chance

From Last chance, the row bell's `toggleBenefitMute` silences and a second toggle returns the credit to Last chance, because Silence keeps last call.

### A local level is written at once

Without an api the level shows before its future completes, is never pending, and lands in the saved preferences.

### The sheet has the control and no ladder

The credit sheet shows "Notification levels" with Periodically, Last chance and Silence, Periodically selected with its note "23 days, 7 days and the last day before it shuts", and no "Reminder ladder", "Last call only" or "Silence this credit".

### The sheet's control waits for the server

Choosing Last chance with the route held shows it selected with no `onSelectionChanged`; after the answer it is selected and enabled with "Only on the last day", and the snackbar's Undo restores Periodically on the server.

### A refused level on the sheet is enabled again

When the route refuses, the sheet shows Periodically selected and enabled.

### A silenced card shows Silence, disabled

With the credit's card muted, the control shows Silence with no callback and the note "The whole card is silenced. Unsilence it on the card to choose."

### A viewer sets their own level

Someone who can only view the card chooses Last chance on the sheet and it is sent and selected, since the level is their own.

### The credit editor offers the same levels

The credit editor shows "Notification levels" in place of the two switches; choosing Silence mutes the credit on the server and Periodically clears it.

## System and user cards

`system_cards_test.dart` drives Cards, the editors and the conversion over the fake api with a Gold from the catalogue, a claim on its Uber Cash, and a Freedom of the household's own ([[mobile-architecture#System and user cards]]).

### Cards groups system and user cards

Cards names "Kept up to date" with the Gold under it and "Maintained by you" with the Freedom under it.

### A system card's terms are read-only

The Gold's editor has a read-only fee, no "Add" and an editable label; "Change the terms" opens the conversion screen, which says it will no longer update automatically and keeps its claims, and nothing has been converted yet.

### Conversion keeps the claims

"Make it mine" converts the Gold once, opens its editor with an editable fee, and leaves the captured total and the claim as they were; back on Cards the Gold is under "Maintained by you".

### A second card of a product is numbered

Adding a Gold from the api's catalogue to a household holding one proposes "American Express Gold (1)"; the catalogue comes from the api with `blank` last.

## Card access

`card_access_test.dart` gives the caller a Gold of their own and Alex's Platinum, labelled "Platinum", shared at view or at record over the fake api ([[mobile-architecture#Card access]]).

### A card shared to view logs nothing

Alex's Uber Cash row has no log or opt-out action but keeps its bell, while the Gold's row logs. Its sheet is headed "PLATINUM · ALEX" and has no logging and no "Edit this credit", only the levels.

A claim attempted anyway is refused with "You can view Alex’s card but not change it." in the snackbar, and nothing is posted.

### A card shared to record logs but stays the owner's

At record the Uber Cash row logs and the sheet's "Mark the full" posts the claim. The card editor's label, fee and renewal date are read-only, archive, delete and "Change the terms" are gone, and it says "Only Alex can change this card.".

A rename attempted anyway is refused with that sentence in the snackbar, and the label stays.

### Cards names whose cards they are

Cards puts the Gold above "Alex’s cards" and Alex's card under it as "Platinum · Alex", with no edit link at view but the add button for your own. Today's rows name it "Platinum · Alex" too.

### Labels count only your own cards

While Alex shares an unlabelled Platinum, adding your own Platinum proposes no label; once you own one, the next proposes "American Express Platinum (1)".

### An offline launch keeps the access and the names

With the api unreachable, a store over the `shared_preferences` cache the last launch wrote still says `record` for Alex's card and `owner` for the Gold, and names the Platinum "Platinum · Alex".

### Without an api every card is yours

A local store says `owner` for Alex's card and names it "Platinum" alone, and its editor is fully editable, with archive, delete and "Change the terms".

## Household sharing

`household_sharing_test.dart` drives Settings, the share sheet, the join screen and the router over the fake api of `test/support/fake_api.dart`, with `share` captured ([[mobile-architecture#Household sharing]]).

The caller owns a Gold and a Sapphire Reserve; Bob is someone they share with and Alex someone who shares a Gold with them.

### Sharing all your cards opens the share sheet on iOS

"Share your cards" at its defaults, View and All cards, then "Create and share" makes one invite at `view` to all cards, shares only its link as a URI anchored to the button, and shows the code.

### Sharing your cards on Android sends the message

The same steps on Android share the reward message with the code and the link on its own last line, the title and subject "Join my household on HelpMe Reward" and the app icon as a PNG thumbnail.

### Chosen cards send their ids

"Can record usage" and "Chosen cards" with both cards ticked make one invite at `record` with the two card ids, and open the share sheet.

### The join screen says who shares what

An invite to two of Alex's cards at record reads "Alex wants to share 2 of their cards with you." and "You’ll be able to view them and record what you use.".

Accept sends the code and lands on Today with Alex's Uber Cash and "You can see Alex’s cards now.".

### An invite to all cards to view says so

The default offer reads "Alex wants to share all their cards with you." and "You’ll be able to view them.".

### Used, expired, own and already-shared codes say why

An expired, a used and an unknown code each say so when read, with no Accept. Accepting your own invite, or one from someone who already shares with you, says why, and the screen stays.

### Changing a share updates its line

Bob's line under "People who see your cards" reads "All cards · View"; his sheet's "Can record usage" and Save send the change and the line reads "All cards · Can record usage".

### Stopping sharing asks first

Bob's sheet's "Stop sharing" asks "Stop sharing with Bob?"; confirming tells the api, removes his line and says nobody sees your cards yet.

### Stopping seeing removes their cards

Alex's line under "Shared with you" reads "All cards · View"; "Stop seeing their cards" tells the api, and Alex's Uber Cash is gone from the store and from Today without a restart.

### A code opens the join screen

"Have an invite code?" with a lower-case code opens the join screen for it in capitals.

### A link opens the join screen

Opening `/invite/ZZZZ2222` shows the join screen for that code.

### A signed-out link joins after sign-in

Signed out, the link shows sign-in; signing in lands on the join screen for the code.

## Api config

`api_config_test.dart` covers the build-time define ([[mobile-architecture#Api config]]). Each case skips itself in the run it does not apply to, so the verify gate and `make check` run the file a second time with the define.

### The define sets the api base URL

Run with `--dart-define=API_BASE_URL=https://example.test`, `ApiConfig.baseUrl` is `https://example.test`.

### Without the define the app talks to staging

Run without it, `ApiConfig.baseUrl` is `ApiConfig.stagingUrl`.

## End to end

`integration_test/app_test.dart` drives the real app on a simulator or emulator through `make e2e` ([[mobile-architecture#Make targets]]); it is not part of the verify gate.

### A fresh install launches to the first-run screen

Booting the app with an empty snapshot store on a device reaches the Today screen and shows "Add a card to start tracking its credits", proving the shell, the store and the screen wire together outside the test harness.

### The parity flow runs through every screen

One pass from an empty store through adding a card, logging, undoing, swiping and reading every screen, on a real simulator or emulator.

The steps: add the Platinum from the catalogue for Kathy and land on its editor; see its Walmart+ Membership Credit, a monthly credit with no enrollment, on Today; log it from the sheet and undo it from the snackbar; log it by swipe; find it under Credits > Captured and as $12.95 captured on Value; mute the card from the Cards menu; open the credit's editor from its sheet; and choose Dark in Settings, which darkens the theme.

## Push

`push_test.dart` drives `PushController` and the app over fakes of FCM and the api; `push_config_test.dart` reads the native files ([[mobile-architecture#Push]]).

### A granted permission registers the device

`enable` prompts once and registers the token with the installation id, `ios` and `Europe/London` from the fake.

### A refused permission registers nothing

A denial returns the refusal sentence and the api holds no device.

### A refreshed token registers again

After a refresh the api holds only the new token; `unregister` then leaves it empty.

### Turning reminders on asks once

In Settings the switch prompts once, turns reminders on and registers; switching off turns them off and removes the device.

### A refusal is reported in the snackbar

With a denial the switch stays off and the snackbar reads "Reminders stay off until notifications are allowed."

### Signing out deletes the registration

Sign out removes the device from the api before the auth signs out.

### Settings shows the summary and sends a delayed test

With reminders on, Settings shows "3 reminders scheduled. Next on Oct 31: $10 expires tonight." from the api. The test button asks for a 5-second delay and shows "Sending in 5 seconds…" while the request is open, then "Test notification sent."

### A tapped notification opens its screen

A tap whose data names `/cards/card-1` opens the card editor, from the background and when the tap launched the app.

### A notice in the foreground shows in the snackbar

A push that arrives while the app is open shows its title in the snackbar.

### iOS declares push

`Runner.entitlements` has `aps-environment` and `Info.plist` lists `remote-notification` under `UIBackgroundModes`.

### Both platforms answer the zone channel

`AppDelegate.swift` and `MainActivity.kt` both name the `com.helpmebrands.reward/timezone` channel and its `current` method.
