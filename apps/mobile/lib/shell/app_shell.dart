import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'router.dart';
import 'width_class.dart';

/// The app shell: the four destinations as a bottom bar in the compact class
/// and a rail from medium, and the centred content column the screens render
/// into. The width class is computed once here, from the window width, and
/// handed down; no leaf widget re-derives it.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final widthClass = WidthClass.forWidth(MediaQuery.sizeOf(context).width);
    final column = WidthClassScope(
      widthClass: widthClass,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          key: const Key('content-column'),
          constraints: BoxConstraints(maxWidth: widthClass.column),
          child: navigationShell,
        ),
      ),
    );

    if (widthClass == WidthClass.compact) {
      return Scaffold(
        body: SafeArea(child: column),
        bottomNavigationBar: NavigationBar(
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: navigationShell.goBranch,
          destinations: [
            for (final d in destinations)
              NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selectedIcon),
                label: d.label,
              ),
          ],
        ),
      );
    }

    final extended = widthClass == WidthClass.expanded;
    // The design fixes the rail at 80 or 200; the rail's own minimum widths
    // would let a wide label push it out, so the width is pinned.
    final railWidth = extended ? 200.0 : 80.0;
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: railWidth,
            child: NavigationRail(
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: navigationShell.goBranch,
              extended: extended,
              labelType: extended
                  ? NavigationRailLabelType.none
                  : NavigationRailLabelType.all,
              minWidth: 80,
              minExtendedWidth: 200,
              destinations: [
                for (final d in destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(d.label),
                  ),
              ],
            ),
          ),
          Expanded(child: SafeArea(child: column)),
        ],
      ),
    );
  }
}
