# Mobile architecture

Three layers, dependencies pointing inward: UI widgets depend on logic, logic on data and the domain, and the domain on nothing. The domain is the Dart package in `packages/domain`, shared with the service tier.

Created with `flutter create --org com.helpmebrands --project-name reward --platforms ios,android` and resolved through the root pub workspace (`resolution: workspace`), so one `dart pub get` covers the app, the domain and the service. iOS dependencies come through Swift Package Manager; there is no Podfile. The iOS deployment target is 15.0 in `ios/Runner.xcodeproj` and the macOS one is 12.0 in `macos/Runner.xcodeproj`, the lowest Xcode 27 accepts; the templates' 13.0 and 10.15 no longer build. The Flutter version is pinned in `.fvmrc` at the root and every local Flutter or Dart command runs through FVM (`fvm flutter`, `fvm dart`); CI reads the same file ([[infra-tests#Infrastructure config#Flutter version is pinned once with FVM]]).

## Layers

The layout under `apps/mobile/lib/` follows Flutter's recommended architecture, with the domain kept outside the app entirely.

- **UI** (`lib/screens/`, `lib/widgets/`, `lib/shell/`): Material widgets on the Nocturne tokens. No widget hard-codes a colour; every one is read from the theme extension. Every component ships with a Widget Preview. The shell directory holds the router, the app shell with its width class, and the store scope ([[mobile-architecture#Navigation]], [[mobile-architecture#Responsive layout]]).
- **Logic** (`lib/logic/`): the app store ([[mobile-architecture#The store]]), which calls [[domain]] selectors and exposes what a screen renders, under the rules in [[mobile-architecture#State management]].
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

## State management

The app manages state with Flutter's own primitives and adds no state management or injection package: `ChangeNotifier` and `ValueNotifier` hold state, the builder widgets subscribe, and `setState` covers what one widget owns.

Decided in issue #136. The app has one snapshot, a handful of derived views computed by [[domain]] selectors, and a dependency surface the team keeps at zero. Flutter's architecture guidance (2024/2025) builds its view models on `ChangeNotifier` and reaches for `provider` only to inject them; this app does the injection by hand. `provider`, `riverpod`, `bloc`, `get_it`, `signals` and the like are not added even where they are Flutter Favorites, and a skill step that says to register a dependency in `provider` or `get_it` is overridden here.

### Choosing the primitive

Three kinds of state, each with its own home; the rule is to pick the smallest one that serves every widget that needs the value.

- **Widget-local state** (a text field's draft, whether a row is expanded, an animation): `StatefulWidget` and `setState`. It never leaves the widget.
- **Shared transient state** (which credit sheet is open, the household filter, the width class): a `ValueNotifier` owned by the nearest common ancestor and read through `ValueListenableBuilder`. This is what `UiProvider` holds in the PWA ([[architecture#UI state]]).
- **Application state** (the snapshot, today, the derived views): the store ([[mobile-architecture#The store]]), a `ChangeNotifier` that is the app's view model in the MVVM sense, read through `ListenableBuilder`.
- **Promote only on demand**: state moves up one level when a second widget needs it, never pre-emptively. The width class is computed once in the shell and handed down as a value ([[mobile-architecture#Responsive layout]]).

### Notifier rules

The store and every later notifier follow Flutter's guidance for view models: the logic lives in the notifier, none in the widget, and data flows one way.

- **Unidirectional**: state flows down through getters, events flow up as method calls (`replaceAll` today, `claim` later). A widget never mutates what it reads.
- **Immutable exposure**: fields are private and getters return values or unmodifiable views, so nothing can change the store without a notification. The domain models are immutable already.
- **One notification per change**: mutate every field, then `notifyListeners()` once. Never notify during `build`, and never after `dispose`.
- **Async actions**: an action the UI must track (in flight, failed, done) is wrapped in the guide's Command pattern, a small `ChangeNotifier` with `running`, `error` and an `execute` that ignores re-entry. `load` gets by with a `loading` flag because it is the only async action; the api client brings the first Command.
- **No rules in the store**: derived views are [[domain]] selectors called on every read, as today. The notifier decides when to notify, not what is true.

### Wiring and lifecycle

Notifiers reach widgets by constructor until the tree is deep enough to hurt, then through an `InheritedNotifier`; whoever creates a notifier disposes it.

- **Constructor injection first**: `RewardApp(store:)` today. Tests and previews build the store on `MemorySnapshotStore` with a fixed clock, which is the guide's "make fakes" recommendation in practice.
- **A scope above the router**: `AppScope` is an `InheritedNotifier<AppStore>` wrapped around `MaterialApp.router`, and `AppScope.of(context)` in a route builder is how a screen gets the store; `TodayScreen` still takes it as a constructor argument so tests and previews build it bare. `of` is the only place a widget looks the store up; there is no global.
- **Builders as low as the change**: wrap what changes, not the page around it, and pass a static subtree as `child` so it is not rebuilt. A screen that is all derived views wraps once, as Today does. `ValueListenableBuilder` for one value, `ListenableBuilder` for a notifier, `Listenable.merge` when a widget depends on two.
- **Owner disposes**: a `State` that creates a `ValueNotifier` disposes it in `dispose`; the store is created in `main` and lives as long as the app. `addListener` in `initState` paired with `removeListener` in `dispose` is for side effects only (navigation, a snackbar); rendering goes through builders.
- **Tests**: a notifier is plain Dart, tested without a widget tree by asserting its getters and counting notifications; widgets are tested against a real store on fakes ([[mobile-tests#Store]]).

## Navigation

Decided in issue #136: routing is `go_router`, published by flutter.dev, with the four destinations in a `StatefulShellRoute.indexedStack` and every screen addressable by path as in the PWA. No other routing package and no raw Navigator 2.0.

The Flutter team's architecture guidance recommends `go_router`, and the package README declares it feature-complete: bug fixes and stability, no new features planned. For code an agent writes that is an asset, not a risk. Version 18 requires Flutter 3.44, the pinned toolchain. Screens are addressable because a tapped reminder must open the screen it names, as the PWA's shell does on the worker's `navigate` message ([[architecture#The shell and routing]]).

### Routes and the shell

The route table mirrors the PWA's nine routes, with the four tabs as branches of one shell route and the editors and Settings pushed above it.

- **Paths**: `/` Today, `/credits`, `/cards` and `/value` are the shell branches, the constants in `lib/shell/router.dart`; `/cards/new`, `/cards/:id`, `/benefit/:id` and `/settings` will be full-screen routes above the shell, and `errorBuilder` the not-found screen, when those screens arrive. Today Credits, Cards and Value render `StubScreen`, a heading and one line, so the branches are real before the screens are.
- **The shell** is `StatefulShellRoute.indexedStack` whose builder renders `AppShell`: the `NavigationBar` or `NavigationRail` for the width class ([[mobile-architecture#Responsive layout]]) around the content column, keeping each tab's scroll position across switches. The four `Destination`s are one list the bar and the rail both draw, so the order cannot differ.
- **The credit sheet is not a route**: as in the PWA, the shell shows one modal sheet whichever tab opened it, driven by the shared transient state, so the URL stays on the tab beneath.
- **Typed by hand, not by codegen**: paths are constants and each parameterised route has a helper such as `cardPath(id)`. `go_router_builder` is not added because it brings `build_runner` into a workspace with no code generation, and nine routes do not need it. Revisit if the table grows.
- **Redirects read the store**: `refreshListenable` is the `AppStore`, so a `redirect` re-evaluates on every notification with no second state holder. There is no redirect today; the first will come with the api sign-in.
- **Notification taps go by path**: the reminder payload carries the route to open and the handler calls `go`, the counterpart of the PWA's `navigate` message.
- **Not added**: `app_links` (third-party, needs approval, and there are no associated domains or URL schemes to serve), `auto_route`, and hand-written `RouterDelegate` code.

### Transitions and back

Page transitions stay at the framework defaults, which on the pinned Flutter (3.44) means predictive back on Android with `FadeForwardsPageTransitionsBuilder` for a plain push, and the Cupertino slide on iOS.

- **No `pageTransitionsTheme` in the theme**: pinning a builder opts out of predictive back. The first-party `animations` package is not added until [[design#Screens]] asks for a motion pattern the defaults lack; none does today.
- **The manifest enables predictive back**: `android:enableOnBackInvokedCallback="true"` on the `<application>` element, without which the gesture does not animate.
- **Custom back handling uses `PopScope`**: a sheet or editor that must intercept back (an unsaved draft) does so through `PopScope` and `onPopInvokedWithResult`, never `WillPopScope`, so the predictive gesture keeps working.
- **Per-route transitions** go through `CustomTransitionPage` in a route's `pageBuilder`, and only where a screen calls for one.
- **Tests**: the route table is built by a function that takes the store, so a widget test pumps `MaterialApp.router` on a `MemorySnapshotStore` and asserts the screen a path renders; the shell tests in [[mobile-tests]] run at the three widths.

## Today screen

`TodayScreen` is the PWA's Today ([[design#Screens]]) as Material widgets. No editing yet; the actions arrive with the credit sheet.

It shows the header with the date, the headline counting only what is claimable, the use-soon rows with the reset countdown, up to three overlap cards on the section ground, the locked section with its own total, and the captured rows.

`CreditRow` draws every status in one of five tones from the token set (soon, available, locked, captured, missed), with the holder in the subtitle when the household has more than one card, and the claimed amount on a captured row. The headline number shrinks to fit the column rather than overflow. Every component has a Widget Preview in `lib/previews.dart`. Pinned by [[mobile-tests#Today]].

## Responsive layout

The app realises the product's three width classes ([[design#Responsive layout]]) with Flutter's own tools: `AppShell` computes the class and draws the navigation and the column, and each screen reads it to re-flow. Today's wider re-flow is open work.

`WidthClass` (compact, medium, expanded) carries the column width (402, 560, 720) and the screen padding (20, 24, 28) as enum fields, so no widget re-derives either. `AppShell` computes it once from `MediaQuery.sizeOf(context).width` against the 600 and 1024 thresholds and hands it down through `WidthClassScope`; `WidthClass.of(context)` falls back to compact outside the shell, so a screen in a test or a preview is the phone design. The content column is a top-centred `ConstrainedBox` (key `content-column`) capped at the class's width, the screens' own `ListView` is the only scrollable, and each screen pads itself with the class's padding. The four destinations are a `NavigationBar` in compact and a `NavigationRail` from medium, pinned to 80 wide with icons over labels, and 200 wide and extended from expanded; the rail's width is pinned by a `SizedBox` because its own minimum width lets a wide label push it out. Both draw the one `destinations` list, so the order and focus traversal cannot differ. Today pairs the overlap cards from medium and becomes a two-column body from expanded with the headline spanning both; the widget order stays the phone's so `Semantics` reads the same at every width. Pinned by [[mobile-tests#Shell]].

A macOS build is the way to see the medium and expanded classes without a tablet, which is why macOS is a local run target and not a release target ([[mobile-architecture#Make targets]]).

## Accessibility

The app carries the product's WCAG 2.2 AA intent ([[design#Accessibility]]) in Flutter terms; the theme's tokens and Material's 48dp targets are in place, and the scaling and contrast proofs are open work.

- **Text follows the platform size**: nothing overrides `MediaQuery.textScaler`, no text is clipped, and controls do not overlap at 200%; Today's number shrinks to fit its column instead of overflowing. Pinned, once written, by widget tests at a 2.0 scale factor.
- **Contrast comes from the tokens**: secondary text clears 4.5:1 and control borders 3:1 on every ground in both modes, checked over the theme extension the way `contrast.test.ts` checks `tokens.css`, so a copied token cannot drift.
- **Every gesture has a route**: when swipe actions arrive with the credit sheet, each has a button or a `Semantics` action a screen reader and a switch can reach, as the PWA's table in [[design#Accessibility]] lists.
- **Orientation is never locked** and the compact class covers a landscape phone.

## Make targets

`apps/mobile/Makefile` is the app's script runner, the counterpart of the PWA's `package.json` scripts, and every recipe goes through `fvm flutter` or `fvm dart` so the SDK is the one in `.fvmrc`.

`make init` installs FVM if needed, fetches the pinned SDK, resolves the workspace and runs `flutter doctor`. `make build ios|android|macos` produces a release build and a bare `make build` does the two store platforms, `make test` runs the widget suite and `make test ios` adds the e2e run, `make e2e [android]` runs `integration_test/` on a simulator or emulator it boots if needed, `make run` lists devices and asks for one because Flutter would otherwise silently pick the only booted simulator, `make run ios|android` boots a visible simulator or emulator, `make run macos` opens the app in a resizable window, and `make deploy VERSION=x.y.z` tags `develop` so the release workflow ships both stores ([[deployment#Pipeline]]). `scripts/pick-device.sh` does the device choosing for `e2e` and `run`. The README beside it lists every target; pinned by [[infra-tests#Infrastructure config#Mobile Makefile is the app's script runner]].

macOS is a local target only, added by issue #117 so the medium and expanded classes ([[mobile-architecture#Responsive layout]]) can be tried on a laptop: `apps/mobile/macos/` is the `flutter create` output on Swift Package Manager with no Podfile, both entitlements files grant `network.client` for the api client, and neither `deploy` nor the release workflow builds it; pinned by [[infra-tests#Infrastructure config#macOS is a local run target only]].
