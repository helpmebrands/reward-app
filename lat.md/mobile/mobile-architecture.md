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

The dark tokens are Nocturne verbatim; the light tokens are the PWA's derived light theme, copied from the PWA's `tokens.css` so the app kept its colours. Where Nocturne and Material disagree on looks, Nocturne wins: `ColorScheme.primary` is the accent, primary actions are outlined, the surfaces are the three Nocturne grounds, and there is no alarm red. Material supplies compact density and 48dp minimum targets. The theme mode is `Settings.theme` read from the store by `RewardApp` on every notification, so Dark or Light overrides the platform the moment it is saved and System follows the platform brightness as before; pinned by [[mobile-tests#Theme]] and [[mobile-tests#Settings]].

## The snapshot store

The whole dataset is one record, as in the PWA: `SnapshotStore` loads and saves one `AppData`, and `SharedPreferencesSnapshotStore` keeps it as a JSON string under the PWA's `app-data` key through the `shared_preferences` package, a Flutter Favorite.

`load` never throws: a corrupt or missing record starts the app empty, because empty is recoverable and a crash is not. The JSON shape is the domain's `json.dart` codec ([[tests#Snapshot JSON]]), so a PWA export loads directly. `MemorySnapshotStore` serves tests and previews. Pinned by [[mobile-tests#Store]].

## Api config

The app finds the service tier through one constant, `ApiConfig.baseUrl` in `lib/data/api_config.dart`: `String.fromEnvironment('API_BASE_URL')` at build time, the staging api by default.

The default is `ApiConfig.stagingUrl`, `https://reward-api-bduraqeztq-uc.a.run.app`, so a local run needs nothing.

The release pipeline builds each environment with its own `--dart-define=API_BASE_URL=…` (epic #129); `make run`, `make test` and the verify gate need no define. Pinned by [[mobile-tests#Api config]].

## The store

`AppStore` is a `ChangeNotifier` holding the snapshot and today's date, and the derived views the screens read. All of it is computed by [[domain]] selectors on every read; the store owns no rules.

The views are instances by urgency, the missed ledger, the four totals, the use-soon, locked and captured lists, overlaps and the next reset.

Today is read from a clock on every access rather than captured at boot, because an app resumed the next morning must show that morning's deadlines, as the PWA learnt. The clock is a `DateTime` source, so today and the `createdAt`, `updatedAt`, `enrolledAt` and `claimedAt` instants a mutation stamps come from the same place; tests and previews inject a fixed one. The screens never touch storage.

### Mutations

The store carries the PWA's mutations; every one replaces the snapshot, notifies once and saves through the snapshot store.

Cards: `addCardFromTemplate`, `updateCard`, `toggleCardMute`, `archiveCard`, `deleteCard`. Member: `updatePreferences`, and `toggleCardMute` and `toggleBenefitMute`, which write the member's `MemberPreferences` rather than the household's snapshot; the snapshot store saves them under their own key (`member-preferences`) until the api holds them ([[domain#Member preferences]]). Benefits: `addBenefit`, `updateBenefit`, `toggleBenefitMute`, `confirmEnrollment`, `revokeEnrollment`, `deleteBenefit`. Claims: `claim`, `unclaim`, `removeClaim`. Settings: `updateSettings`, `updatePreferences`. And `replaceAll`.

Every one builds the next snapshot with the domain types' `copyWith`, replaces the store's snapshot, notifies once and then saves it through the [[mobile-architecture#The snapshot store|snapshot store]]; the returned future completes when the save does, but the change is visible and announced before the first await, so a screen that ignores the future still redraws at once. Patches are functions of the current record (`updateCard(id, (card) => card.copyWith(...))`) rather than partial objects, and the store stamps `updatedAt` after applying them. `claim` without an amount records the instance's remaining cents, not the face value, so a second claim against a partly used credit cannot overshoot; `deleteCard` cascades to the card's benefits and their claims, `deleteBenefit` to its claims. `addCardFromTemplate` takes an optional label, last four, anniversary (today by default) and, for the blank template, the typed issuer and product. Ids are version 4 UUIDs from `lib/logic/ids.dart` with no package, the shape the PWA's `crypto.randomUUID()` gives, so ids from either app look alike.

A write that lands before `load` resolves is kept when the snapshot arrives, the PWA's "user's action wins" rule: nothing in the UI can write while `loading` is true, but a caller that does not wait must not have its change silently discarded. A mutation with no snapshot yet starts from `emptyAppData()`, the PWA's defaults in `lib/data/snapshot_store.dart`. Pinned by [[mobile-tests#Store]].

### The service tier

With a `HouseholdApi` the store is backed by the service tier instead of the device; without one (tests, previews, a build with no Firebase app) it keeps the local snapshot above. Pinned by [[mobile-tests#Api store]].

`ApiClient` (`lib/data/household_api.dart`) calls the api on `dart:io`'s `HttpClient` with no package, at `ApiConfig.baseUrl`, sending the signed-in user's Firebase ID token. An unreachable host, a timeout or a broken connection is `ApiOffline`; an answer that says no is `ApiError` with the body's `error`. Transport is a function, so the client is testable without a socket.

- **Reading**: `load` shows the last answer from `HouseholdCache` (`household-cache` in `shared_preferences`) at once, then `refresh` fetches `GET /v1/household/data`, the role and the preferences. The cache carries `householdCacheVersion`; a cache of another version is discarded and fetched again, with no migration chain on the device, because the server holds the truth.
- **Editing**: every mutation other than a claim sends one request and fetches the household again. A card patch sends only the fields that changed; a credit patch splits household state (`PUT …/state`) from terms (`PUT /v1/benefits/{id}`). Offline it is refused with `offlineMessage`, a reader gets `readOnlyMessage`, and an api refusal such as `system maintained` gets its own sentence; the store holds the sentence as `problem` and `RewardApp` shows it in the snackbar.
- **Claims**: `claim` puts the claim in the `ClaimOutbox` (`claim-outbox`, kept apart from the cache so discarding the cache never loses one) with an idempotency key made once, shows it at once as pending, and flushes. `flush` sends the queue in order, each under its own key, and concurrent calls share one flush, so a claim is stored once however often it is retried. Taking back a queued claim removes it from the outbox; a sent one is deleted on the api.
- **When to flush**: after every successful fetch, when the app resumes (`AppLifecycleListener`), and every 30 seconds while offline or with claims queued. No connectivity package: a request that succeeds is the network coming back.
- **Readers**: `canWrite` is false for a reader, so rows have no swipe-to-log, the credit sheet no logging, unlock, undo or edit, the compare sheet no log buttons and Cards no add, archive, delete or edit; mutes stay, since they are the member's own. `canEdit` is also false offline.
- **Commands**: `refresh` runs through `Command0` (`lib/logic/command.dart`), the Command pattern from Flutter's architecture guide with no package: it exposes whether it is running and how it last ended, and a second call joins the first.
- **Signing out** calls `forget`, which drops the household, the cache and the queued claims, so the next person on the device never sees or sends them; signing in refreshes. Theme and horizon stay this device's settings.

## State management

The app manages state with Flutter's own primitives and adds no state management or injection package: `ChangeNotifier` and `ValueNotifier` hold state, the builder widgets subscribe, and `setState` covers what one widget owns.

Decided in issue #136. The app has one snapshot, a handful of derived views computed by [[domain]] selectors, and a dependency surface the team keeps at zero. Flutter's architecture guidance (2024/2025) builds its view models on `ChangeNotifier` and reaches for `provider` only to inject them; this app does the injection by hand. `provider`, `riverpod`, `bloc`, `get_it`, `signals` and the like are not added even where they are Flutter Favorites, and a skill step that says to register a dependency in `provider` or `get_it` is overridden here.

### Choosing the primitive

Three kinds of state, each with its own home; the rule is to pick the smallest one that serves every widget that needs the value.

- **Widget-local state** (a text field's draft, whether a row is expanded, an animation): `StatefulWidget` and `setState`. It never leaves the widget.
- **Shared transient state** (which credit sheet is open, the width class): a `ValueNotifier` owned by the nearest common ancestor and read through `ValueListenableBuilder`, or `UiState` when the shell and the screens both need it ([[mobile-architecture#State management#UI state]]). This is what `UiProvider` held in the PWA.
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

The Flutter team's architecture guidance recommends `go_router`, and the package README declares it feature-complete: bug fixes and stability, no new features planned. For code an agent writes that is an asset, not a risk. Version 18 requires Flutter 3.44; the pinned toolchain is 3.47. Screens are addressable because a tapped reminder must open the screen it names, as the PWA's shell did on its service worker's `navigate` message.

### Routes and the shell

The route table mirrors the PWA's nine routes, with the four tabs as branches of one shell route and the editors and Settings pushed above it.

- **Paths**: `/` Today, `/credits`, `/cards` and `/value` are the shell branches, the constants in `lib/shell/router.dart`. `/cards/new` (`Paths.newCard`), `/cards/:id` (`cardPath`), `/benefit/:id` (`benefitPath`) and `/settings` (`Paths.settings`) are the full-screen routes; `errorBuilder` renders `NotFoundScreen`, "That screen does not exist." with "Back to Today". `StubScreen` remains only as a preview fixture. `appRouter` takes an `initialLocation` so a test opens a screen directly.
- **Full-screen routes are pushed above the shell**: each is a child route of the branch it belongs under (`new` and `:id` under `/cards`, `benefit/:id` and `settings` under `/`) with `parentNavigatorKey` set to the root navigator, so `go` to one of them keeps the shell beneath it and the system back returns to the branch. Declared literal before parameter so `new` wins. Each sits outside `AppShell`, so it computes its width class from the window and hands it down in a `WidthClassScope`, centres its own column, and hosts the snackbar itself.
- **Headings and titles**: every screen has one `ScreenTitle`, the PWA's `h1` and `useScreenTitle` in one: a `Semantics` boundary with `headingLevel` 1 and the screen's name as its label (Today's draws the logotype but reads "Today"), wrapped in a `Title` that sets the window title to "Screen · HelpMe Reward"; the editors use the card or credit name, the not-found screen "Not found". Section titles are `headingLevel` 2, so a screen reader can jump by level. Pinned by [[mobile-tests#Routing#Every route has exactly one heading and its title]].
- **Focus on navigation**: moving between screens never reloads anything, so focus would stay wherever it was and a screen reader would say nothing. `ScreenTitle` registers its focus node on `UiState.headings` under the location it was built for, and `RewardApp` listens to the router: on every change but the first it marks that location as `pendingHeadingFocus`, which the new screen's title consumes when it is built, with a post-frame fallback for a branch that was already built; the heading node carries the `focusable` and `focused` flags so assistive technology follows. A press on the bar or the rail sets `keepFocusOnDestination` first, so focus stays where the user pressed, the PWA's one exception. Pinned by [[mobile-tests#Routing#Navigation moves focus to the heading, a tab press keeps it]].
- **Notification taps go by path**: `handleNotificationTap` takes the router and a payload, a map with a `url` or the url itself, and calls `go` when it is an app path, ignoring anything else, the counterpart of the PWA's `navigate` message; the delivery epic only has to call it. Pinned by [[mobile-tests#Routing#A notification payload opens its screen]].
- **The shell** is `StatefulShellRoute.indexedStack` whose builder renders `AppShell`: the `NavigationBar` or `NavigationRail` for the width class ([[mobile-architecture#Responsive layout]]) around the content column, keeping each tab's scroll position across switches. The four `Destination`s are one list the bar and the rail both draw, so the order cannot differ.
- **The credit sheet is not a route**: as in the PWA, the shell shows one sheet whichever tab opened it, driven by `UiState`, so the URL stays on the tab beneath ([[mobile-architecture#The credit sheet]]). Back closes it through the host's `PopScope` before the router sees the pop.
- **Typed by hand, not by codegen**: paths are constants and each parameterised route has a helper such as `cardPath(id)`. `go_router_builder` is not added because it brings `build_runner` into a workspace with no code generation, and nine routes do not need it. Revisit if the table grows.
- **Redirects read the store and the session**: `refreshListenable` merges the `AppStore` and the `Session`, so the sign-in redirect re-evaluates whenever either notifies, with no other state holder ([[mobile-architecture#Sign-in]]).
- **Not added**: `app_links` (third-party, needs approval, and there are no associated domains or URL schemes to serve), `auto_route`, and hand-written `RouterDelegate` code.

### Transitions and back

Page transitions stay at the framework defaults, which on the pinned Flutter (3.47) means predictive back on Android with `FadeForwardsPageTransitionsBuilder` for a plain push, and the Cupertino slide on iOS.

- **No `pageTransitionsTheme` in the theme**: pinning a builder opts out of predictive back. The first-party `animations` package is not added until [[design#Screens]] asks for a motion pattern the defaults lack; none does today.
- **The manifest enables predictive back**: `android:enableOnBackInvokedCallback="true"` on the `<application>` element, without which the gesture does not animate.
- **Custom back handling uses `PopScope`**: a sheet or editor that must intercept back (an unsaved draft) does so through `PopScope` and `onPopInvokedWithResult`, never `WillPopScope`, so the predictive gesture keeps working.
- **Per-route transitions** go through `CustomTransitionPage` in a route's `pageBuilder`, and only where a screen calls for one.
- **Tests**: the route table is built by a function that takes the store, so a widget test pumps `MaterialApp.router` on a `MemorySnapshotStore` and asserts the screen a path renders; the shell tests in [[mobile-tests]] run at the three widths.

## Sign-in

The app sits behind sign-in with Google or Apple through Firebase Authentication on the environment's Identity Platform project; there is no guest mode, because the household lives in the service tier. Pinned by [[mobile-tests#Sign-in]].

`Session` (`lib/logic/session.dart`, a `ChangeNotifier`) holds two independent pieces of launch state: `introSeen`, a device flag in `shared_preferences` (`SharedPreferencesIntroStore`) set when the slideshow is skipped or finished and kept across sign-out, and the signed-in user from the `AuthService`. `main` loads the flag before the first frame.

`signInRedirect` in `lib/shell/router.dart` is the router's one redirect:

| State | Destination |
| --- | --- |
| Signed in | the app: the `from` a sign-in was sent from, or Today |
| Signed out, intro seen | `/sign-in` |
| Signed out, intro unseen | `/welcome`, then `/sign-in` |

The slideshow stays open while signed out, which is how "Learn more" on the sign-in screen replays it. A signed-out deep link carries `?from=`, so an invite link opened before signing in (#221) still lands where it pointed. Without a session, as in the screen tests, there is no redirect.

- **`WelcomeScreen`**: three slides in a `PageView`, Skip at the top, dots, and Next that becomes "Get started"; both finish the intro and go to sign-in.
- **`SignInScreen`**: "Continue with Google", "Continue with Apple" and "Learn more"; a failed sign-in shows its sentence in a live region and stays.
- **Settings** gains an *Account* section with the email and "Sign out", after which the redirect returns to sign-in, never the slideshow.
- **`FirebaseAuthService`** (`lib/data/firebase_auth_service.dart`) signs in with `signInWithProvider` for both providers, so no provider SDK is added: `google_sign_in` would need approval under rule 9. A cancelled sheet is not an error.
- **`FirebaseConfig`** (`lib/firebase_options.dart`) builds the per-platform `FirebaseOptions` by hand from `--dart-define`s whose staging defaults are the Pulumi stack's outputs (`firebaseIosAppId`, `firebaseIosApiKey`, …), with no `flutterfire` CLI or generated file. A platform without an app id runs signed out with `UnconfiguredAuth`, whose every sign-in says it is not set up, so `make run macos` and the tests work without Firebase.
- **iOS**: `Runner.entitlements` declares Sign in with Apple, which the App Store provisioning profile must carry (runbook 08, step 1.7). Google's web flow returns through the URL scheme `firebaseIosUrlScheme`, registered in `Info.plist` beside the staging option defaults, so a plain iOS or Android build signs in against staging.
- `firebase_core` and `firebase_auth` are Flutter Favorites, resolved through Swift Package Manager on iOS and macOS; the analyzer excludes `build/`, where a macOS build checks their Swift packages out.

Every screen has a Widget Preview: the slideshow in both themes and sign-in at compact and expanded.

## System and user cards

A card added from the catalogue is linked to its template and kept up to date by it; a card added blank, or converted, is the household's own ([[domain#Catalogue versions]], [[api-architecture#Conversion]]). Pinned by [[mobile-tests#System and user cards]].

- **Cards** names two groups, "Kept up to date" (`cards-system`) and "Maintained by you" (`cards-user`), each shown when it has cards; a local household with no linked card shows its cards without names, as before sign-in existed.
- **Add a card** lists the api's catalogue (`GET /v1/catalog`, `AppStore.templates`) in the service-tier mode, the built-in one until it is fetched, with `blank` last; `CatalogFilterController` reads its templates through a function so a fetch that lands later shows. A template adds a linked card, `blank` a household one, and a second card of a product gets the numbered label ([[domain#Card]]).
- **A system card's terms are read-only**: in the card editor the fee is read-only, the network cannot change and "Add" is gone; in the benefit editor every term (name, value, cadence, anchor, category, merchant, ends on, spend threshold, enrolment needed, steps) is read-only, while the label, renewal date, kind, enrolment, spend met, tracking, last call and silences stay the household's.
- **"Change the terms"** on either editor opens `ConvertScreen` at `/cards/:id/convert`, which says the card will be replaced by one the household maintains, will no longer update automatically, and keeps its claims, history, enrolment and everyone's silences. Nothing changes until "Make it mine", which calls `AppStore.convertCard` (`POST /v1/cards/{id}/convert`) and opens the new card's editor, now fully editable.
- `SwitchRow` takes a null `onChanged` for a switch the catalogue owns.

Widget Previews: Cards with both groups, and the conversion screen.

## Household sharing

Members invite and join each other without typing ids: by a link shared through the system share sheet, or by an eight-character code. Pinned by [[mobile-tests#Household sharing]].

- **Settings, Household** (service-tier mode only): every member with their role, "Invite someone" for the owner, a remove button per member for the owner with a confirmation, and "Have an invite code?". Inviting asks read or edit in a bottom sheet, calls `POST /v1/household/invites`, hands the link and the code to the share sheet (`share_plus`, a Flutter Favorite, behind `shareText` so tests see what was shared) and shows the code on the screen.
- **Joining**: `/invite/:code` is a full-screen route to `JoinScreen`, reached from an invite link or from a code typed under "Have an invite code?" on sign-in or in Settings. A signed-out person who opens a link is sent to sign-in with `from`, and lands back on the join screen ([[mobile-architecture#Sign-in]]).
- `AppStore.joinHousehold` first flushes the claims queued for the old household, then accepts. Leaving a household that holds cards asks "Leave your cards behind?" and repeats with `confirmLeave`; used, expired and unknown codes, an owner with members and an existing member each say why and stay. On success the cache is cleared, the household fetched, and the app goes to Today.
- **Links on the device**: `Runner.entitlements` declares `applinks:api.staging.helpmereward.com`, and the Android manifest an `autoVerify` intent filter for `https://api.staging.helpmereward.com/invite/`; go_router's built-in deep linking routes them, with no `app_links` package ([[api-architecture#Invite links]]).

Every new screen has a Widget Preview: the join screen in both themes.

## Today screen

`TodayScreen` is the PWA's Today ([[design#Screens]]) as Material widgets: the number, the countdown, the rows behind them, and every interaction the PWA has.

It shows the header with the date and the "Preview nudge" button, the headline counting only what is claimable, the use-soon rows with the reset countdown, up to three overlap cards on the section ground, the locked section with its own total, and the captured rows.

`CreditRow` draws every status in one of five tones from the token set (soon, available, locked, captured, missed), with the card's display name in the subtitle when the household has more than one card, the claimed amount on a captured row, and "Eligible now" in place of a deadline on an open rolling credit. Given callbacks it is the interactive row of [[mobile-architecture#The swipe row]]. The headline number shrinks to fit the column rather than overflow. Every component has a Widget Preview in `lib/previews.dart`. Pinned by [[mobile-tests#Today]].

### Today's interactions

The screen takes the `UiState` beside the store; without it the screen is static, which is how tests and previews still build it bare.

With it, every row gets `onOpen` (the credit sheet by benefit id), `onLogAll` and `onToggleMute` through the shared `CreditActions` ([[mobile-architecture#Undo and the snackbar]]), so a tap, a swipe and a sheet button all do the same thing and the headline follows a claim at once.

- **Compare sheet**: tapping an overlap card opens `CompareSheet` for the group, through `UiState.openOverlap` and `AppStore.overlapFor`. It is the PWA's: the two sides side by side, each a button that opens that credit (closing the compare first), the "What to do" advice that is concrete about one booking drawing on one card and stops short of ranking the two people, and a "Log … on …'s card" button per unlocked side that claims through `CreditActions` and closes. The shell hosts it above the credit sheet in a `SheetHost` with `wide: dialog`, so it stays a centred dialog at expanded where the credit sheet docks.
- **Nudge preview**: "Preview nudge" shows the next reminder from `buildSchedule` over the current snapshot at the store's clock, or `sampleReminder` built from the claimable total when nothing is scheduled ([[reminders#Nudge preview]]), through `UiState.showNudge`. `NudgePreview` is drawn by the shell at the top of the content column: the app name, "preview", the title and the body, a Dismiss with its own label, a six-second clock of its own, and a tap that dismisses and goes to the reminder's route. It is in-app and needs no permission; delivery on the device is a later epic.

Pinned by [[mobile-tests#Today interactions]].

The screen re-flows with the width class it reads from the shell ([[mobile-architecture#Responsive layout]]). From medium the overlap cards go two across in `IntrinsicHeight` rows of two `Expanded` cards. From expanded the body under the headline is a `Row` of two columns, use-soon, overlaps and captured on the left and locked on the right, with the headline spanning both. Flutter orders a screen reader's traversal by position, not by the widget tree, so each of Today's sections is a `_Section`: a semantics container with an `OrdinalSortKey` giving its place in the phone order. The two-column layout therefore reads exactly as the phone does, which [[mobile-tests#Today#The screen reader hears the phone order at every width]] proves by comparing the traversal at 402 and 1280.

## The credit sheet

`CreditSheet` is the PWA's credit sheet ([[design#Partial logging]]): the one place every credit action lives, opened by benefit id from any tab and drawn by the shell inside a `SheetHost` in the shape the width calls for.

Its job is to make logging a partial amount as easy as logging the whole thing. It reads the instance from the store on every build through `AppStore.instanceFor`, so a claim made anywhere updates the balance without reopening. From top to bottom: the card label, name and window; the balance over a progress bar labelled "Claimed so far" and the deadline (a rolling credit reads "Eligible now" or "Eligible again" with the day after its window); for a locked credit, the enrolment note and "I've enrolled — unlock this credit" (`confirmEnrollment`), or for a spend-gated one "Unlocks after $5,000 spend this year." and "I've reached it — unlock" (`confirmSpend`), chosen by `lockReason`; for an open one, "Log what you spent" with the quick amounts, "Other…" revealing an amount field whose entry is parsed with `parseMoneyToCents` and capped at what is left, and "Mark the full … used", each of which claims through the store and closes the sheet; "Logged this period" from `AppStore.claimsFor`, newest first, each with a Remove whose label names the amount and the day (`removeClaim`); for a captured credit "Fully captured" with Undo (`unclaim`); the missed note; the redemption steps; the notes; the reminder ladder with the reached rung emphasised; and the "Last call only" and "Silence this credit" switches (`updateBenefit`, `toggleBenefitMute`). Quick amounts are `quickAmounts`: a quarter and a half of the remainder rounded to whole dollars, each at least a dollar and under the remainder, and none under five dollars. The issuer's benefits page is not linked yet, since opening a URL needs a package; "Edit this credit" closes the sheet and opens the benefit editor. Every write goes through `CreditActions` ([[mobile-architecture#Undo and the snackbar]]), so logging, unlocking, silencing, removing and clearing each report through the snackbar the way a swipe will.

`SheetHost` is the PWA's `Sheet` ([[design#Screens]]) as one stateful widget the shell wraps around the scaffold, choosing by the width class it is handed:

- **Compact**: Material's `BottomSheet` widget with its drag handle over a scrim, driven by the host's own animation controller so a drag past the handle's threshold calls `onClosing`, capped at 92% of the height.
- **Medium**: a centred `Dialog` at most 480 wide and 85% of the height over the scrim.
- **Expanded**: a 380-wide, full-height panel on the trailing edge in a `Row` beside the shell, with no scrim, so the list narrows rather than being covered and stays tappable; switching tabs leaves the sheet open.

All three wrap the presentation in `Semantics(scopesRoute, namesRoute)` labelled with the credit's name, so a screen reader hears it as a dialog; a `FocusScope` keeps keyboard traversal inside, the host remembers the focused node on open, moves focus into the scope once the sheet is built (autofocus alone is honoured only when nothing behind has focus) and hands it back after close; `CallbackShortcuts` above the scope closes on Escape; and a `PopScope` with `canPop` false while open closes on the system back, leaving predictive back intact. The scrim is a dismissible `ModalBarrier` labelled "Close …". Pinned by [[mobile-tests#Credit sheet]]; every state and width has a Widget Preview.

## Credits screen

`CreditsScreen` is the PWA's ledger ([[design#Screens]]): everything that exists and where it stands, including what Today hides, with four totals that are never one.

The screen holds its filter and grouping as widget-local state, and computes the rest on every build from the store: the live instances, and the closed windows from `AppStore.missed` folded in as first-class rows with the missed status and the shortfall as the remainder (`missedRows`), so "Missed" is itemised per credit rather than sitting as one number on Value. `filterRows` keeps what each of the six filters means in the PWA: All, Use soon, Open (claimable), Locked, Captured (claimed this cycle, not missed) and Missed. `groupRows` buckets by card, cadence or status in first-seen order, as the PWA's `Map` does, labelling each with the card label, the cadence label or the status label, and `groupFigure` gives every header the one figure that matches the filter: missed sums the remainder, captured sums the claimed cents, locked the remainder, anything else the claimable remainder, so a header never mixes money still on the table with money already lost ([[domain#The four totals]]).

From top to bottom: "All credits" with the open, locked and missed counts; the four totals as tiles, two by two on a phone and four across from medium; the grouping as a `SegmentedButton` and the filters as `ChoiceChip`s in a `Wrap`, each group labelled for a screen reader ("Group credits by", "Filter by status") with Material's selected state; then each group with its dot, label and figure in a `Wrap` so the figure drops under the label at a large text size, its swipe rows on the shared `CreditActions` keyed by benefit and cycle so a missed row and the live one are distinct, and under the card grouping the PWA's footer line; or "Nothing matches that filter." when the filter empties the ledger. Pinned by [[mobile-tests#Credits]], against what the PWA drew for the sample household, dumped once and pinned; previews at compact in both modes and at expanded.

## Cards screen

`CardsScreen` is the PWA's Cards ([[design#Screens]], [[domain#Card value and the cardmember year]]): each card against its fee with a verdict that leads with an action, and a menu per card.

`AppStore.cardSummaries` gives one `summarizeCard` per active card over every instance, as the PWA's `cardSummaries` memo does. The header sums the fees and the captured value across them. Each card shows the issuer, the card label, the fee, the captured and the net figures, the break-even bar ("Share of the annual fee earned back", capped at 100% so cards with different fees stay comparable), the percentage with the days to renewal, the verdict, the tags (claimable, locked, missed, credit count, and "Business" on a business card) and "Edit card and credits", which goes to `cardPath`; "Add a card from the catalogue" goes to `Paths.newCard`. `cardVerdict` words the five cases exactly as the PWA does, No fee, Keep, Unlock first, Catch up and Decide, and refuses to price lounge access or status, because putting a number on those would be the one judgement the app should not fake.

The menu on each card offers Mute (or Unmute), Archive and Delete. Mute and Archive write the store and report through the snackbar with an Undo that names the card; Delete asks first in an `AlertDialog`, because deleting a card destroys its claim history, which no undo snackbar can honestly cover, and then cascades through `deleteCard` and says "Card deleted." The PWA had no archive or delete on this screen (its delete lives in the card editor); the menu is where the mobile app puts them.

One column on a phone; two across at medium in a `Wrap`; one wide row per card at expanded, a `Row` of the head, figures, bar and percentage beside the verdict, tags and edit button. Each block carries an `OrdinalSortKey`, so the wide layout reads in the phone order. Pinned by [[mobile-tests#Cards]] against the PWA's snapshot, dumped once and pinned; previews at compact in both modes, at medium and expanded, and empty.

## Value screen

`ValueScreen` is the PWA's Value ([[design#Screens]], [[domain#Card value and the cardmember year]]): what the household actually got against what leaked away, by month, by card and by credit.

The screen holds only how many months to show (6, 9 or 12, as choice chips) and computes the rest on every build: `monthlyTotals` over the store's missed ledger for the captured and missed totals and the bars, `biggestLeaks` for the leaks, and `cardSummaries` sorted by `feeProgress` for the ranks. Two totals sit side by side and are never one figure. When anything was missed, a panel on the section ground leads with "$X has expired unclaimed" and names the biggest single leak, because small recurring credits are exactly the shape of loss the reminder ladder exists for.

The chart is `MonthlyBarsPainter`, a `CustomPainter` with no chart package: for each month a missed bar and a captured bar side by side on one shared scale, so a tall month is tall on every card, painted in the accent and in `chartMissed`, the PWA's `--chart-missed` (neutral-600 in dark, neutral-700 in light) added to the tokens and checked at 3:1 on the page ground by [[mobile-tests#Token contrast]]. The painter's `heightFor` is the one scaling rule. The painted chart is decorative; the semantics node around it carries every month's captured and missed amounts as text, the counterpart of the PWA's visually hidden table, and "Tallest bar = $X", the month labels and the legend swatches are excluded so they are not read twice. The chart fills the padded column, so it grows with the width class.

Cards are ranked worst-first on a percentage-of-fee axis, each with its label, its percentage and a track whose fill is capped at the break-even line at 100%, so cards with different fees stay comparable; the section appears only with more than one card. The leaks list each recurring credit that expired unclaimed with its label, its span and its amount, worst first. With no cards the screen explains what will appear. Pinned by [[mobile-tests#Value]] against the PWA's snapshot, dumped once and pinned; previews in both modes and at expanded.

## Settings screen

`SettingsScreen` is the PWA's Settings ([[design#Screens]]) at `/settings` without the "Your data" section: reminder preferences, the ladder table and the appearance choice, one column at every width because the ladder table needs it.

The reminders section is the "Send me reminders" switch and, once on, "Send them at" (a time as HH:MM with a clock button that opens Material's time picker), "Ignore anything under" on the Field pattern with `moneyError`, and "Nudge me about locked credits"; every control writes this member's preferences through `updatePreferences` as soon as its value is valid and reads the stored value back on rebuild. These preferences drive the nudge preview and the server's schedule. With push ([[mobile-architecture#Push]]), turning the switch on asks for notification permission first and a refusal leaves it off with "Reminders stay off until notifications are allowed." in the snackbar; once on, the server's summary ("3 reminders scheduled. Next on Oct 31: $10 expires tonight.") and "Send a test notification" sit under the fields. Sign out unregisters the device before signing out. The ladder table lists the four scheduled cadences with `ladderSummary` ([[reminders#The ladder]]). Appearance is three choice chips, System, Dark and Light, writing `Settings.theme`, which the app reads into its theme mode ([[mobile-architecture#Theme]]). Today's header carries the gear that leads here, the only way into Settings and therefore into turning reminders on, so it lives on the screen people open every day. Pinned by [[mobile-tests#Settings]]; previews with reminders off, on, and in light.

## Push

The server decides and sends reminders and change notices ([[api-architecture#Reminder sender]]); the device asks permission, registers, and shows. Pinned by [[mobile-tests#Push]].

`PushMessaging` (`lib/data/push_messaging.dart`) is the seam: `FirebasePushMessaging` on `firebase_messaging`, which reaches APNs on iOS, and a fake in tests. It asks permission (provisional counts as granted), reads the FCM token (on iOS after waiting briefly for the APNs token), and exposes token refreshes, the tap that launched the app, taps from the background and pushes that arrive in the foreground. The IANA zone comes from the method channel `com.helpmebrands.reward/timezone`, which `AppDelegate.swift` answers with `TimeZone.current.identifier` and `MainActivity.kt` with `TimeZone.getDefault().id`, because Dart only sees an abbreviation and no package is needed for one call.

`PushController` (`lib/logic/push.dart`, a `ChangeNotifier`) holds the rest:

- `enable` asks once per switch-on (the system prompts only the first time) and registers `{token, installationId, platform, timezone}` with `POST /v1/devices`; a refusal returns the PWA's sentence instead.
- `register` runs again on each launch and sign-in while reminders are on, and on every token refresh, so the api has the current token and zone; a replaced token is unregistered.
- `unregister` deletes the registration when the switch goes off and before sign-out, while the ID token still works.
- `refreshSummary` reads `GET /v1/me/reminders/summary` for Settings, and `sendTest` posts `/v1/me/reminders/test` and returns the sentence for the snackbar.

The installation id is a UUID made once and kept in shared preferences. `main.dart` builds the controller only with Firebase, next to the api client. `RewardApp` routes each tap, and the one that launched the app, through `handleNotificationTap`, so a reminder opens Today and a change notice opens `/cards/<id>`; a push in the foreground, which the system does not show, appears in the snackbar with its title.

iOS declares `aps-environment` in `Runner.entitlements` and the `remote-notification` background mode; the App ID already had Push Notifications, and the APNs key is uploaded to Firebase by hand (runbook 08, step 3.6). Android needs no declaration: the plugin brings `POST_NOTIFICATIONS`.

## Forms and the Field pattern

`Field` is the PWA's `Field` ([[design#Screens#Forms and errors]]): a labelled control with a hint and an error slot, where the field owns *when* an error shows and the caller owns *whether* there is one.

The caller passes the label, the hint, the current rule result from the domain's validation, whether the field is required, whether the form has been submitted, and a focus node it owns. `Field` watches the node and marks itself touched when focus leaves; the error shows once touched or once submitted, never on the first keystroke. The control is built by the caller from a `FieldControl`, the focus node and an `InputDecoration` carrying the label (with a `*` when required, which the form explains once with "Fields marked * are required.") and the invalid border. The hint and the error are drawn by `Field` under the control, not by the decorator, because the decorator hides the helper behind the error and its live region depends on the platform; the error slot is always present and a live region, so a message arriving in it is announced. Forms keep the focus nodes so a submit with errors can focus the first invalid field; Save is never disabled, since a disabled button never says why.

### The editors

`CardEditorScreen` and `BenefitEditorScreen` are the PWA's editors ([[design#Screens]]): live-writing forms on the Field pattern, framed by `EditorScaffold`.

Fields write the store as soon as their value is valid, as the PWA's editors do; what was typed is kept apart in a draft, so an invalid value shows its error on blur without being written or snapped back, and back asks "Leave without saving?" only while a field still holds such a value. `EditorScaffold` gives each its app bar with the entity's name as the title, a subtitle, Back and a trailing action, computes the width class from the window and hosts the snackbar, since the route sits outside the shell; `FieldGrid` pairs short fields two to a row from expanded and gives panels and buttons the row; `SwitchRow` is the shared titled switch with one label for the screen reader. An unknown id renders the not-found title and line rather than throwing.

- **Card editor** (`/cards/:id`): the label (`labelError`, the product name when blank), annual fee (`moneyError`), renews on (`anniversaryError`), the network and the kind as two choice chips (`KindChoice`, Personal or Business); silence and archive switches; the credits by name, each a link to its editor with its cadence, value and whether it needs enrolment or is paused; "Add", which adds a "New credit" through `addBenefit` and opens it; and delete on the app bar, which confirms because it cascades, then says "Card deleted." and returns to Cards.
- **Benefit editor** (`/benefit/:id`): name, value (`positiveMoneyError`), cadence with the ladder summary under it, the anchor as two choice chips (they wrap where a segmented button overflows at a large text size) with the window the cadence and anchor produce under them, recomputed on every change through `cycleFor` because those two fields decide whether a reminder arrives in time, or for a rolling credit "Months between claims" (`intervalMonthsError`) in place of the anchor; an optional end date (`endsOnError`), which the window preview and the credit sheet's header then show; category, merchant, the enrolment switch with the enrolled switch and the page URL (`enrollmentUrlError`) behind it, the optional spend threshold (`moneyError`) with the "Spend reached this year" switch behind it (`confirmSpend`, `revokeSpend`), the redemption steps one per line, and the tracking, last-call and silence switches; Done returns to the card; delete confirms, says "Credit deleted." and returns to the card. The credit sheet's "Edit this credit" leads here.

Pinned by [[mobile-tests#Editors]]; both editors, the expanded card editor, the benefit editor with a spend threshold, the rolling one, the one with an end date and the not-found state have previews.

### Add a card

`AddCardScreen` is the PWA's two-step flow at `/cards/new`: pick the product, then label it and say when the cardmember year turns over.

A product the household already holds gets its numbered default label in the field (`defaultLabel`), because every card's display name is unique and the whole app turns on telling two identical Platinums apart ([[domain#Card]]).

The catalogue opens with a header whose filled "Add card" button (from medium up "Add card manually") opens the blank template's form, so manual entry never needs a scroll. Below it, every template but the blank one is listed in `sortByValue` order ([[domain#Catalogue filter]]) with its issuer, product, fee, annual value from `templateAnnualValueCents`, credit count and how many need enrolment. The list ends with "Don't see your card?" and an "Enter it manually" text button that opens the same form. Both buttons keep a 48dp target despite the theme's compact density. The form shows the picked template's summary, the required note, and the fields: Issuer and Card for the blank template, the optional label, "Account opened / renews on" (a text field with a calendar button that opens Material's date picker), and the kind chips, which start on the template's kind and can be changed before saving. The rules are `requiredError`, `labelError` and `anniversaryError`; a blank label on the blank template saves the numbered default when its product is already held. Save calls `addCardFromTemplate`, shows "Added with N credits. Check the terms — issuers change them." or "Card added. Add its credits next." and goes to the card's editor. A `PopScope` handles back: from the catalogue it leaves for Cards; from an untouched form it returns to the catalogue at once; from a draft it asks "Discard this card?" first. From expanded the short fields pair two to a row. Pinned by [[mobile-tests#Field]] and [[mobile-tests#Add a card]]; the Field, the catalogue and the details step (through the screen's `initialTemplate`, which exists for the preview) have previews.

#### Catalogue filter

From medium width up, the catalogue step leaves the content column for a row up to 1080 wide. The filter panel is on the left (200 wide in medium, 240 in expanded) and the template list on the right.

`CatalogFilterController` is a `ChangeNotifier` owned by `AddCardScreen`. It holds a `CatalogFilter` ([[domain#Catalogue filter]]), the search `TextEditingController` and the merchant sub-search controller, so leaving the screen resets everything and nothing reaches the URL. The screen and the panel rebuild through `ListenableBuilder`. Because the controllers live in the notifier, typing keeps the caret, and "Clear all" can empty both fields.

`CatalogFilterPanel` shows the search field, then Annual fee, Network, Card kind (Personal and Business, only those the catalogue has), Issuer and Benefit merchant. Each group has a header and one `CheckboxListTile` per option, with the count on the right. A zero-count option is drawn at half opacity until it is checked, and it can still be selected. The merchant group has its own sub-search, which narrows the options and not the cards. It lists six merchants with "Show all" / "Show fewer", and while the sub-search has text it lists every match without the toggle.

The results header holds "Card catalogue", "N of 16 cards" in a live region, "Clear all" whenever a facet or the search is active, and the manual-entry button. Below it is one `InputChip` per selected value, whose delete tooltip reads "Remove Chase filter". When nothing matches, the list says "No cards match. Try removing a filter, or add your card manually." and shows an "Add card manually" button. Pinned by [[mobile-tests#Catalogue filter]]. The expanded catalogue, the panel alone and the sheet have previews.

When a merchant is selected or the search has text, each tile names the credits that matched ([[domain#Catalogue filter]] `matchedBenefits`) as tags under the product name. Each tag shows a Material icon for the credit's category (`benefitCategoryIcon`, since the catalogue's Phosphor names only render in the PWA), its name, and its value per cycle from `formatValuePerCycle`. The tag is drawn on the accent ramp's 900 ground with 200 text, which is the container pair in both themes. The tile's screen-reader label adds "Matches Uber Cash (monthly), $15/mo; …". `AddCardScreen.initialFilter` exists only for the matched-credits preview.

In compact there is no panel. The header gains a 48dp "Filters" `OutlinedButton` with a `Badge` showing `activeCount`. The badge is hidden at zero and ignores the search text. The chips stay above the list. The button opens `showCatalogFilterSheet`, a modal bottom sheet (`isScrollControlled`, at most 80% of the height) holding the same `CatalogFilterPanel` under a "Filters" header with a "Show N" button. Checks apply behind the scrim at once, so "Show N" only closes the sheet. "Show N", a scrim tap and system back all close it with the selection kept, and focus returns to the Filters button. When the window grows past 600 with the sheet open, the sheet pops itself and the side panel shows the same controller's state.

## The swipe row

`SwipeRow` is the PWA's swipe-to-act ([[design#Screens]]) around `CreditRow`: swipe right to log the whole credit, left to silence it, parked open rather than fired, with a route for every gesture.

Material's `Dismissible` fires on release and cannot park, so the gesture is a `OneSequenceGestureRecognizer` of its own inside a `RawGestureDetector`, with the PWA's numbers: the gesture becomes a swipe only once horizontal movement passes 10 logical pixels, and bows out of the arena the moment vertical movement passes 10 and leads, so the list's own scroll is never stolen; the row rubber-bands past the 84 pixel action width at 0.28; releasing past 55% of that width, or a flick over 0.45 pixels per millisecond in the row's direction, parks the row open at 84 with the action button exposed, and anything less springs back. Parking rather than firing is the point: an irreversible action should not be one accidental flick away, so the exposed "Log it" or "Silence" still needs a tap. A tap anywhere else closes an open row through `TapRegion.onTapOutside`. The mouse is ignored as in the PWA. The action sits behind the content in a `Stack` and is only built while the row is open, so a closed row keeps it out of the tree and the semantics; a `Transform.translate` slides the content.

`CreditRow` takes `onOpen`, `onLogAll` and `onToggleMute`. Tap opens the sheet through an `InkWell`; the bell on every row silences with the credit named in its label ("Silence reminders for Uber Cash"), because the row's title is not enough context in a long list; and each gesture is a `CustomSemanticsAction` on the row ("Log the full credit", "Silence" or "Unsilence"), so a screen reader and a switch reach both without the gesture, as the table in [[design#Accessibility#Pointer accelerators and their keyboard routes]] asks. The leading action exists only on a claimable row, and a captured or manual row has the gesture disabled; a locked row can still be silenced. The callbacks are meant to be the shared `CreditActions` ([[mobile-architecture#Undo and the snackbar]]), so a swipe does exactly what the sheet does. Pinned by [[mobile-tests#Swipe row]]; the interactive rows have a Widget Preview.

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
- **Every gesture has a route**: every action on the credit sheet is a labelled button or switch ([[mobile-tests#Credit sheet#Every control on the sheet has a label]]), and each swipe on a row is also a custom semantics action and a button a screen reader and a switch can reach ([[mobile-architecture#The swipe row]]), as the PWA's table in [[design#Accessibility]] lists.
- **Orientation is never locked** and the compact class covers a landscape phone.

## Make targets

`apps/mobile/Makefile` is the app's script runner, the counterpart of the PWA's `package.json` scripts, and every recipe goes through `fvm flutter` or `fvm dart` so the SDK is the one in `.fvmrc`.

`make init` installs FVM if needed, fetches the pinned SDK, resolves the workspace and runs `flutter doctor`. `make build ios|android|macos` produces a release build and a bare `make build` does the two store platforms, `make test` runs the widget suite and `make test ios` adds the e2e run, `make e2e [android]` runs `integration_test/` on a simulator or emulator it boots if needed, `make run` lists devices and asks for one because Flutter would otherwise silently pick the only booted simulator, `make run ios|android` boots a visible simulator or emulator, `make run macos` opens the app in a resizable window, and `make deploy VERSION=x.y.z` tags `develop` so the release workflow ships both stores ([[deployment#Pipeline]]). `scripts/pick-device.sh` does the device choosing for `e2e` and `run`. The README beside it lists every target; pinned by [[infra-tests#Infrastructure config#Mobile Makefile is the app's script runner]].

macOS is a local target only, added by issue #117 so the medium and expanded classes ([[mobile-architecture#Responsive layout]]) can be tried on a laptop: `apps/mobile/macos/` is the `flutter create` output on Swift Package Manager with no Podfile, both entitlements files grant `network.client` for the api client, and neither `deploy` nor the release workflow builds it; pinned by [[infra-tests#Infrastructure config#macOS is a local run target only]].
