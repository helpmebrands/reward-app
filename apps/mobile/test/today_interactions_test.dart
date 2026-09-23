import 'dart:convert';
import 'dart:io';

import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reward/data/snapshot_store.dart';
import 'package:reward/logic/app_store.dart';
import 'package:reward/logic/ui_state.dart';
import 'package:reward/main.dart';
import 'package:reward/widgets/credit_row.dart';
import 'package:reward/widgets/holder_filter.dart';
import 'package:reward/widgets/nudge_preview.dart';

/// Today as the user touches it: rows open the sheet, the household filter
/// narrows the screen, overlap cards open the compare sheet, and "Preview
/// nudge" shows the next reminder. On the PWA's sample household, dated
/// 16 September 2026.

AppData sampleHousehold() => appDataFromJson(
  jsonDecode(File('../pwa/samples/sample-household.json').readAsStringSync())
      as Map<String, dynamic>,
);

final DateTime now = DateTime(2026, 9, 16, 8);
const IsoDate today = '2026-09-16';

class App {
  App(this.store, this.ui);
  final AppStore store;
  final UiState ui;
}

Future<App> pumpApp(WidgetTester tester, {AppData? data}) async {
  final store = AppStore(
    store: MemorySnapshotStore(data ?? sampleHousehold()),
    clock: () => now,
  );
  await store.load();
  final ui = UiState();
  tester.view.physicalSize = const Size(402, 874);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(RewardApp(store: store, ui: ui));
  await tester.pumpAndSettle();
  return App(store, ui);
}

Finder row(String benefitId) =>
    find.byKey(ValueKey('row-$benefitId'), skipOffstage: false);

Finder get creditSheet => find.byKey(const Key('credit-sheet'));

Finder get compareSheet => find.byKey(const Key('compare-sheet'));

String headline(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('today-amount'))).data!;

String benefitId(AppData data, String name, String cardId) =>
    data.benefits.firstWhere((b) => b.name == name && b.cardId == cardId).id;

void main() {
  // @lat: [[mobile-tests#Today interactions#A row opens the sheet and logging moves it to captured]]
  testWidgets('tapping a use-soon row opens its sheet; logging moves the row', (
    tester,
  ) async {
    final app = await pumpApp(tester);
    final resy = benefitId(app.store.data!, 'Resy Dining Credit', 'card-0002');
    expect(headline(tester), moneyParts(189890).digits);
    expect(tester.widget<CreditRow>(row(resy)).tone, RowTone.soon);

    await tester.tap(row(resy));
    await tester.pumpAndSettle();
    expect(app.ui.openBenefitId, resy);
    expect(creditSheet, findsOneWidget);

    await tester.tap(find.text('Mark the full \$100 used'));
    await tester.pumpAndSettle();

    expect(creditSheet, findsNothing);
    expect(headline(tester), moneyParts(179890).digits);
    expect(tester.widget<CreditRow>(row(resy)).tone, RowTone.captured);
    expect(find.text('Logged \$100 on Resy Dining Credit.'), findsOneWidget);
  });

  // @lat: [[mobile-tests#Today interactions#Swiping a row logs it with an undo]]
  testWidgets('swiping a row right and tapping Log it logs with an Undo', (
    tester,
  ) async {
    final app = await pumpApp(tester);
    final resy = benefitId(app.store.data!, 'Resy Dining Credit', 'card-0002');

    await tester.drag(row(resy), const Offset(60, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log it'));
    await tester.pumpAndSettle();

    expect(headline(tester), moneyParts(179890).digits);
    await tester.tap(find.bySemanticsLabel('Undo logging Resy Dining Credit'));
    await tester.pumpAndSettle();
    expect(headline(tester), moneyParts(189890).digits);
  });

  // @lat: [[mobile-tests#Today interactions#The household filter narrows the screen]]
  testWidgets('choosing a holder hides the other rows and totals', (
    tester,
  ) async {
    final app = await pumpApp(tester);
    expect(find.text('Everyone in the household'), findsOneWidget);

    await tester.tap(find.byType(HolderFilter));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jim').last);
    await tester.pumpAndSettle();

    expect(app.store.data!.settings.holderFilter, 'Jim');
    final rows = tester.widgetList<CreditRow>(
      find.byType(CreditRow, skipOffstage: false),
    );
    expect(rows, isNotEmpty);
    expect(rows.every((r) => r.instance.card.holder == 'Jim'), isTrue);
    final jims = currentInstances(
      app.store.data!,
      today,
    ).where((i) => i.card.holder == 'Jim').toList();
    expect(
      headline(tester),
      moneyParts(totalsFor(jims, 0).claimableCents).digits,
    );
  });

  // @lat: [[mobile-tests#Today interactions#One holder has no filter]]
  testWidgets('with one holder the filter is absent', (tester) async {
    final data = sampleHousehold();
    final one = data.copyWith(
      cards: data.cards.where((c) => c.id == 'card-0001').toList(),
      benefits: data.benefits.where((b) => b.cardId == 'card-0001').toList(),
    );
    await pumpApp(tester, data: one);

    expect(find.byKey(const Key('holder-filter')), findsNothing);
    expect(find.text('Everyone in the household'), findsNothing);
  });

  // @lat: [[mobile-tests#Today interactions#An overlap card opens the compare sheet]]
  testWidgets('tapping an overlap card compares both sides', (tester) async {
    final app = await pumpApp(tester);

    await tester.ensureVisible(find.text('Hotel Credit (FHR / THC) × 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hotel Credit (FHR / THC) × 2'));
    await tester.pumpAndSettle();

    expect(app.ui.openOverlapLabel, 'Hotel Credit (FHR / THC)');
    expect(compareSheet, findsOneWidget);
    final inSheet = find.descendant(
      of: compareSheet,
      matching: find.text('Jim'),
    );
    expect(inSheet, findsOneWidget);
    expect(
      find.descendant(of: compareSheet, matching: find.text('Kathy')),
      findsOneWidget,
    );
    expect(
      find.textContaining('Both sides are untouched at \$300'),
      findsOneWidget,
    );
    expect(find.text('Log \$300 on Jim’s card'), findsOneWidget);
    expect(find.text('Log \$300 on Kathy’s card'), findsOneWidget);

    await tester.tap(find.text('Log \$300 on Jim’s card'));
    await tester.pumpAndSettle();
    expect(compareSheet, findsNothing);
    final hotel = benefitId(
      app.store.data!,
      'Hotel Credit (FHR / THC)',
      'card-0001',
    );
    expect(
      app.store.data!.claims
          .where((c) => c.benefitId == hotel)
          .last
          .amountCents,
      30000,
    );
  });

  // @lat: [[mobile-tests#Today interactions#A compare side opens that credit]]
  testWidgets('a side of the compare sheet opens that credit', (tester) async {
    final app = await pumpApp(tester);
    await tester.ensureVisible(find.text('Hotel Credit (FHR / THC) × 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hotel Credit (FHR / THC) × 2'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(of: compareSheet, matching: find.text('Kathy')),
    );
    await tester.pumpAndSettle();

    expect(app.ui.openOverlapLabel, isNull);
    expect(compareSheet, findsNothing);
    expect(
      app.ui.openBenefitId,
      benefitId(app.store.data!, 'Hotel Credit (FHR / THC)', 'card-0002'),
    );
    expect(creditSheet, findsOneWidget);
  });

  // @lat: [[mobile-tests#Today interactions#Preview nudge shows the stand-in when nothing is scheduled]]
  testWidgets('Preview nudge shows the stand-in with reminders off', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('Preview nudge'));
    await tester.pumpAndSettle();

    final sample = sampleReminder(189890, now);
    expect(sample.title, '\$1,898.90 on the line — one week left');
    expect(find.text(sample.title), findsOneWidget);
    expect(find.text(sample.body), findsOneWidget);

    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
    expect(find.text(sample.title), findsNothing);
  });

  // @lat: [[mobile-tests#Today interactions#Preview nudge shows the next scheduled reminder]]
  testWidgets('Preview nudge shows what buildSchedule produces', (
    tester,
  ) async {
    final data = sampleHousehold();
    final enabled = data.copyWith(
      settings: data.settings.copyWith(
        notifications: data.settings.notifications.copyWith(enabled: true),
      ),
    );
    final expected = buildSchedule(
      enabled,
      now,
    ).reminders.firstWhere((r) => r.fireAt > now.millisecondsSinceEpoch);
    final app = await pumpApp(tester, data: enabled);

    await tester.tap(find.text('Preview nudge'));
    await tester.pumpAndSettle();

    expect(app.ui.nudge?.id, expected.id);
    expect(find.text(expected.title), findsOneWidget);
    expect(find.text(expected.body), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Dismiss preview'));
    await tester.pumpAndSettle();
    expect(app.ui.nudge, isNull);
    expect(find.text(expected.title), findsNothing);
  });
}
