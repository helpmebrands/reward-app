import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reward/data/snapshot_store.dart';
import 'package:reward/logic/app_store.dart';
import 'package:reward/logic/ui_state.dart';
import 'package:reward/main.dart';
import 'package:reward/screens/credits_screen.dart';
import 'package:reward/shell/width_class.dart';
import 'package:reward/theme/theme.dart';
import 'package:reward/widgets/credit_row.dart';

/// The Credits screen against what the PWA shows for the sample household on
/// 16 September 2026, dumped once by the retired PWA (#174) and pinned.

/// The PWA's sample household, its two Platinums labelled with the names
/// the PWA shows for them, so the PWA's fixtures still apply.
AppData sampleHousehold() {
  final data = appDataFromJson(
    jsonDecode(
          File(
            '../../packages/domain/test/fixtures/sample-household.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>,
  );
  const labels = {
    'card-0001': 'American Express Platinum — Jim',
    'card-0002': 'American Express Platinum — Kathy',
  };
  return data.copyWith(
    cards: [for (final c in data.cards) c.copyWith(label: labels[c.id])],
  );
}

Map<String, dynamic> expected() =>
    jsonDecode(File('test/fixtures/sample-credits.json').readAsStringSync())
        as Map<String, dynamic>;

final DateTime now = DateTime(2026, 9, 16, 8);

Future<AppStore> pumpCredits(
  WidgetTester tester, {
  AppData? data,
  WidthClass widthClass = WidthClass.compact,
  double textScale = 1,
  double height = 9000,
}) async {
  final store = AppStore(
    store: MemorySnapshotStore(data ?? sampleHousehold()),
    clock: () => now,
  );
  await store.load();
  tester.view.physicalSize = Size(widthClass.column, height);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    MaterialApp(
      theme: nocturneTheme(Brightness.dark),
      home: Scaffold(
        body: WidthClassScope(
          widthClass: widthClass,
          child: CreditsScreen(store: store),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return store;
}

/// The PWA's fixture names each card's holder, which the app no longer
/// stores; the sample household's two cards are Jim's and Kathy's.
const holderOf = {'card-0001': 'Jim', 'card-0002': 'Kathy'};

/// The rows on screen, in order, the way the fixture spells them.
List<String> rows(WidgetTester tester) => tester
    .widgetList<CreditRow>(find.byType(CreditRow, skipOffstage: false))
    .map((r) {
      final i = r.instance;
      return '${i.benefit.name} · ${holderOf[i.card.id]} · ${i.cycle.label}';
    })
    .toList();

List<String> keyed(WidgetTester tester, String prefix) => tester
    .widgetList<Text>(
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            w.key is ValueKey<String> &&
            (w.key as ValueKey<String>).value.startsWith(prefix),
        skipOffstage: false,
      ),
    )
    .map((t) => t.data!)
    .toList();

List<String> groupLabels(WidgetTester tester) => keyed(tester, 'group-label-');
List<String> groupFigures(WidgetTester tester) =>
    keyed(tester, 'group-figure-');

Future<void> choose(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).first);
  await tester.pumpAndSettle();
}

void main() {
  // @lat: [[mobile-tests#Credits#The header carries the counts and the four totals]]
  testWidgets('shows the open, locked and missed counts and four totals', (
    tester,
  ) async {
    await pumpCredits(tester);
    final header = expected()['header'] as Map<String, dynamic>;
    final totals = expected()['totals'] as Map<String, dynamic>;

    expect(find.text('All credits'), findsOneWidget);
    expect(
      find.text(
        '${header['open']} open · ${header['locked']} locked · '
        '${header['missed']} missed',
      ),
      findsOneWidget,
    );
    for (final (label, key) in [
      ('Claimable', 'claimableCents'),
      ('Locked', 'lockedCents'),
      ('Captured', 'capturedCents'),
      ('Missed', 'missedCents'),
    ]) {
      expect(find.byKey(Key('total-$label')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(Key('total-$label')),
          matching: find.text(formatMoney(totals[key] as int)),
        ),
        findsOneWidget,
      );
    }
  });

  // @lat: [[mobile-tests#Credits#Each filter shows the PWA's rows]]
  testWidgets('each filter shows exactly the rows the PWA shows', (
    tester,
  ) async {
    await pumpCredits(tester);
    final filters = expected()['filters'] as Map<String, dynamic>;
    const labels = {
      'all': 'All',
      'use_soon': 'Use soon',
      'open': 'Open',
      'locked': 'Locked',
      'captured': 'Captured',
      'missed': 'Missed',
    };

    expect(rows(tester), (filters['all'] as List).cast<String>());
    expect(rows(tester), hasLength(72));
    for (final entry in labels.entries) {
      await choose(tester, entry.value);
      expect(
        rows(tester),
        (filters[entry.key] as List).cast<String>(),
        reason: entry.value,
      );
    }
  });

  // @lat: [[mobile-tests#Credits#Groupings produce the PWA's labels in order]]
  testWidgets('Card, Cycle and Status group the way the PWA does', (
    tester,
  ) async {
    await pumpCredits(tester);
    final groups = expected()['groups'] as Map<String, dynamic>;
    List<String> labelsOf(String grouping) => (groups[grouping] as List)
        .map((g) => (g as Map<String, dynamic>)['label'] as String)
        .toList();
    List<String> figuresOf(String grouping) => (groups[grouping] as List)
        .map((g) => (g as Map<String, dynamic>)['figure'] as String)
        .toList();

    expect(groupLabels(tester), labelsOf('card'));
    expect(groupFigures(tester), figuresOf('card'));
    await choose(tester, 'Cycle');
    expect(groupLabels(tester), labelsOf('cycle'));
    expect(groupFigures(tester), figuresOf('cycle'));
    await choose(tester, 'Status');
    expect(groupLabels(tester), labelsOf('status'));
    expect(groupFigures(tester), figuresOf('status'));
  });

  // @lat: [[mobile-tests#Credits#A group figure follows the filter and never mixes]]
  testWidgets('Missed sums remaining, Captured sums claimed, never both', (
    tester,
  ) async {
    await pumpCredits(tester);
    final groups = expected()['groups'] as Map<String, dynamic>;
    List<String> figuresOf(String grouping) => (groups[grouping] as List)
        .map((g) => (g as Map<String, dynamic>)['figure'] as String)
        .toList();

    await choose(tester, 'Missed');
    expect(groupFigures(tester), figuresOf('missedByCard'));
    expect(groupFigures(tester).first, '\$653.60 missed');
    await choose(tester, 'Captured');
    expect(groupFigures(tester), figuresOf('capturedByCard'));
    expect(groupFigures(tester).first, '\$741 captured');
    for (final figure in groupFigures(tester)) {
      expect(figure.contains('missed') && figure.contains('captured'), isFalse);
    }
  });

  // @lat: [[mobile-tests#Credits#An empty filter says so]]
  testWidgets('a filter with no rows says nothing matches', (tester) async {
    final data = sampleHousehold();
    // Only Jim's locked Equinox credit: nothing captured, nothing missed.
    final locked = data.copyWith(
      benefits: data.benefits.where((b) => b.id == 'ben-0013').toList(),
      claims: const [],
    );
    await pumpCredits(tester, data: locked);

    await choose(tester, 'Captured');
    expect(find.text('Nothing matches that filter.'), findsOneWidget);
    expect(find.byType(CreditRow), findsNothing);
  });

  // @lat: [[mobile-tests#Credits#Rows swipe and open the sheet in place]]
  testWidgets('a row opens the sheet and a claim updates it in place', (
    tester,
  ) async {
    final store = AppStore(
      store: MemorySnapshotStore(sampleHousehold()),
      clock: () => now,
    );
    await store.load();
    final ui = UiState();
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(RewardApp(store: store, ui: ui));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Credits'));
    await tester.pumpAndSettle();

    expect(find.text('All credits'), findsOneWidget);
    final resy = find.byKey(
      const ValueKey('row-ben-0018-2026-07-01'),
      skipOffstage: false,
    );
    await tester.ensureVisible(resy);
    await tester.pumpAndSettle();
    expect(tester.widget<CreditRow>(resy).tone, RowTone.soon);

    // Swipes while open: left parks on Silence and Opt out, a tap away closes it.
    await tester.drag(resy, const Offset(-120, 0));
    await tester.pumpAndSettle();
    expect(find.text('Silence').hitTestable(), findsOneWidget);
    // Just below the row, in the gap before the next one.
    await tester.tapAt(Offset(200, tester.getRect(resy).bottom + 2));
    await tester.pumpAndSettle();
    expect(find.text('Silence').hitTestable(), findsNothing);

    await tester.tap(resy);
    await tester.pumpAndSettle();
    expect(ui.openBenefitId, 'ben-0018');
    await tester.tap(find.text('Mark the full \$100 used'));
    await tester.pumpAndSettle();

    expect(tester.widget<CreditRow>(resy).tone, RowTone.captured);
  });

  // @lat: [[mobile-tests#Credits#The totals re-flow with the width]]
  testWidgets('the totals sit two by two at compact and four across at 1280', (
    tester,
  ) async {
    await pumpCredits(tester);
    Rect total(String label) => tester.getRect(find.byKey(Key('total-$label')));
    expect(total('Locked').top, total('Claimable').top);
    expect(total('Captured').top, greaterThan(total('Claimable').bottom - 1));

    await pumpCredits(tester, widthClass: WidthClass.expanded);
    expect(total('Locked').top, total('Claimable').top);
    expect(total('Captured').top, total('Claimable').top);
    expect(total('Missed').top, total('Claimable').top);
    expect(total('Missed').right, lessThanOrEqualTo(720 - 28));
  });

  // @lat: [[mobile-tests#Credits#Opted out is its own yearly figure]]
  testWidgets('an Opted out figure appears per year once a credit is out', (
    tester,
  ) async {
    final store = await pumpCredits(tester);
    final tile = find.byKey(const Key('total-Opted out'));
    expect(tile, findsNothing, reason: 'hidden while zero');

    final oura = store.data!.benefits.firstWhere((b) => b.id == 'ben-0012');
    final claimable = store.totals.claimableCents;
    await store.optOutBenefit(oura.id);
    await tester.pumpAndSettle();
    final yearly = formatMoney(annualValueCents(oura));
    expect(tile, findsOneWidget);
    expect(
      find.descendant(of: tile, matching: find.text('$yearly a year')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Opted out, $yearly a year'), findsOneWidget);
    expect(store.totals.claimableCents, lessThan(claimable));
  });

  // @lat: [[mobile-tests#Credits#Five totals hold at compact and expanded]]
  testWidgets('the five totals wrap at compact and sit in one row wide', (
    tester,
  ) async {
    final household = sampleHousehold();
    final data = household.copyWith(
      benefits: [
        for (final b in household.benefits)
          b.id == 'ben-0012'
              ? b.copyWith(optedOutAt: '2026-05-01T09:00:00.000Z')
              : b,
      ],
    );
    Rect total(String label) => tester.getRect(find.byKey(Key('total-$label')));
    const labels = ['Claimable', 'Locked', 'Captured', 'Missed', 'Opted out'];

    await pumpCredits(tester, data: data);
    for (final label in labels) {
      expect(total(label).right, lessThanOrEqualTo(WidthClass.compact.column));
    }
    expect(total('Opted out').top, greaterThan(total('Missed').top));

    await pumpCredits(tester, data: data, widthClass: WidthClass.expanded);
    for (final label in labels) {
      expect(total(label).top, total('Claimable').top, reason: label);
      expect(total(label).right, lessThanOrEqualTo(720 - 28));
    }
    expect(tester.takeException(), isNull);
  });

  // @lat: [[mobile-tests#Credits#Segments carry labels and a selected state]]
  testWidgets('the filters and groupings are labelled and show selection', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpCredits(tester);

    SemanticsNode node(String text) => tester.getSemantics(find.text(text));
    expect(
      node('All').getSemanticsData().flagsCollection.isSelected,
      Tristate.isTrue,
    );
    expect(
      node('Missed').getSemanticsData().flagsCollection.isSelected,
      Tristate.isFalse,
    );
    expect(
      node('Card').getSemanticsData().flagsCollection.isSelected,
      Tristate.isTrue,
    );
    expect(
      node('Cycle').getSemanticsData().flagsCollection.isSelected,
      Tristate.isFalse,
    );
    expect(find.bySemanticsLabel('Filter by status'), findsOneWidget);
    expect(find.bySemanticsLabel('Group credits by'), findsOneWidget);

    await choose(tester, 'Missed');
    expect(
      node('Missed').getSemanticsData().flagsCollection.isSelected,
      Tristate.isTrue,
    );
    expect(
      node('All').getSemanticsData().flagsCollection.isSelected,
      Tristate.isFalse,
    );
    handle.dispose();
  });

  // @lat: [[mobile-tests#Credits#Credits at 200% clips nothing]]
  testWidgets('at a 2.0 text scale nothing overflows or leaves the width', (
    tester,
  ) async {
    await pumpCredits(tester, textScale: 2, height: 20000);
    expect(tester.takeException(), isNull);
    final texts = find.byType(Text, skipOffstage: false);
    for (var i = 0; i < texts.evaluate().length; i++) {
      expect(
        tester.getRect(texts.at(i)).right,
        lessThanOrEqualTo(402.5),
        reason: tester.widget<Text>(texts.at(i)).data,
      );
    }
  });
}
