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

## End to end

`integration_test/app_test.dart` drives the real app on a simulator or emulator through `make e2e` ([[mobile-architecture#Make targets]]); it is not part of the verify gate.

### A fresh install launches to the first-run screen

Booting the app with an empty snapshot store on a device reaches the Today screen and shows "Start with one card", proving the shell, the store and the screen wire together outside the test harness.
