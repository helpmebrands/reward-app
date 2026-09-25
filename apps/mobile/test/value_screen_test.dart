import 'dart:convert';
import 'dart:io';

import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reward/data/snapshot_store.dart';
import 'package:reward/logic/app_store.dart';
import 'package:reward/screens/value_screen.dart';
import 'package:reward/shell/width_class.dart';
import 'package:reward/theme/theme.dart';

/// The Value screen against what the PWA shows for the sample household on
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
    jsonDecode(File('test/fixtures/sample-value.json').readAsStringSync())
        as Map<String, dynamic>;

final DateTime now = DateTime(2026, 9, 16, 8);

Future<AppStore> pumpValue(
  WidgetTester tester, {
  AppData? data,
  WidthClass widthClass = WidthClass.compact,
  double textScale = 1,
  double height = 3000,
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
          child: ValueScreen(store: store),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return store;
}

Finder get chart => find.byKey(const Key('value-chart'));

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

void main() {
  // @lat: [[mobile-tests#Value#The totals, the bars, the ranks and the leaks are the PWA's]]
  testWidgets('shows the PWA totals, months, ranks and leaks', (tester) async {
    await pumpValue(tester);
    final f = expected();

    expect(find.text('Value'), findsOneWidget);
    expect(find.text('Last 9 months · 2 cards'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('value-captured')),
        matching: find.text(formatMoney(f['capturedTotalCents'] as int)),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('value-missed')),
        matching: find.text(formatMoney(f['missedTotalCents'] as int)),
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        '${formatMoney(f['missedTotalCents'] as int)} has expired unclaimed',
      ),
      findsOneWidget,
    );
    final leaks = (f['leaks'] as List).cast<Map<String, dynamic>>();
    expect(
      find.textContaining(
        'The biggest single leak is ${leaks.first['label']} at '
        '${formatMoney(leaks.first['missedCents'] as int)}.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Tallest bar = ${formatMoney(f['peakCents'] as int)}'),
      findsOneWidget,
    );

    final months = (f['months'] as List).cast<Map<String, dynamic>>();
    expect(
      keyed(tester, 'month-label-'),
      months.map((m) => m['label'] as String).toList(),
    );
    final painter =
        tester.widget<CustomPaint>(chart).painter as MonthlyBarsPainter;
    expect(painter.months.map((m) => m.label), months.map((m) => m['label']));
    expect(
      painter.months.map((m) => m.capturedCents),
      months.map((m) => m['capturedCents']),
    );
    expect(
      painter.months.map((m) => m.missedCents),
      months.map((m) => m['missedCents']),
    );
    expect(painter.peakCents, f['peakCents']);
    expect(painter.heightFor(f['peakCents'] as int, 100), 100);
    expect(painter.heightFor(0, 100), 0);

    final ranked = (f['ranked'] as List).cast<Map<String, dynamic>>();
    expect(
      keyed(tester, 'rank-label-'),
      ranked.map((r) => r['label'] as String).toList(),
    );
    expect(
      keyed(tester, 'rank-percent-'),
      ranked.map((r) => '${r['percent']}%').toList(),
    );

    expect(
      keyed(tester, 'leak-label-'),
      leaks.map((l) => l['label'] as String).toList(),
    );
    expect(
      keyed(tester, 'leak-when-'),
      leaks.map((l) => l['when'] as String).toList(),
    );
    expect(
      keyed(tester, 'leak-amount-'),
      leaks.map((l) => formatMoney(l['missedCents'] as int)).toList(),
    );
  });

  // @lat: [[mobile-tests#Value#The chart reads every month's figures aloud]]
  testWidgets('the chart semantics carry each month as text', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpValue(tester);
    final months = (expected()['months'] as List).cast<Map<String, dynamic>>();

    final label = tester.getSemantics(chart).label;
    expect(label, contains('Captured against missed, by month'));
    for (final m in months) {
      expect(
        label,
        contains(
          '${m['label']}: captured ${formatMoney(m['capturedCents'] as int)}, '
          'missed ${formatMoney(m['missedCents'] as int)}',
        ),
      );
    }
    handle.dispose();
  });

  // @lat: [[mobile-tests#Value#The months segment re-bins the chart]]
  testWidgets('choosing 6m or 12m changes the months shown', (tester) async {
    await pumpValue(tester);
    expect(keyed(tester, 'month-label-'), hasLength(9));

    await tester.tap(find.text('6m'));
    await tester.pumpAndSettle();
    expect(keyed(tester, 'month-label-'), hasLength(6));
    expect(find.text('Last 6 months · 2 cards'), findsOneWidget);

    await tester.tap(find.text('12m'));
    await tester.pumpAndSettle();
    expect(keyed(tester, 'month-label-'), hasLength(12));
  });

  // @lat: [[mobile-tests#Value#The chart grows with the column]]
  testWidgets('the chart fills the padded column at every width', (
    tester,
  ) async {
    for (final widthClass in WidthClass.values) {
      await pumpValue(tester, widthClass: widthClass);
      expect(
        tester.getSize(chart).width,
        widthClass.column - 2 * widthClass.padding,
        reason: widthClass.name,
      );
    }
  });

  // @lat: [[mobile-tests#Value#Value at 200% clips nothing]]
  testWidgets('at a 2.0 text scale nothing overflows or leaves the width', (
    tester,
  ) async {
    await pumpValue(tester, textScale: 2, height: 8000);
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

  // @lat: [[mobile-tests#Value#No cards shows the empty note]]
  testWidgets('with no cards it explains what will appear', (tester) async {
    await pumpValue(tester, data: emptyAppData());
    expect(
      find.textContaining('this screen shows what you captured'),
      findsOneWidget,
    );
    expect(find.text('Biggest leaks'), findsNothing);
    expect(find.text('Cards against their own fee'), findsNothing);
  });
}
