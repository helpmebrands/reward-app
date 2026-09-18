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

### A fresh install shows the first-run screen

With no snapshot the screen shows "Start with one card" and no rows.

## Store

`snapshot_store_test.dart` covers persistence and the app store ([[mobile-architecture#The snapshot store]], [[mobile-architecture#The store]]).

### A snapshot round-trips through shared preferences

Saving the sample household and loading it back yields equal JSON, under the `app-data` key.

### A corrupt snapshot starts the app empty

A record that is not JSON loads as null rather than throwing.

### The app store resolves today's instances

After `load` the store reports its cards, the first use-soon credit, the claimable total and the next reset for the fixed date, all from the domain selectors.

