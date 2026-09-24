import 'dart:convert';
import 'dart:io';

import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reward/data/snapshot_store.dart';
import 'package:reward/logic/app_store.dart';
import 'package:reward/screens/today_screen.dart';
import 'package:reward/theme/theme.dart';
import 'package:reward/widgets/credit_row.dart';

/// The PWA's sample household, read from the frozen app, and what its Today
/// screen shows for 16 September 2026, dumped by
/// `apps/pwa/scripts/today-snapshot.ts`.
AppData sampleHousehold() => appDataFromJson(
  jsonDecode(File('../pwa/samples/sample-household.json').readAsStringSync())
      as Map<String, dynamic>,
);

Map<String, dynamic> expectedToday() =>
    jsonDecode(File('test/fixtures/sample-today.json').readAsStringSync())
        as Map<String, dynamic>;

Future<AppStore> pumpToday(WidgetTester tester, {AppData? data}) async {
  final store = AppStore(
    store: MemorySnapshotStore(data ?? sampleHousehold()),
    clock: () => DateTime(2026, 9, 16),
  );
  await store.load();
  // A tall viewport so every section is laid out and every row is found.
  tester.view.physicalSize = const Size(402, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: nocturneTheme(Brightness.dark),
      home: Scaffold(body: TodayScreen(store: store)),
    ),
  );
  await tester.pumpAndSettle();
  return store;
}

/// The PWA's fixture names each card's holder, which the app no longer
/// stores; the sample household's two cards are Jim's and Kathy's.
const holderOf = {'card-0001': 'Jim', 'card-0002': 'Kathy'};

List<Map<String, Object?>> renderedRows(WidgetTester tester) =>
    tester.widgetList<CreditRow>(find.byType(CreditRow)).map((row) {
      final i = row.instance;
      return {
        'name': i.benefit.name,
        'holder': holderOf[i.card.id],
        'tone': row.tone.name,
        'cents': i.status == BenefitStatus.captured
            ? i.claimedCents
            : i.remainingCents,
      };
    }).toList();

void main() {
  // @lat: [[mobile-tests#Today#The sample household renders the PWA's rows, order and tones]]
  testWidgets(
    'renders the same rows, order and tones as the PWA for the sample',
    (tester) async {
      await pumpToday(tester);
      final expected = expectedToday();
      final rows = [
        ...(expected['soon'] as List),
        ...(expected['locked'] as List),
        ...(expected['captured'] as List),
      ].cast<Map<String, dynamic>>();
      expect(renderedRows(tester), rows);
    },
  );

  // @lat: [[mobile-tests#Today#The headline counts only what is claimable]]
  testWidgets('headlines the claimable total and the nearest reset', (
    tester,
  ) async {
    await pumpToday(tester);
    final expected = expectedToday();
    final totals = expected['totals'] as Map<String, dynamic>;
    final digits = moneyParts(totals['claimableCents'] as int).digits;
    expect(
      tester.widget<Text>(find.byKey(const Key('today-amount'))).data,
      digits,
    );
    expect(
      find.textContaining('The nearest window shuts 30 September'),
      findsOneWidget,
    );
    expect(find.text('Use soon — resets 30 September'), findsOneWidget);
    expect(find.text('Locked behind enrolment'), findsOneWidget);
    expect(
      find.text(
        'Captured this period — ${formatMoney(totals['capturedCents'] as int)}',
      ),
      findsOneWidget,
    );
  });

  // @lat: [[mobile-tests#Today#The locked section says why]]
  testWidgets('the locked section names a spend threshold when one applies', (
    tester,
  ) async {
    final sample = sampleHousehold();
    final gated = Benefit(
      id: 'gated',
      cardId: sample.cards.first.id,
      name: 'Dell Bonus',
      category: BenefitCategory.shopping,
      valueCents: 100000,
      cadence: Cadence.annual,
      anchor: CycleAnchor.calendar,
      enrollmentRequired: false,
      spendThresholdCents: 500000,
      redemptionSteps: const [],
      lastCallOnly: false,
      active: true,
      createdAt: '2026-01-01T00:00:00.000Z',
      updatedAt: '2026-01-01T00:00:00.000Z',
    );
    await pumpToday(
      tester,
      data: sample.copyWith(benefits: [...sample.benefits, gated]),
    );
    expect(find.text('Locked behind enrolment and spend'), findsOneWidget);
    expect(find.textContaining('some a spend threshold'), findsOneWidget);
    expect(find.text('Dell Bonus'), findsOneWidget);
  });

  // @lat: [[mobile-tests#Today#Overlaps show the three largest]]
  testWidgets('shows the three largest overlaps with their combined value', (
    tester,
  ) async {
    await pumpToday(tester);
    final overlaps = (expectedToday()['overlaps'] as List)
        .cast<Map<String, dynamic>>();
    expect(overlaps, hasLength(3));
    for (final overlap in overlaps) {
      expect(
        find.text('${overlap['label']} × ${overlap['count']}'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          '${formatMoney(overlap['remainingCents'] as int)} unclaimed across',
        ),
        findsWidgets,
      );
    }
  });

  // @lat: [[mobile-tests#Today#A fresh install shows the first-run screen]]
  testWidgets('shows the first-run screen when there are no cards', (
    tester,
  ) async {
    final store = AppStore(
      store: MemorySnapshotStore(),
      clock: () => DateTime(2026, 9, 16),
    );
    await store.load();
    await tester.pumpWidget(
      MaterialApp(
        theme: nocturneTheme(Brightness.dark),
        home: Scaffold(body: TodayScreen(store: store)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Start with one card'), findsOneWidget);
    expect(find.byType(CreditRow), findsNothing);
  });
}
