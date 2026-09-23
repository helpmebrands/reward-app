import 'dart:convert';
import 'dart:io';

import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reward/data/snapshot_store.dart';
import 'package:reward/logic/app_store.dart';
import 'package:reward/logic/ui_state.dart';
import 'package:reward/main.dart';
import 'package:reward/shell/router.dart';

/// The catalogue filter on the add-card screen: the side panel from medium
/// width up, its chips, counts and empty state.

AppData sampleHousehold() => appDataFromJson(
  jsonDecode(File('../pwa/samples/sample-household.json').readAsStringSync())
      as Map<String, dynamic>,
);

Future<void> pumpCatalogue(
  WidgetTester tester, {
  Size size = const Size(1280, 2000),
  double textScale = 1,
}) async {
  final store = AppStore(
    store: MemorySnapshotStore(sampleHousehold()),
    clock: () => DateTime(2026, 9, 16, 8),
  );
  await store.load();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    RewardApp(store: store, ui: UiState(), initialLocation: Paths.newCard),
  );
  await tester.pumpAndSettle();
}

final int total = filterTemplates(cardTemplates, const CatalogFilter()).length;

Finder keyPrefix(String prefix) => find.byWidgetPredicate(
  (w) =>
      w.key is ValueKey<String> &&
      (w.key! as ValueKey<String>).value.startsWith(prefix),
);

Finder get tiles => keyPrefix('template-');

Finder facet(String id) => find.byKey(ValueKey('facet-$id'));

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder chip(String label) =>
    find.widgetWithText(InputChip, label, skipOffstage: false);

void main() {
  // @lat: [[mobile-tests#Catalogue filter#Checking an issuer narrows the list and adds a chip]]
  testWidgets('checking Chase narrows to its cards and the chip undoes it', (
    tester,
  ) async {
    await pumpCatalogue(tester);
    expect(find.text('$total of $total cards'), findsOneWidget);
    expect(tiles, findsNWidgets(total));

    await tap(tester, facet('issuer-Chase'));
    expect(find.text('4 of $total cards'), findsOneWidget);
    expect(tiles, findsNWidgets(4));
    expect(chip('Chase'), findsOneWidget);

    await tap(tester, find.byTooltip('Remove Chase filter'));
    expect(find.text('$total of $total cards'), findsOneWidget);
    expect(chip('Chase'), findsNothing);
  });

  // @lat: [[mobile-tests#Catalogue filter#Facets combine and counts follow the other facets]]
  testWidgets('Chase and \$600+ narrow together; fee counts follow Chase', (
    tester,
  ) async {
    await pumpCatalogue(tester);
    await tap(tester, facet('issuer-Chase'));
    Finder count(String id, String n) =>
        find.descendant(of: facet(id), matching: find.text(n));
    expect(count('fee-under100', '2'), findsOneWidget);
    expect(count('fee-from100', '1'), findsOneWidget);
    expect(count('fee-from400', '0'), findsOneWidget);
    expect(count('fee-from600', '1'), findsOneWidget);

    await tap(tester, facet('fee-from600'));
    expect(tiles, findsOneWidget);
    expect(
      find.byKey(const ValueKey('template-chase-sapphire-reserve')),
      findsOneWidget,
    );
    expect(chip('\$600+'), findsOneWidget);
    expect(find.text('1 of $total cards'), findsOneWidget);
  });

  // @lat: [[mobile-tests#Catalogue filter#Search narrows per keystroke and Clear all resets everything]]
  testWidgets('search narrows as you type and Clear all resets it all', (
    tester,
  ) async {
    await pumpCatalogue(tester);
    final search = find.byKey(const Key('catalog-search'));
    expect(find.text('Clear all'), findsNothing);
    for (final typed in ['u', 'ub', 'ube', 'uber']) {
      await tester.enterText(search, typed);
      await tester.pumpAndSettle();
      final n = filterTemplates(
        cardTemplates,
        CatalogFilter(search: typed),
      ).length;
      expect(tiles, findsNWidgets(n), reason: typed);
      expect(find.text('$n of $total cards'), findsOneWidget);
    }
    await tap(tester, facet('issuer-Chase'));
    await tester.enterText(find.byKey(const Key('merchant-search')), 'dash');
    await tester.pumpAndSettle();

    await tap(tester, find.text('Clear all'));
    expect(find.text('$total of $total cards'), findsOneWidget);
    expect(tester.widget<TextField>(search).controller!.text, isEmpty);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('merchant-search')))
          .controller!
          .text,
      isEmpty,
    );
    expect(find.byType(InputChip), findsNothing);
    expect(find.text('Clear all'), findsNothing);
  });

  // @lat: [[mobile-tests#Catalogue filter#The merchant group shows six and searches its own options]]
  testWidgets(
    'merchants show six, all on request, and every sub-search match',
    (tester) async {
      // Tall enough that the panel builds every merchant row.
      await pumpCatalogue(tester, size: const Size(1280, 5000));
      final merchants = facetCounts(
        cardTemplates,
        const CatalogFilter(),
      ).merchants.keys.toList();
      expect(keyPrefix('facet-merchant-'), findsNWidgets(6));
      await tap(tester, find.text('Show all'));
      expect(keyPrefix('facet-merchant-'), findsNWidgets(merchants.length));
      await tap(tester, find.text('Show fewer'));
      expect(keyPrefix('facet-merchant-'), findsNWidgets(6));

      await tester.enterText(find.byKey(const Key('merchant-search')), 'a');
      await tester.pumpAndSettle();
      final matching = merchants.where((m) => m.toLowerCase().contains('a'));
      expect(matching.length, greaterThan(6));
      expect(keyPrefix('facet-merchant-'), findsNWidgets(matching.length));
      expect(find.text('Show all'), findsNothing);
      expect(find.text('$total of $total cards'), findsOneWidget);
    },
  );

  // @lat: [[mobile-tests#Catalogue filter#No match shows the empty state with manual entry]]
  testWidgets('a filter that matches nothing offers manual entry', (
    tester,
  ) async {
    await pumpCatalogue(tester);
    await tester.enterText(find.byKey(const Key('catalog-search')), 'zzzz');
    await tester.pumpAndSettle();
    expect(tiles, findsNothing);
    expect(
      find.text(
        'No cards match. Try removing a filter, or add your card manually.',
      ),
      findsOneWidget,
    );
    await tap(tester, find.byKey(const Key('add-manually-empty')));
    expect(find.text('Card details'), findsOneWidget);
    expect(find.byKey(const Key('field-issuer')), findsOneWidget);
  });

  // @lat: [[mobile-tests#Catalogue filter#The result count is a live region]]
  testWidgets('the result count is announced as a live region', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpCatalogue(tester);
    final node = tester.getSemantics(find.text('$total of $total cards'));
    expect(node.flagsCollection.isLiveRegion, isTrue);
    handle.dispose();
  });

  // @lat: [[mobile-tests#Catalogue filter#The panel at 200% clips nothing]]
  testWidgets('at 720 wide and a 2.0 text scale nothing clips', (tester) async {
    await pumpCatalogue(tester, size: const Size(720, 4000), textScale: 2);
    await tap(tester, facet('issuer-American Express'));
    await tap(tester, facet('merchant-Adobe'));
    expect(tester.takeException(), isNull);
    final texts = find.byType(Text);
    for (var i = 0; i < texts.evaluate().length; i++) {
      expect(
        tester.getRect(texts.at(i)).right,
        lessThanOrEqualTo(720.5),
        reason: tester.widget<Text>(texts.at(i)).data,
      );
    }
  });
}
