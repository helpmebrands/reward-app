# Mobile architecture

Three layers, dependencies pointing inward: UI widgets depend on logic, logic on data and the domain, and the domain on nothing. The domain is the Dart package in `packages/domain`, shared with the service tier.

Created with `flutter create --org com.helpmebrands --project-name reward --platforms ios,android` and resolved through the root pub workspace (`resolution: workspace`), so one `dart pub get` covers the app, the domain and the service. iOS dependencies come through Swift Package Manager; there is no Podfile.

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

