# Mobile

The Flutter app in `apps/mobile`: the product in [[overview]] rebuilt on [[domain|the shared domain]] for iOS and Android. It replaced the PWA, retired in issue #174 once it reached parity.

- [[mobile-architecture]] — The UI, logic and data layers, the Nocturne theme and the workspace wiring.
- [[mobile-tests]] — What the Flutter suites guard: the theme, the store, the Today, Credits, Cards, Value, Add a card, editor, Settings and not-found screens, the routing polish, the Field pattern, the credit sheet, the swipe row, the undo snackbar and push.

## Parity checklist

Every feature of the PWA, from [[design#Screens]], with the Flutter counterpart that covers it and the test that pins it; the input to the PWA's retirement in issue #174, where every row was ticked or closed.

| PWA feature | Flutter counterpart | Pinned by |
| --- | --- | --- |
| Today: headline, countdown, use-soon, locked and captured rows, three overlaps | `TodayScreen` ([[mobile-architecture#Today screen]]) | [[mobile-tests#Today]] |
| Today: rows open the sheet and swipe, compare sheet, nudge preview | `TodayScreen` with `UiState` ([[mobile-architecture#Today screen#Today's interactions]]) | [[mobile-tests#Today interactions]] |
| Credits: six filters, three groupings, four totals and opted out, missed rows | `CreditsScreen` ([[mobile-architecture#Credits screen]]) | [[mobile-tests#Credits]] |
| Cards: verdict and tags, fee bar, edit and add | `CardsScreen` ([[mobile-architecture#Cards screen]]) | [[mobile-tests#Cards]] |
| Cards: mute, archive and delete | the card menu ([[mobile-architecture#Cards screen]]) | [[mobile-tests#Cards#Mute from the menu offers an undo]] |
| Value: totals, monthly chart, worst-first ranks, leaks | `ValueScreen` and `MonthlyBarsPainter` ([[mobile-architecture#Value screen]]) | [[mobile-tests#Value]] |
| Add a card: catalogue, label and anniversary, the blank card | `AddCardScreen` ([[mobile-architecture#Forms and the Field pattern#Add a card]]) | [[mobile-tests#Add a card]] |
| Forms and errors: label, hint, error on blur or submit, Save never disabled | `Field` ([[mobile-architecture#Forms and the Field pattern]]) | [[mobile-tests#Field]] |
| Card editor and benefit editor with the live window | `CardEditorScreen`, `BenefitEditorScreen` ([[mobile-architecture#Forms and the Field pattern#The editors]]) | [[mobile-tests#Editors]] |
| Settings: reminder preferences, the ladder table, appearance | `SettingsScreen` ([[mobile-architecture#Settings screen]]) | [[mobile-tests#Settings]] |
| New in the app: the welcome slideshow and sign-in with Google or Apple | `WelcomeScreen`, `SignInScreen`, `Session` ([[mobile-architecture#Sign-in]]) | [[mobile-tests#Sign-in]] |
| The credit sheet: partial logging, logged this period, unlock, ladder, switches | `CreditSheet` ([[mobile-architecture#The credit sheet]]) | [[mobile-tests#Credit sheet]] |
| Sheets by width: bottom sheet, dialog, side panel; Escape, back, focus | `SheetHost` ([[mobile-architecture#The credit sheet]]) | [[mobile-tests#Credit sheet#Compact is a bottom sheet with a scrim]] |
| Swipe rows: direction lock, rubber-band, park open, a route for every gesture | `SwipeRow` and `CreditRow` ([[mobile-architecture#The swipe row]]) | [[mobile-tests#Swipe row]] |
| Undo over confirmation: the snackbar and the shared actions | `SnackbarState`, `SnackbarHost`, `CreditActions` ([[mobile-architecture#Undo and the snackbar]]) | [[mobile-tests#Snackbar]], [[mobile-tests#Credit actions]] |
| The store's mutations, the user's action wins | `AppStore` ([[mobile-architecture#The store#Mutations]]) | [[mobile-tests#Store]] |
| Responsive layout: three width classes, rail and bar, the column | `AppShell` ([[mobile-architecture#Responsive layout]]) | [[mobile-tests#Shell]] |
| Text to 200%, token contrast | ([[mobile-architecture#Accessibility]]) | [[mobile-tests#Text scaling]], [[mobile-tests#Token contrast]] |
| Titles and focus, the not-found route, the notification message | `ScreenTitle`, `NotFoundScreen`, `handleNotificationTap` ([[mobile-architecture#Navigation#Routes and the shell]]) | [[mobile-tests#Routing]] |
| Theme: Nocturne in both modes | `nocturneTheme` ([[mobile-architecture#Theme]]) | [[mobile-tests#Theme]] |
| Reminder delivery: permission, push, periodic sync, the test notification | `PushController` and `FirebasePushMessaging`; the server sends ([[mobile-architecture#Push]], [[api-architecture#Reminder sender]]), so there is no periodic sync | [[mobile-tests#Push]] |
| Your data: export and import a backup | **Won't do**: issue #176 closed as not planned, since the service tier holds the household's data | (none) |
| Forced colours | **Not applicable**: a browser mode; the platforms' high-contrast settings apply through Material | (none) |
| Service worker, install prompt, PWA manifest | **Not applicable**: the store app has no worker | (none) |

The flow in [[mobile-tests#End to end]] runs the ticked rows on a simulator in one pass. Issue #174 retired `apps/pwa` and kept its web slot for [[deployment#Site|the static site]].
