# Mobile tests

What the Flutter widget suites in `apps/mobile/test/` guard, run by the `flutter` job of the verify gate ([[deployment#Pipeline]]).

## Theme

`theme_test.dart` pins the theme to the Nocturne tokens so a re-theme is a deliberate token change rather than drift ([[mobile-architecture#Theme]]).

### Both themes carry the Nocturne token colours

Each theme's primary, surface, on-surface and scaffold colours are the `tokens.css` values for its mode, and each carries its token set as the extension.

Dark: `#9184d9`, `#232532`, `#e9e9ed`, `#161826`. Light: `#5d5294`, `#ffffff`, `#232532`, `#f3f5fe`.

### The app follows the platform brightness

With the platform reporting dark, the running app resolves the dark accent as primary and the dark "use soon" ground from the extension, so the system setting is what picks the theme.


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

With a spend-gated Dell bonus added to the sample household, the section is titled "Locked behind enrolment and spend", its note mentions a spend threshold, and the bonus is listed in it.

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

"Cards" is headed by the fee and captured totals; each card shows its issuer, label, fee, captured, net, percentage and days to renewal, the verdict headline and body, every tag and the edit button, and the catalogue button follows.

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

### Cards at 200% clips nothing

At a 2.0 text scale on 402 the screen raises no layout exception and every text's painted rectangle ends inside the width.

### Every control on a card has a label

Every button in the semantics tree has a label or a tooltip, and the menu is found by "Menu for …".

### No cards shows the first-run copy

With no cards the screen says "Start with one card", draws no card and still offers the catalogue.

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

The card carries that label, date, issuer and product, its benefits match `benefitsFromTemplate` by name, value and enrolment, and the "Added with N credits" snackbar shows.

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

Jim's card starts personal; tapping the "Business" chip writes `CardKind.business` and "Personal" writes it back.

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

### Enrolment, tracking and the switches write the benefit

"Needs enrolment" requires enrolment and shows "Not yet — the credit is locked."; "Enrolled" stamps it; "not a url" shows the address sentence and a real address is written; "Last call only" sets it.

"Opted out" stamps `optedOutAt` and leaves `active` alone. There is no "Track this credit" switch any more; the "Opted out" switch carries the note "You won’t use this. It stays off your lists and totals until you reactivate it."

### A rolling credit asks for its interval and hides the anchor

Choosing Rolling writes the cadence, removes the anchor chips and shows "Months between claims"; blank shows "Enter how many months between claims." and writes nothing; "48" writes it.

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

An empty household shows the note about what will appear and neither the ranks nor the leaks.

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

### Enrolment is confirmed and revoked

On a benefit that requires enrolment, `confirmEnrollment` stamps `enrolledAt` and the credit leaves the locked list; `revokeEnrollment` clears it to null and the credit is locked again.

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

### Silence and last call are switches on the sheet

The switch labelled "Silence reminders for …" mutes the benefit and "Last call only for …" sets `lastCallOnly`.

### Opting out from the sheet closes it and leaves Today

"Opt out — I won't use this" closes the sheet, opts the credit out with the same snackbar as the swipe, and the credit's row leaves Today.

### A locked credit unlocks from the sheet

A locked credit shows the "Not enrolled." note and no logging; "I've enrolled — unlock this credit" stamps `enrolledAt` and the full-amount button appears.

### A rolling credit is eligible now and restarts when claimed

Global Entry reads "Eligible now — the clock restarts when you claim it"; marking the full $120 used closes the sheet, and reopening it reads "Eligible again Sep 16, 2030" with no logging.

### A spend-gated credit unlocks from the sheet

The $1,000 Dell bonus behind $5,000 of spend shows "Unlocks after $5,000 spend this year." and no enrolment note or logging; "I've reached it — unlock" stamps `spendMetAt`, says "Dell Bonus unlocked." and the full-amount button appears.

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

### A reader sees no claim or edit controls

For a reader, Today's rows have no log action, the credit sheet has no logging section, and Cards has no add button or edit link.

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

## Household sharing

`household_sharing_test.dart` drives Settings, the join screen and the router over the fake api of `test/support/fake_api.dart`, with `shareText` captured ([[mobile-architecture#Household sharing]]).

### An owner shares an invite

The owner sees themselves as Owner; "Invite someone", "Can edit" and "Create and share" make one edit invite, share a text with its link and code, and show the code.

### Only an owner invites and removes

An editor sees the members but no invite button and no remove button.

### A code joins the household

"Have an invite code?" with a lower-case code opens the join screen for it in capitals; "Join this household" accepts it, lands on Today with "You joined the household." and the invite's role.

### A link opens the join screen

Opening `/invite/ZZZZ2222` shows the join screen for that code.

### A signed-out link joins after sign-in

Signed out, the link shows sign-in; signing in lands on the join screen for the code.

### Used, expired and unknown codes say so

An expired, a used and an unknown code each stay on the join screen with their own sentence.

### Leaving cards behind asks first

When the current household holds cards the join asks "Leave your cards behind?", and "Leave and join" repeats it with `confirmLeave` and lands on Today.

### An owner removes a member

The owner's remove button for a member, confirmed, removes them from the api and the list.

## Api config

`api_config_test.dart` covers the build-time define ([[mobile-architecture#Api config]]). Each case skips itself in the run it does not apply to, so the verify gate and `make check` run the file a second time with the define.

### The define sets the api base URL

Run with `--dart-define=API_BASE_URL=https://example.test`, `ApiConfig.baseUrl` is `https://example.test`.

### Without the define the app talks to staging

Run without it, `ApiConfig.baseUrl` is `ApiConfig.stagingUrl`.

## End to end

`integration_test/app_test.dart` drives the real app on a simulator or emulator through `make e2e` ([[mobile-architecture#Make targets]]); it is not part of the verify gate.

### A fresh install launches to the first-run screen

Booting the app with an empty snapshot store on a device reaches the Today screen and shows "Start with one card", proving the shell, the store and the screen wire together outside the test harness.

### The parity flow runs through every screen

One pass from an empty store through adding a card, logging, undoing, swiping and reading every screen, on a real simulator or emulator.

The steps: add the Platinum from the catalogue for Kathy and land on its editor; see its Walmart+ Membership Credit, a monthly credit with no enrolment, on Today; log it from the sheet and undo it from the snackbar; log it by swipe; find it under Credits > Captured and as $12.95 captured on Value; mute the card from the Cards menu; open the credit's editor from its sheet; and choose Dark in Settings, which darkens the theme.

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
