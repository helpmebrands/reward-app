# Mobile architecture

Three layers, dependencies pointing inward: UI widgets depend on logic, logic on data and the domain, and the domain on nothing. The domain is the Dart package in `packages/domain`, shared with the service tier.

Created with `flutter create --org com.helpmebrands --project-name reward --platforms ios,android` and resolved through the root pub workspace (`resolution: workspace`), so one `dart pub get` covers the app, the domain and the service. iOS dependencies come through Swift Package Manager; there is no Podfile. The iOS deployment target is 15.0 in `ios/Runner.xcodeproj`, the lowest Xcode 27 accepts; the template's 13.0 no longer builds. The Flutter version is pinned in `.fvmrc` at the root and every local Flutter or Dart command runs through FVM (`fvm flutter`, `fvm dart`); CI reads the same file ([[infra-tests#Infrastructure config#Flutter version is pinned once with FVM]]).

## Layers

The layout under `apps/mobile/lib/` follows Flutter's recommended architecture, with the domain kept outside the app entirely.

- **UI** (`lib/screens/`, `lib/widgets/`): Material widgets on the Nocturne tokens. No widget hard-codes a colour; every one is read from the theme extension. Every component ships with a Widget Preview.
- **Logic** (`lib/logic/`): the app store ([[mobile-architecture#The store]]), which calls [[domain]] selectors and exposes what a screen renders.
- **Data** (`lib/data/`): persistence of the single `AppData` snapshot ([[mobile-architecture#The snapshot store]]) and, later, the api client. Nothing above this layer knows where a snapshot lives.
- **Domain** (`packages/domain`): the rules, imported as `package:domain/domain.dart`.

## Theme

`nocturneTheme(Brightness)` builds a Material 3 `ThemeData` from the [[design#Tokens and theming|Nocturne tokens]], one per brightness, and carries the full token set as a `ThemeExtension` so widgets read tones and surfaces by name.

The dark tokens are Nocturne verbatim; the light tokens are the PWA's derived light theme, copied from `apps/pwa/src/styles/tokens.css` so both apps render the same colours. Where Nocturne and Material disagree on looks, Nocturne wins: `ColorScheme.primary` is the accent, primary actions are outlined, the surfaces are the three Nocturne grounds, and there is no alarm red. Material supplies compact density and 48dp minimum targets. The app follows the platform brightness through `ThemeMode.system`; pinned by [[mobile-tests#Theme]].

## The snapshot store

The whole dataset is one record, as in the PWA: `SnapshotStore` loads and saves one `AppData`, and `SharedPreferencesSnapshotStore` keeps it as a JSON string under the PWA's `app-data` key through the `shared_preferences` package, a Flutter Favorite.

`load` never throws: a corrupt or missing record starts the app empty, because empty is recoverable and a crash is not. The JSON shape is the domain's `json.dart` codec ([[tests#Snapshot JSON]]), so a PWA export loads directly. `MemorySnapshotStore` serves tests and previews. Pinned by [[mobile-tests#Store]].

## The store

`AppStore` is a `ChangeNotifier` holding the snapshot and today's date, and the derived views the screens read. All of it is computed by [[domain]] selectors on every read; the store owns no rules.

The views are instances by urgency narrowed by the household filter, the missed ledger, the four totals, the use-soon, locked and captured lists, overlaps and the next reset.

Today is read from a clock on every access rather than captured at boot, because an app resumed the next morning must show that morning's deadlines ([[architecture#The app store#Keeping today fresh]] in the PWA). Tests and previews inject a fixed clock. `replaceAll` writes the snapshot back through the store; the screens never touch storage.

## Today screen

`TodayScreen` is the PWA's Today ([[design#Screens]]) as Material widgets. No editing yet; the actions arrive with the credit sheet.

It shows the header with the date, the headline counting only what is claimable, the use-soon rows with the reset countdown, up to three overlap cards on the section ground, the locked section with its own total, and the captured rows.

`CreditRow` draws every status in one of five tones from the token set (soon, available, locked, captured, missed), with the holder in the subtitle when the household has more than one card, and the claimed amount on a captured row. The headline number shrinks to fit the column rather than overflow. Every component has a Widget Preview in `lib/previews.dart`. Pinned by [[mobile-tests#Today]].

## Responsive layout

The app must realise the product's three width classes ([[design#Responsive layout]]) with Flutter's own tools; today it renders the compact class at every width, and the wider classes are open work.

A width class comes from `MediaQuery.sizeOf(context).width` against the 600 and 1024 thresholds, computed once in the shell and handed down, not re-derived in leaf widgets. The content column is a centred `ConstrainedBox` at 402, 560 or 720 logical pixels with 20, 24 or 28 of padding, and it is the only scrollable. The four destinations are a `NavigationBar` in compact and a `NavigationRail` from medium, 80 wide with icons over labels, 200 wide and extended from expanded, in the same order so focus traversal does not change. Today pairs the overlap cards from medium and becomes a two-column body from expanded with the headline spanning both; the widget order stays the phone's so `Semantics` reads the same at every width.

A macOS build is the way to see the medium and expanded classes without a tablet, which is why macOS is a local run target and not a release target ([[mobile-architecture#Make targets]]).

## Accessibility

The app carries the product's WCAG 2.2 AA intent ([[design#Accessibility]]) in Flutter terms; the theme's tokens and Material's 48dp targets are in place, and the scaling and contrast proofs are open work.

- **Text follows the platform size**: nothing overrides `MediaQuery.textScaler`, no text is clipped, and controls do not overlap at 200%; Today's number shrinks to fit its column instead of overflowing. Pinned, once written, by widget tests at a 2.0 scale factor.
- **Contrast comes from the tokens**: secondary text clears 4.5:1 and control borders 3:1 on every ground in both modes, checked over the theme extension the way `contrast.test.ts` checks `tokens.css`, so a copied token cannot drift.
- **Every gesture has a route**: when swipe actions arrive with the credit sheet, each has a button or a `Semantics` action a screen reader and a switch can reach, as the PWA's table in [[design#Accessibility]] lists.
- **Orientation is never locked** and the compact class covers a landscape phone.

## Make targets

`apps/mobile/Makefile` is the app's script runner, the counterpart of the PWA's `package.json` scripts, and every recipe goes through `fvm flutter` or `fvm dart` so the SDK is the one in `.fvmrc`.

`make init` installs FVM if needed, fetches the pinned SDK, resolves the workspace and runs `flutter doctor`. `make build ios|android` produces a release build, `make test` runs the widget suite and `make test ios` adds the e2e run, `make e2e [android]` runs `integration_test/` on a simulator or emulator it boots if needed, `make run` lists devices and asks for one because Flutter would otherwise silently pick the only booted simulator, `make run ios|android` boots a visible simulator or emulator, and `make deploy VERSION=x.y.z` tags `develop` so the release workflow ships both stores ([[deployment#Pipeline]]). `scripts/pick-device.sh` does the device choosing for `e2e` and `run`. The README beside it lists every target; pinned by [[infra-tests#Infrastructure config#Mobile Makefile is the app's script runner]].
