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

Today is read from a clock on every access rather than captured at boot, because an app resumed the next morning must show that morning's deadlines ([[architecture#The app store#Keeping today fresh]] in the PWA). The clock is a `DateTime` source, so today and the `createdAt`, `updatedAt`, `enrolledAt` and `claimedAt` instants a mutation stamps come from the same place; tests and previews inject a fixed one. The screens never touch storage.

### Mutations

The store carries the PWA's mutations ([[architecture#The app store]]); every one replaces the snapshot, notifies once and saves through the snapshot store.

Cards: `addCardFromTemplate`, `updateCard`, `toggleCardMute`, `archiveCard`, `deleteCard`. Benefits: `addBenefit`, `updateBenefit`, `toggleBenefitMute`, `confirmEnrollment`, `revokeEnrollment`, `deleteBenefit`. Claims: `claim`, `unclaim`, `removeClaim`. Settings: `updateSettings`, `updateNotificationSettings`. And `replaceAll`.

Every one builds the next snapshot with the domain types' `copyWith`, replaces the store's snapshot, notifies once and then saves it through the [[mobile-architecture#The snapshot store|snapshot store]]; the returned future completes when the save does, but the change is visible and announced before the first await, so a screen that ignores the future still redraws at once. Patches are functions of the current record (`updateCard(id, (card) => card.copyWith(...))`) rather than partial objects, and the store stamps `updatedAt` after applying them. `claim` without an amount records the instance's remaining cents, not the face value, so a second claim against a partly used credit cannot overshoot; `deleteCard` cascades to the card's benefits and their claims, `deleteBenefit` to its claims. `addCardFromTemplate` takes the holder, an optional nickname, last four, anniversary (today by default) and, for the blank template, the typed issuer and product. Ids are version 4 UUIDs from `lib/logic/ids.dart` with no package, the shape the PWA's `crypto.randomUUID()` gives, so ids from either app look alike.

A write that lands before `load` resolves is kept when the snapshot arrives, the PWA's "user's action wins" rule: nothing in the UI can write while `loading` is true, but a caller that does not wait must not have its change silently discarded. A mutation with no snapshot yet starts from `emptyAppData()`, the PWA's defaults in `lib/data/snapshot_store.dart`. Pinned by [[mobile-tests#Store]].

## State management

The app manages state with Flutter's own primitives and adds no state management or injection package: `ChangeNotifier` and `ValueNotifier` hold state, the builder widgets subscribe, and `setState` covers what one widget owns.

Decided in issue #136. The app has one snapshot, a handful of derived views computed by [[domain]] selectors, and a dependency surface the team keeps at zero. Flutter's architecture guidance (2024/2025) builds its view models on `ChangeNotifier` and reaches for `provider` only to inject them; this app does the injection by hand. `provider`, `riverpod`, `bloc`, `get_it`, `signals` and the like are not added even where they are Flutter Favorites, and a skill step that says to register a dependency in `provider` or `get_it` is overridden here.

### Choosing the primitive

Three kinds of state, each with its own home; the rule is to pick the smallest one that serves every widget that needs the value.

- **Widget-local state** (a text field's draft, whether a row is expanded, an animation): `StatefulWidget` and `setState`. It never leaves the widget.
- **Shared transient state** (which credit sheet is open, the household filter, the width class): a `ValueNotifier` owned by the nearest common ancestor and read through `ValueListenableBuilder`, or `UiState` when the shell and the screens both need it ([[mobile-architecture#State management#UI state]]). This is what `UiProvider` holds in the PWA ([[architecture#UI state]]).
- **Application state** (the snapshot, today, the derived views): the store ([[mobile-architecture#The store]]), a `ChangeNotifier` that is the app's view model in the MVVM sense, read through `ListenableBuilder`.
- **Promote only on demand**: state moves up one level when a second widget needs it, never pre-emptively. The width class is computed once in the shell and handed down as a value ([[mobile-architecture#Responsive layout]]).

### Notifier rules

The store and every later notifier follow Flutter's guidance for view models: the logic lives in the notifier, none in the widget, and data flows one way.

- **Unidirectional**: state flows down through getters, events flow up as method calls (`replaceAll` today, `claim` later). A widget never mutates what it reads.
- **Immutable exposure**: fields are private and getters return values or unmodifiable views, so nothing can change the store without a notification. The domain models are immutable already.
- **One notification per change**: mutate every field, then `notifyListeners()` once. Never notify during `build`, and never after `dispose`.
- **Async actions**: an action the UI must track (in flight, failed, done) is wrapped in the guide's Command pattern, a small `ChangeNotifier` with `running`, `error` and an `execute` that ignores re-entry. `load` gets by with a `loading` flag because it is the only async action; the api client brings the first Command.
- **No rules in the store**: derived views are [[domain]] selectors called on every read, as today. The notifier decides when to notify, not what is true.

### UI state

`UiState` is the PWA's `UiProvider` as a `ChangeNotifier`: the open credit's benefit id, the open compare group's label and the nudge preview's reminder, each with an open and a close, notifying once per change.

It notifies not at all when nothing changes, and it also owns the `SnackbarState` ([[mobile-architecture#Undo and the snackbar]]).

It lives above the router in `UiScope`, an `InheritedNotifier` beside `AppScope`, because the shell renders the sheets while the screens open them, and the two sit on opposite sides of the router's layout boundary. The sheet tracks a benefit *id*, never a resolved instance: the instance is recomputed on every claim, and holding one would leave the sheet showing a balance that went stale the moment the user logged something. `RewardApp` creates and disposes it unless a test injects one. Pinned by [[mobile-tests#UI state]].

### Wiring and lifecycle

Notifiers reach widgets by constructor until the tree is deep enough to hurt, then through an `InheritedNotifier`; whoever creates a notifier disposes it.

- **Constructor injection first**: `RewardApp(store:)` today. Tests and previews build the store on `MemorySnapshotStore` with a fixed clock, which is the guide's "make fakes" recommendation in practice.
- **A scope above the router**: `AppScope` is an `InheritedNotifier<AppStore>` wrapped around `MaterialApp.router`, and `AppScope.of(context)` in a route builder is how a screen gets the store; `TodayScreen` still takes it as a constructor argument so tests and previews build it bare. `UiScope` does the same for `UiState`. `of` is the only place a widget looks either up; there is no global.
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
- **The credit sheet is not a route**: as in the PWA, the shell shows one sheet whichever tab opened it, driven by `UiState`, so the URL stays on the tab beneath ([[mobile-architecture#The credit sheet]]). Back closes it through the host's `PopScope` before the router sees the pop.
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

The screen re-flows with the width class it reads from the shell ([[mobile-architecture#Responsive layout]]). From medium the overlap cards go two across in `IntrinsicHeight` rows of two `Expanded` cards. From expanded the body under the headline is a `Row` of two columns, use-soon, overlaps and captured on the left and locked on the right, with the headline spanning both. Flutter orders a screen reader's traversal by position, not by the widget tree, so each of Today's sections is a `_Section`: a semantics container with an `OrdinalSortKey` giving its place in the phone order. The two-column layout therefore reads exactly as the phone does, which [[mobile-tests#Today#The screen reader hears the phone order at every width]] proves by comparing the traversal at 402 and 1280.

## The credit sheet

`CreditSheet` is the PWA's credit sheet ([[design#Partial logging]]): the one place every credit action lives, opened by benefit id from any tab and drawn by the shell inside a `SheetHost` in the shape the width calls for.

Its job is to make logging a partial amount as easy as logging the whole thing. It reads the instance from the store on every build through `AppStore.instanceFor`, so a claim made anywhere updates the balance without reopening. From top to bottom: the card label, name and window; the balance over a progress bar labelled "Claimed so far" and the deadline; for a locked credit, the enrolment note and "I've enrolled — unlock this credit" (`confirmEnrollment`); for an open one, "Log what you spent" with the quick amounts, "Other…" revealing an amount field whose entry is parsed with `parseMoneyToCents` and capped at what is left, and "Mark the full … used", each of which claims through the store and closes the sheet; "Logged this period" from `AppStore.claimsFor`, newest first, each with a Remove whose label names the amount and the day (`removeClaim`); for a captured credit "Fully captured" with Undo (`unclaim`); the missed note; the redemption steps; the notes; the reminder ladder with the reached rung emphasised; and the "Last call only" and "Silence this credit" switches (`updateBenefit`, `toggleBenefitMute`). Quick amounts are `quickAmounts`: a quarter and a half of the remainder rounded to whole dollars, each at least a dollar and under the remainder, and none under five dollars. The issuer's benefits page is not linked yet, since opening a URL needs a package; the edit link arrives with the benefit editor. Every write goes through `CreditActions` ([[mobile-architecture#Undo and the snackbar]]), so logging, unlocking, silencing, removing and clearing each report through the snackbar the way a swipe will.

`SheetHost` is the PWA's `Sheet` ([[interaction#Bottom sheets]]) as one stateful widget the shell wraps around the scaffold, choosing by the width class it is handed:

- **Compact**: Material's `BottomSheet` widget with its drag handle over a scrim, driven by the host's own animation controller so a drag past the handle's threshold calls `onClosing`, capped at 92% of the height.
- **Medium**: a centred `Dialog` at most 480 wide and 85% of the height over the scrim.
- **Expanded**: a 380-wide, full-height panel on the trailing edge in a `Row` beside the shell, with no scrim, so the list narrows rather than being covered and stays tappable; switching tabs leaves the sheet open.

All three wrap the presentation in `Semantics(scopesRoute, namesRoute)` labelled with the credit's name, so a screen reader hears it as a dialog; a `FocusScope` keeps keyboard traversal inside, the host remembers the focused node on open, moves focus into the scope once the sheet is built (autofocus alone is honoured only when nothing behind has focus) and hands it back after close; `CallbackShortcuts` above the scope closes on Escape; and a `PopScope` with `canPop` false while open closes on the system back, leaving predictive back intact. The scrim is a dismissible `ModalBarrier` labelled "Close …". Pinned by [[mobile-tests#Credit sheet]]; every state and width has a Widget Preview.

## Undo and the snackbar

Undo over confirmation ([[design#Undo over confirmation]]): `CreditActions` writes the store at once and hands `SnackbarState` a message whose Undo takes exactly that change back, and `SnackbarHost` draws it in the content column.

`CreditActions` is the PWA's `useCreditActions`, a value built on the store and the snackbar wherever a row or the sheet needs it, so a swipe and a sheet button do the same thing. `log` (and `logAll`) claims and offers "Undo logging …" that removes that one claim; `toggleMute` says "Silenced … It is still tracked." or "Reminders back on for …" with an Undo that toggles back; `confirmEnrollment` says "… unlocked." with an Undo that revokes. `removeClaim` and `unclaimAll` report what happened with no Undo, because the sheet's "Logged this period" is the way back that needs no timer.

`SnackbarState` is a `ChangeNotifier` holding the one current message, owned by `UiState`. An undo stays up twenty seconds, not Material's six, because WCAG 2.2.1 wants a time limit the user cannot adjust to be generous; a plain message stays 3.5. `pause` stops the clock and `resume` restarts it in full: the host calls them when the pointer enters and leaves the bar and when focus lands on and leaves the Undo. A newer message replaces the older and restarts the clock. Material's `ScaffoldMessenger` was not used because its `SnackBar` owns a clock that cannot be paused on hover or focus.

`SnackbarHost` is a `Stack` over its child, the bar aligned to the bottom, with the Undo a `TextButton` whose text carries the action's semantics label so a screen reader hears "Undo logging Uber Cash" while the eye sees "Undo", and the text a live region. The shell puts the host inside the content column: from medium the bar therefore centres on the column the rail pushes off centre, not on the window, and on a phone it sits above the navigation bar so it never covers the destination tapped next. The host resumes a pending message's clock when it mounts and pauses it when it unmounts, so a message never keeps a timer alive with nothing to draw it. Pinned by [[mobile-tests#Credit actions]] and [[mobile-tests#Snackbar]]; the bar has previews at compact and expanded and plain.

## Responsive layout

The app realises the product's three width classes ([[design#Responsive layout]]) with Flutter's own tools: `AppShell` computes the class and draws the navigation and the column, and each screen reads it to re-flow.

`WidthClass` (compact, medium, expanded) carries the column width (402, 560, 720) and the screen padding (20, 24, 28) as enum fields, so no widget re-derives either. `AppShell` computes it once from `MediaQuery.sizeOf(context).width` against the 600 and 1024 thresholds and hands it down through `WidthClassScope`; `WidthClass.of(context)` falls back to compact outside the shell, so a screen in a test or a preview is the phone design. The content column is a top-centred `ConstrainedBox` (key `content-column`) capped at the class's width, the screens' own `ListView` is the only scrollable, and each screen pads itself with the class's padding. The four destinations are a `NavigationBar` in compact and a `NavigationRail` from medium, pinned to 80 wide with icons over labels, and 200 wide and extended from expanded; the rail's width is pinned by a `SizedBox` because its own minimum width lets a wide label push it out. Both draw the one `destinations` list, so the order and focus traversal cannot differ. Today pairs the overlap cards from medium and becomes a two-column body from expanded with the headline spanning both ([[mobile-architecture#Today screen]]). Pinned by [[mobile-tests#Shell]].

A macOS build is the way to see the medium and expanded classes without a tablet, which is why macOS is a local run target and not a release target ([[mobile-architecture#Make targets]]).

## Accessibility

The app carries the product's WCAG 2.2 AA intent ([[design#Accessibility]]) in Flutter terms: the theme's tokens, Material's 48dp targets, and the text scaling and contrast proofs are all in place.

- **Text follows the platform size**: nothing overrides `MediaQuery.textScaler`, no text is clipped, and controls do not overlap at 200%; Today's number shrinks to fit its column instead of overflowing. Two layouts had to give for this: the header is a `Wrap` so the date drops under the title, and a credit row's name wraps instead of ellipsising, because a truncated name loses the one thing the row is for. Pinned by [[mobile-tests#Text scaling]] at a 2.0 scale factor on a 402-wide viewport, in the test font whose glyphs are squares, so it is stricter than any real typeface.
- **Contrast comes from the tokens**: secondary text clears 4.5:1 and control borders 3:1 on every ground in both modes, each tone's text on its own ground, and every text the overlap card draws on the section ground, checked over the theme extension the way `contrast.test.ts` checks `tokens.css`, so a copied token cannot drift ([[mobile-tests#Token contrast]]). The overlap card's body is neutral-300 rather than the secondary text colour, as in the PWA, because the light theme's secondary text reaches only 3.85:1 on the section ground.
- **Every gesture has a route**: every action on the credit sheet is a labelled button or switch ([[mobile-tests#Credit sheet#Every control on the sheet has a label]]), and when swipe actions arrive each has a button or a `Semantics` action a screen reader and a switch can reach, as the PWA's table in [[design#Accessibility]] lists.
- **Orientation is never locked** and the compact class covers a landscape phone.

## Make targets

`apps/mobile/Makefile` is the app's script runner, the counterpart of the PWA's `package.json` scripts, and every recipe goes through `fvm flutter` or `fvm dart` so the SDK is the one in `.fvmrc`.

`make init` installs FVM if needed, fetches the pinned SDK, resolves the workspace and runs `flutter doctor`. `make build ios|android|macos` produces a release build and a bare `make build` does the two store platforms, `make test` runs the widget suite and `make test ios` adds the e2e run, `make e2e [android]` runs `integration_test/` on a simulator or emulator it boots if needed, `make run` lists devices and asks for one because Flutter would otherwise silently pick the only booted simulator, `make run ios|android` boots a visible simulator or emulator, `make run macos` opens the app in a resizable window, and `make deploy VERSION=x.y.z` tags `develop` so the release workflow ships both stores ([[deployment#Pipeline]]). `scripts/pick-device.sh` does the device choosing for `e2e` and `run`. The README beside it lists every target; pinned by [[infra-tests#Infrastructure config#Mobile Makefile is the app's script runner]].

macOS is a local target only, added by issue #117 so the medium and expanded classes ([[mobile-architecture#Responsive layout]]) can be tried on a laptop: `apps/mobile/macos/` is the `flutter create` output on Swift Package Manager with no Podfile, both entitlements files grant `network.client` for the api client, and neither `deploy` nor the release workflow builds it; pinned by [[infra-tests#Infrastructure config#macOS is a local run target only]].
