import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../logic/app_store.dart';
import '../screens/stub_screen.dart';
import '../screens/today_screen.dart';
import 'app_scope.dart';
import 'app_shell.dart';

/// Route paths, the PWA's, written by hand rather than generated.
abstract final class Paths {
  static const today = '/';
  static const credits = '/credits';
  static const cards = '/cards';
  static const value = '/value';
}

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
GoRouter appRouter(AppStore store) => GoRouter(
  refreshListenable: store,
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AppShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Paths.today,
              builder: (context, state) =>
                  TodayScreen(store: AppScope.of(context)),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Paths.credits,
              builder: (context, state) => const StubScreen('Credits'),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Paths.cards,
              builder: (context, state) => const StubScreen('Cards'),
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
