import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../logic/app_store.dart';
import '../screens/add_card_screen.dart';
import '../screens/benefit_editor_screen.dart';
import '../screens/card_editor_screen.dart';
import '../screens/cards_screen.dart';
import '../screens/credits_screen.dart';
import '../screens/not_found_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/today_screen.dart';
import '../screens/value_screen.dart';
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
/// navigator so the shell stays beneath them. The store is the refresh
/// listenable so a later redirect re-evaluates on every notification, and
/// an unknown path renders the not-found screen.
GoRouter appRouter(
  AppStore store, {
  String initialLocation = Paths.today,
}) => GoRouter(
  navigatorKey: rootNavigatorKey,
  refreshListenable: store,
  initialLocation: initialLocation,
  errorBuilder: (context, state) => const NotFoundScreen(),
  routes: [
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
