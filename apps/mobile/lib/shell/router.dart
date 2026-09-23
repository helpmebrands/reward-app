import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../logic/app_store.dart';
import '../screens/add_card_screen.dart';
import '../screens/cards_screen.dart';
import '../screens/credits_screen.dart';
import '../screens/stub_screen.dart';
import '../screens/today_screen.dart';
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
}

/// The card editor's path for one card.
String cardPath(String id) => '/cards/$id';

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

/// The route table: the four destinations as branches of one stateful shell,
/// each keeping its own navigator and scroll position. The store is the
/// refresh listenable so a later redirect re-evaluates on every notification.
GoRouter appRouter(AppStore store, {String initialLocation = Paths.today}) =>
    GoRouter(
      refreshListenable: store,
      initialLocation: initialLocation,
      routes: [
        // Full-screen routes above the shell. `/cards/new` is declared before
        // `/cards/:id` so the literal wins the match.
        GoRoute(
          path: Paths.newCard,
          builder: (context, state) => AddCardScreen(
            store: AppScope.of(context),
            ui: UiScope.of(context),
          ),
        ),
        GoRoute(
          path: '/cards/:id',
          builder: (context, state) => const StubScreen('Card editor'),
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
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: Paths.value,
                  builder: (context, state) => const StubScreen('Value'),
                ),
              ],
            ),
          ],
        ),
      ],
    );
