import 'dart:convert';
import 'dart:io';

import 'package:domain/domain.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reward/data/snapshot_store.dart';
import 'package:reward/logic/app_store.dart';
import 'package:reward/screens/today_screen.dart';
import 'package:reward/shell/width_class.dart';
import 'package:reward/theme/theme.dart';
import 'package:reward/widgets/all_caught_up.dart';
import 'package:reward/widgets/value_bar.dart';

/// Today once nothing is claimable: the all-caught-up state, its locked
/// wording, and the Next up card, over the sample household cut down to the
/// two Uber Cash credits, both used on 16 September 2026.

const today = '2026-09-16';
const uberJim = 'ben-0003';
const uberKathy = 'ben-0015';
const ouraKathy = 'ben-0024'; // needs enrollment, not enrolled: locked

AppData sampleHousehold() => appDataFromJson(
  jsonDecode(
        File(
          '../../packages/domain/test/fixtures/sample-household.json',
        ).readAsStringSync(),
      )
      as Map<String, dynamic>,
);

Claim _used(String benefitId) => Claim(
  id: 'used-$benefitId',
  benefitId: benefitId,
  cycleKey: '2026-09-01',
  amountCents: 1500,
  claimedAt: '2026-09-10T12:00:00.000Z',
);

/// Both Uber Cash credits, used this month, plus [extra] benefits.
AppData household({List<String> extra = const [], bool used = true}) {
  final data = sampleHousehold();
  final keep = {uberJim, uberKathy, ...extra};
  return data.copyWith(
    benefits: data.benefits.where((b) => keep.contains(b.id)).toList(),
    claims: used ? [_used(uberJim), _used(uberKathy)] : const [],
  );
}

Future<AppStore> pumpToday(
  WidgetTester tester, {
  AppData? data,
  WidthClass widthClass = WidthClass.compact,
  double textScale = 1,
  bool load = true,
}) async {
  final store = AppStore(
    store: MemorySnapshotStore(data ?? household()),
    clock: () => DateTime(2026, 9, 16),
  );
  if (load) await store.load();
  tester.view.physicalSize = Size(widthClass.column, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    MaterialApp(
      theme: nocturneTheme(Brightness.dark),
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(widthClass.column, 2000),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: WidthClassScope(
            widthClass: widthClass,
            child: TodayScreen(store: store),
          ),
        ),
      ),
    ),
  );
  if (load) await tester.pumpAndSettle();
  return store;
}

final amount = find.byKey(const Key('today-amount'));

/// Every label in the semantics tree, in traversal order.
List<String> spokenOrder(WidgetTester tester) {
  final root = tester.getSemantics(find.byType(ListView));
  final labels = <String>[];
  void visit(SemanticsNode node) {
    if (node.label.isNotEmpty) labels.add(node.label);
    for (final child in node.debugListChildrenInOrder(
      DebugSemanticsDumpOrder.traversalOrder,
    )) {
      visit(child);
    }
  }

  visit(root);
  return labels;
}

void main() {
  // @lat: [[mobile-tests#Today all caught up#Every open credit used shows All caught up]]
  testWidgets('every open credit used: All caught up with Next up', (
    tester,
  ) async {
    await pumpToday(tester);
    expect(find.byType(AllCaughtUp), findsOneWidget);
    expect(find.text('All caught up'), findsOneWidget);
    expect(amount, findsNothing);
    expect(
      find.text('You’ve used all \$30 open this period across 2 cards.'),
      findsOneWidget,
    );
    expect(find.text('Next up: Uber Cash, \$15 × 2'), findsOneWidget);
    expect(find.text('Opens Oct 1, in 15 days'), findsOneWidget);
    expect(find.byType(ValueBar), findsOneWidget);
    expect(find.textContaining('Captured this period'), findsOneWidget);
  });

  // @lat: [[mobile-tests#Today all caught up#Locked credits change the wording]]
  testWidgets('with a credit still locked the heading says so', (tester) async {
    await pumpToday(tester, data: household(extra: [ouraKathy]));
    expect(find.byType(AllCaughtUp), findsOneWidget);
    expect(find.text('Everything you can use is used'), findsOneWidget);
    expect(find.text('All caught up'), findsNothing);
    expect(
      find.text('\$200 is still locked. Unlock it and it will show up here.'),
      findsOneWidget,
    );
    expect(find.textContaining('Locked behind enrollment'), findsOneWidget);
    expect(find.textContaining('Next up'), findsNothing);
    expect(amount, findsNothing);
  });

  // @lat: [[mobile-tests#Today all caught up#A claimable credit brings the number back]]
  testWidgets('undoing a claim brings the headline back at once', (
    tester,
  ) async {
    final store = await pumpToday(tester);
    expect(amount, findsNothing);
    await store.unclaim(uberJim, '2026-09-01');
    await tester.pump();
    expect(amount, findsOneWidget);
    expect(tester.widget<Text>(amount).data, '15');
    expect(find.text('All caught up'), findsNothing);
    expect(find.byType(AllCaughtUp), findsNothing);
  });

  // @lat: [[mobile-tests#Today all caught up#A muted unused credit is not done]]
  testWidgets('a muted, unused credit keeps the normal headline', (
    tester,
  ) async {
    final store = await pumpToday(tester, data: household(used: false));
    await store.toggleBenefitMute(uberJim);
    await store.toggleBenefitMute(uberKathy);
    await tester.pumpAndSettle();
    expect(store.instanceFor(uberJim)!.muted, isTrue);
    expect(amount, findsOneWidget);
    expect(find.text('All caught up'), findsNothing);
  });

  // @lat: [[mobile-tests#Today all caught up#No card and loading keep their screens]]
  testWidgets('no active card and loading keep their own screens', (
    tester,
  ) async {
    await pumpToday(tester, data: emptyAppData());
    expect(
      find.text('Add a card to start tracking its credits'),
      findsOneWidget,
    );
    expect(find.text('All caught up'), findsNothing);

    await pumpToday(tester, load: false);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('All caught up'), findsNothing);
  });

  // @lat: [[mobile-tests#Today all caught up#The screen reader hears the heading after Today]]
  testWidgets('reading order: Today, heading, line, Next up, value bar', (
    tester,
  ) async {
    for (final width in [WidthClass.compact, WidthClass.expanded]) {
      final handle = tester.ensureSemantics();
      final store = await pumpToday(tester, widthClass: width);
      final spoken = spokenOrder(tester);
      final order = [
        spoken.indexOf('Today'),
        spoken.indexOf('All caught up'),
        spoken.indexWhere((l) => l.startsWith('You’ve used all')),
        spoken.indexWhere((l) => l.startsWith('Next up')),
        spoken.indexOf(valueBarSentence(store.householdValue)),
      ];
      expect(order, everyElement(greaterThanOrEqualTo(0)), reason: '$width: $spoken');
      expect(order, [...order]..sort(), reason: '$width: $spoken');
      final heading = tester.getSemantics(find.text('All caught up'));
      expect(
        heading.getSemanticsData().flagsCollection.isHeader,
        isTrue,
        reason: '$width',
      );
      handle.dispose();
    }
  });

  // @lat: [[mobile-tests#Today all caught up#The state holds at every width and at 2x]]
  testWidgets('holds at every width and at 2x text with no overflow', (
    tester,
  ) async {
    for (final width in WidthClass.values) {
      for (final scale in [1.0, 2.0]) {
        await pumpToday(
          tester,
          data: household(extra: [ouraKathy]),
          widthClass: width,
          textScale: scale,
        );
        expect(tester.takeException(), isNull, reason: '$width @ $scale');
        await pumpToday(tester, widthClass: width, textScale: scale);
        expect(tester.takeException(), isNull, reason: '$width @ $scale');
        expect(find.text('All caught up'), findsOneWidget);
      }
    }
  });
}
