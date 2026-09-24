import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../logic/app_store.dart';
import '../logic/session.dart';
import '../screens/add_card_screen.dart';
import '../screens/benefit_editor_screen.dart';
import '../screens/card_editor_screen.dart';
import '../screens/cards_screen.dart';
import '../screens/credits_screen.dart';
import '../screens/join_screen.dart';
import '../screens/not_found_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/sign_in_screen.dart';
import '../screens/today_screen.dart';
import '../screens/value_screen.dart';
import '../screens/welcome_screen.dart';
import 'app_scope.dart';
import 'app_shell.dart';
import 'ui_scope.dart';

/// Route paths, the PWA's, written by hand rather than generated.
abstract final class Paths {
  static const today = '/';
  static const credits = '/credits';
  static const cards = '/cards';
  static const value = '/value';
  static const newCard = '/cards/new';
  static const settings = '/settings';
  static const welcome = '/welcome';
  static const signIn = '/sign-in';
}

/// The join screen's path for one invite code, as the invite links spell it.
String invitePath(String code) => '/invite/${Uri.encodeComponent(code)}';

/// Where the redirect sends a signed-out launch, and where signing in
/// returns to, from the session's two pieces of state:
///
/// | State | Destination |
/// | --- | --- |
/// | Signed in | the app (the `from` a sign-in was sent from, or Today) |
/// | Signed out, intro seen | sign-in |
/// | Signed out, intro unseen | the slideshow, then sign-in |
///
/// The slideshow stays reachable while signed out, which is how "Learn
/// more" replays it. A signed-out deep link carries `from`, so the person
/// lands where they meant to after signing in.
String? signInRedirect(Session session, GoRouterState state) {
  final location = state.matchedLocation;
  final onEntry = location == Paths.welcome || location == Paths.signIn;
  final query = state.uri.queryParameters;
  if (session.signedIn) {
    return onEntry ? (query['from'] ?? Paths.today) : null;
  }
  if (onEntry) {
    return !session.introSeen && location == Paths.signIn
        ? Uri(path: Paths.welcome, queryParameters: query).toString()
        : null;
  }
  final from = state.uri.toString();
  return Uri(
    path: session.introSeen ? Paths.signIn : Paths.welcome,
    queryParameters: from == Paths.today ? null : {'from': from},
  ).toString();
}

/// [path] carrying the `from` of [state] along.
String _keepFrom(String path, GoRouterState state) {
  final from = state.uri.queryParameters['from'];
  return Uri(
    path: path,
    queryParameters: from == null ? null : {'from': from},
  ).toString();
}

/// The card editor's path for one card.
String cardPath(String id) => '/cards/$id';

/// The benefit editor's path for one credit.
String benefitPath(String id) => '/benefit/$id';

/// One of the four destinations the bar and the rail share, in the order
/// both show them.
class Destination {
  const Destination(this.label, this.icon, this.selectedIcon, this.path);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String path;
}

const destinations = [
  Destination('Today', Icons.today_outlined, Icons.today, Paths.today),
  Destination(
    'Credits',
    Icons.receipt_long_outlined,
    Icons.receipt_long,
    Paths.credits,
  ),
  Destination(
    'Cards',
    Icons.credit_card_outlined,
    Icons.credit_card,
    Paths.cards,
  ),
  Destination('Value', Icons.insights_outlined, Icons.insights, Paths.value),
];

/// The root navigator, which the full-screen routes are pushed on so they
/// sit above the shell rather than inside a branch.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);

/// The route table: the four destinations as branches of one stateful shell,
/// each keeping its own navigator and scroll position, and the full-screen
/// routes as children of the branch they belong under, pushed on the root
/// navigator so the shell stays beneath them. The store and the [session]
/// are the refresh listenable, so the sign-in redirect re-evaluates when
/// either changes, and an unknown path renders the not-found screen.
/// Without a session (tests of the screens behind sign-in) there is no
/// redirect.
GoRouter appRouter(
  AppStore store, {
  String initialLocation = Paths.today,
  Session? session,
}) => GoRouter(
  navigatorKey: rootNavigatorKey,
  refreshListenable: session == null
      ? store
      : Listenable.merge([store, session]),
  initialLocation: initialLocation,
  redirect: session == null
      ? null
      : (context, state) => signInRedirect(session, state),
  errorBuilder: (context, state) => const NotFoundScreen(),
  routes: [
    if (session != null) ...[
      GoRoute(
        path: Paths.welcome,
        builder: (context, state) => WelcomeScreen(
          onDone: () async {
            await session.finishIntro();
            if (context.mounted) context.go(_keepFrom(Paths.signIn, state));
          },
        ),
      ),
      GoRoute(
        path: Paths.signIn,
        builder: (context, state) => SignInScreen(
          auth: session.auth,
          onLearnMore: () => context.go(_keepFrom(Paths.welcome, state)),
          // A code typed before signing in is kept as `from`, so signing in
          // lands on the join screen.
          onInviteCode: (code) => context.go(invitePath(code)),
        ),
      ),
    ],
    GoRoute(
      path: '/invite/:code',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => JoinScreen(
        store: AppScope.of(context),
        ui: UiScope.of(context),
        code: state.pathParameters['code']!.toUpperCase(),
      ),
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AppShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Paths.today,
              builder: (context, state) => TodayScreen(
                store: AppScope.of(context),
                ui: UiScope.of(context),
              ),
              routes: [
                GoRoute(
                  path: 'benefit/:id',
                  parentNavigatorKey: rootNavigatorKey,
                  builder: (context, state) => BenefitEditorScreen(
                    store: AppScope.of(context),
                    ui: UiScope.of(context),
                    id: state.pathParameters['id']!,
                  ),
                ),
                GoRoute(
                  path: 'settings',
                  parentNavigatorKey: rootNavigatorKey,
                  builder: (context, state) => SettingsScreen(
                    store: AppScope.of(context),
                    ui: UiScope.of(context),
                    session: session,
                  ),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Paths.credits,
              builder: (context, state) => CreditsScreen(
                store: AppScope.of(context),
                ui: UiScope.of(context),
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Paths.cards,
              builder: (context, state) => CardsScreen(
                store: AppScope.of(context),
                ui: UiScope.of(context),
              ),
              // `new` is declared before `:id` so the literal wins the match.
              routes: [
                GoRoute(
                  path: 'new',
                  parentNavigatorKey: rootNavigatorKey,
                  builder: (context, state) => AddCardScreen(
                    store: AppScope.of(context),
                    ui: UiScope.of(context),
                  ),
                ),
                GoRoute(
                  path: ':id',
                  parentNavigatorKey: rootNavigatorKey,
                  builder: (context, state) => CardEditorScreen(
                    store: AppScope.of(context),
                    ui: UiScope.of(context),
                    id: state.pathParameters['id']!,
                  ),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Paths.value,
              builder: (context, state) =>
                  ValueScreen(store: AppScope.of(context)),
            ),
          ],
        ),
      ],
    ),
  ],
);

/// A tapped notification opens the screen its payload names: the counterpart
/// of the PWA's `navigate` message from the worker. The payload is a map
/// with a `url`, or the url itself; anything that is not an app path is
/// ignored, so the delivery epic only has to call this.
void handleNotificationTap(GoRouter router, Object? payload) {
  final url = switch (payload) {
    String s => s,
    Map<Object?, Object?> m => m['url'],
    _ => null,
  };
  if (url is String && url.startsWith('/')) router.go(url);
}
