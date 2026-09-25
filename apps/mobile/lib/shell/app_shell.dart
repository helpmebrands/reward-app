import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../logic/credit_actions.dart';
import '../widgets/compare_sheet.dart';
import '../widgets/credit_sheet.dart';
import '../widgets/sheet_host.dart';
import '../widgets/snackbar_host.dart';
import 'app_scope.dart';
import 'router.dart';
import 'ui_scope.dart';
import 'width_class.dart';

/// The app shell: the four destinations as a bottom bar in the compact class
/// and a rail from medium, the centred content column the screens render
/// into, and the one credit sheet whichever tab opened it. The width class is
/// computed once here, from the window width, and handed down; no leaf widget
/// re-derives it.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final widthClass = WidthClass.forWidth(MediaQuery.sizeOf(context).width);
    final ui = UiScope.of(context);
    final store = AppScope.of(context);
    final actions = CreditActions(store: store, snackbar: ui.snackbar);
    final openId = ui.openBenefitId;
    final overlap = ui.openOverlapLabel == null
        ? null
        : store.overlapFor(ui.openOverlapLabel!);
    // The compare sheet sits above the credit sheet: a side of a compare
    // opens that credit, closing the compare first.
    return SheetHost(
      open: overlap != null,
      widthClass: widthClass,
      wide: SheetWide.dialog,
      sheetKey: const Key('compare-sheet'),
      title: overlap?.label ?? '',
      onClose: ui.closeOverlap,
      sheet: overlap == null
          ? null
          : CompareSheet(
              overlap: overlap,
              actions: actions,
              onClose: ui.closeOverlap,
              onOpenCredit: (id) {
                ui.closeOverlap();
                ui.openCredit(id);
              },
            ),
      child: SheetHost(
        open: openId != null,
        widthClass: widthClass,
        title: openId == null
            ? ''
            : store.instanceFor(openId)?.benefit.name ?? 'Credit',
        onClose: ui.closeCredit,
        sheet: openId == null
            ? null
            : CreditSheet(
                actions: actions,
                benefitId: openId,
                onClose: ui.closeCredit,
              ),
        child: _Scaffold(
          navigationShell: navigationShell,
          widthClass: widthClass,
        ),
      ),
    );
  }
}

/// The bar or the rail around the content column.
class _Scaffold extends StatelessWidget {
  const _Scaffold({required this.navigationShell, required this.widthClass});

  final StatefulNavigationShell navigationShell;
  final WidthClass widthClass;

  @override
  Widget build(BuildContext context) {
    // The snackbar lives inside the column, so it centres on the column the
    // rail pushes off centre and sits above the bar, never over it.
    final column = WidthClassScope(
      widthClass: widthClass,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          key: const Key('content-column'),
          constraints: BoxConstraints(maxWidth: widthClass.column),
          child: SnackbarHost(
            snackbar: UiScope.of(context).snackbar,
            child: navigationShell,
          ),
        ),
      ),
    );

    if (widthClass == WidthClass.compact) {
      return Scaffold(
        body: SafeArea(child: column),
        bottomNavigationBar: NavigationBar(
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: (index) {
            UiScope.of(context).keepFocusOnDestination = true;
            navigationShell.goBranch(index);
          },
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
              onDestinationSelected: (index) {
                UiScope.of(context).keepFocusOnDestination = true;
                navigationShell.goBranch(index);
              },
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
