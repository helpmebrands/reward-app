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
  jsonDecode(
        File(
          '../../packages/domain/test/fixtures/sample-household.json',
        ).readAsStringSync(),
      )
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

  // @lat: [[mobile-tests#Catalogue filter#Business narrows to business cards in the panel and the sheet]]
  testWidgets('checking Business in the panel and the sheet', (tester) async {
    await pumpCatalogue(tester);
    await tap(tester, facet('kind-business'));
    expect(chip('Business'), findsOneWidget);
    expect(tiles, findsOneWidget);
    expect(
      find.byKey(const ValueKey('template-amex-business-platinum')),
      findsOneWidget,
    );

    await pumpCatalogue(tester, size: const Size(402, 874));
    await tester.tap(find.byKey(const Key('filters-button')));
    await tester.pumpAndSettle();
    final kind = facet('kind-business');
    await tester.scrollUntilVisible(
      kind,
      100,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('filter-sheet')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(kind);
    await tester.pumpAndSettle();
    expect(find.text('Show 1'), findsOneWidget);
    await tester.tap(find.text('Show 1'));
    await tester.pumpAndSettle();
    expect(chip('Business'), findsOneWidget);
    expect(tiles, findsOneWidget);
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
    // Tall enough to build every tile once the search tags their credits.
    await pumpCatalogue(tester, size: const Size(1280, 6000));
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

  group('matched benefits', () {
    /// Every shown tile carries exactly the tags `matchedBenefits` names.
    void expectTagsMatch(WidgetTester tester, CatalogFilter filter) {
      for (final template in filterTemplates(cardTemplates, filter)) {
        final names = matchedBenefits(template, filter).map((b) => b.name);
        final tags = find.descendant(
          of: find.byKey(ValueKey('template-${template.id}')),
          matching: keyPrefix('match-'),
        );
        expect(
          tags.evaluate().map(
            (e) => (e.widget.key! as ValueKey<String>).value.substring(6),
          ),
          names,
          reason: template.id,
        );
      }
    }

    // @lat: [[mobile-tests#Catalogue filter#A selected merchant tags the benefits it matched]]
    testWidgets('selecting Uber tags the Platinum credits it matched', (
      tester,
    ) async {
      await pumpCatalogue(tester, size: const Size(1280, 5000));
      expect(keyPrefix('match-'), findsNothing);
      await tester.enterText(find.byKey(const Key('merchant-search')), 'uber');
      await tester.pumpAndSettle();
      await tap(tester, facet('merchant-Uber'));

      final platinum = find.byKey(const ValueKey('template-amex-platinum'));
      Finder tag(String name) => find.descendant(
        of: platinum,
        matching: find.byKey(ValueKey('match-$name')),
      );
      final monthly = tag('Uber Cash (monthly)');
      final bonus = tag('Uber Cash (December bonus)');
      expect(monthly, findsOneWidget);
      expect(bonus, findsOneWidget);
      expect(
        find.descendant(of: monthly, matching: find.text(r'$15/mo')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: bonus, matching: find.text(r'$20/yr')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: monthly, matching: find.byType(Icon)),
        findsOneWidget,
      );
      expectTagsMatch(tester, const CatalogFilter().toggleMerchant('Uber'));

      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(platinum).label,
        contains('Matches Uber Cash (monthly)'),
      );
      handle.dispose();
    });

    // @lat: [[mobile-tests#Catalogue filter#The search tags only the benefits it matched]]
    testWidgets('searching "resy" tags only Resy credits', (tester) async {
      await pumpCatalogue(tester, size: const Size(1280, 5000));
      await tester.enterText(find.byKey(const Key('catalog-search')), 'resy');
      await tester.pumpAndSettle();
      expect(keyPrefix('match-'), findsWidgets);
      expectTagsMatch(tester, const CatalogFilter(search: 'resy'));
      for (final e in keyPrefix('match-').evaluate()) {
        expect((e.widget.key! as ValueKey<String>).value, contains('Resy'));
      }
    });
  });

  group('compact', () {
    const phone = Size(402, 874);
    final filters = find.byKey(const Key('filters-button'));
    Badge badge(WidgetTester tester) => tester.widget<Badge>(
      find.descendant(of: filters, matching: find.byType(Badge)),
    );
    final sheet = find.byKey(const Key('filter-sheet'));

    /// The sheet builds only the rows near its viewport, so scroll first.
    Future<void> inSheet(
      WidgetTester tester,
      Finder finder, {
      double by = 100,
    }) async {
      await tester.scrollUntilVisible(
        finder,
        by,
        scrollable: find
            .descendant(of: sheet, matching: find.byType(Scrollable))
            .first,
      );
      await tester.pumpAndSettle();
    }

    Future<void> sheetTap(WidgetTester tester, Finder finder) async {
      await inSheet(tester, finder);
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    Future<void> openSheet(WidgetTester tester) async {
      await tester.tap(filters);
      await tester.pumpAndSettle();
      expect(sheet, findsOneWidget);
    }

    // @lat: [[mobile-tests#Catalogue filter#The Filters badge counts selections, not search text]]
    testWidgets('the badge counts checked values and ignores the search', (
      tester,
    ) async {
      await pumpCatalogue(tester, size: phone);
      expect(find.byKey(const Key('catalog-search')), findsNothing);
      expect(badge(tester).isLabelVisible, isFalse);

      await openSheet(tester);
      await sheetTap(tester, facet('fee-from600'));
      await sheetTap(tester, facet('network-visa'));
      final search = find.byKey(const Key('catalog-search'));
      await inSheet(tester, search, by: -100);
      await tester.enterText(search, 'x');
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(200, 20));
      await tester.pumpAndSettle();

      expect(sheet, findsNothing);
      expect(badge(tester).isLabelVisible, isTrue);
      expect(
        find.descendant(of: filters, matching: find.text('2')),
        findsOneWidget,
      );
    });

    // @lat: [[mobile-tests#Catalogue filter#Show N reports the live count and closes the sheet]]
    testWidgets('"Show 4" follows the Chase check and closes onto 4 tiles', (
      tester,
    ) async {
      await pumpCatalogue(tester, size: phone);
      await openSheet(tester);
      expect(find.text('Show $total'), findsOneWidget);
      await sheetTap(tester, facet('issuer-Chase'));
      expect(find.text('Show 4'), findsOneWidget);

      await tester.tap(find.text('Show 4'));
      await tester.pumpAndSettle();
      expect(sheet, findsNothing);
      expect(chip('Chase'), findsOneWidget);
      expect(find.text('4 of $total cards'), findsOneWidget);
      final focused = FocusManager.instance.primaryFocus!;
      expect(
        find.ancestor(
          of: find.byWidget(focused.context!.widget),
          matching: filters,
        ),
        findsOneWidget,
      );
    });

    // @lat: [[mobile-tests#Catalogue filter#The scrim and system back close the sheet and keep the selection]]
    testWidgets('the scrim and system back both close and keep the selection', (
      tester,
    ) async {
      await pumpCatalogue(tester, size: phone);
      await openSheet(tester);
      await sheetTap(tester, facet('issuer-Chase'));
      await tester.tapAt(const Offset(200, 20));
      await tester.pumpAndSettle();
      expect(sheet, findsNothing);
      expect(chip('Chase'), findsOneWidget);

      await openSheet(tester);
      await sheetTap(tester, facet('issuer-Citi'));
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(sheet, findsNothing);
      expect(find.text('Add a card'), findsOneWidget);
      expect(chip('Chase'), findsOneWidget);
      expect(chip('Citi'), findsOneWidget);
    });

    // @lat: [[mobile-tests#Catalogue filter#Growing past compact swaps the sheet for the panel]]
    testWidgets('widening with the sheet open shows the panel, same state', (
      tester,
    ) async {
      await pumpCatalogue(tester, size: phone);
      await openSheet(tester);
      await sheetTap(tester, facet('issuer-Chase'));

      tester.view.physicalSize = const Size(1280, 2000);
      await tester.pumpAndSettle();
      expect(sheet, findsNothing);
      expect(filters, findsNothing);
      expect(
        tester.widget<CheckboxListTile>(facet('issuer-Chase')).value,
        isTrue,
      );
      expect(find.text('4 of $total cards'), findsOneWidget);

      tester.view.physicalSize = phone;
      await tester.pumpAndSettle();
      expect(chip('Chase'), findsOneWidget);
      expect(find.text('4 of $total cards'), findsOneWidget);
    });

    // @lat: [[mobile-tests#Catalogue filter#The sheet keeps 48dp targets and clips nothing at 200%]]
    testWidgets('the sheet keeps 48dp targets and clips nothing at 200%', (
      tester,
    ) async {
      await pumpCatalogue(tester, size: phone, textScale: 2);
      expect(tester.getSize(filters).height, greaterThanOrEqualTo(48));
      await openSheet(tester);
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byKey(const Key('show-results'))).height,
        greaterThanOrEqualTo(48),
      );
      final options = keyPrefix('facet-');
      for (var i = 0; i < options.evaluate().length; i++) {
        expect(tester.getSize(options.at(i)).height, greaterThanOrEqualTo(48));
      }
      final texts = find.descendant(of: sheet, matching: find.byType(Text));
      for (var i = 0; i < texts.evaluate().length; i++) {
        expect(
          tester.getRect(texts.at(i)).right,
          lessThanOrEqualTo(402.5),
          reason: tester.widget<Text>(texts.at(i)).data,
        );
      }
    });
  });
}
