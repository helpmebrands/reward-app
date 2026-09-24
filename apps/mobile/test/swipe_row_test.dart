import 'package:domain/domain.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reward/data/snapshot_store.dart';
import 'package:reward/theme/theme.dart';
import 'package:reward/widgets/credit_row.dart';
import 'package:reward/widgets/swipe_row.dart';

/// The swipe row: right to log, left to silence, parked open rather than
/// fired, direction-locked so the list still scrolls, and every gesture
/// reachable as a semantics action.

const _stamp = '2026-01-01T00:00:00.000Z';

Benefit _benefit(String id, String name, int valueCents) => Benefit(
  id: id,
  cardId: 'jim',
  name: name,
  category: BenefitCategory.dining,
  valueCents: valueCents,
  cadence: Cadence.quarterly,
  anchor: CycleAnchor.calendar,
  enrollmentRequired: false,
  redemptionSteps: const [],
  muted: false,
  lastCallOnly: false,
  active: true,
  createdAt: _stamp,
  updatedAt: _stamp,
);

/// Twelve open credits so the list scrolls, and one captured credit.
AppData _household() => AppData(
  version: 1,
  cards: const [
    Card(
      id: 'jim',
      issuer: 'American Express',
      product: 'Platinum',
      network: CardNetwork.amex,
      kind: CardKind.personal,
      annualFeeCents: 89500,
      anniversaryOn: '2021-03-14',
      muted: false,
      archived: false,
      createdAt: _stamp,
      updatedAt: _stamp,
    ),
  ],
  benefits: [
    for (var i = 0; i < 12; i++) _benefit('b$i', 'Credit $i', 10000),
    _benefit('done', 'Captured credit', 1500),
  ],
  claims: const [
    Claim(
      id: 'c',
      benefitId: 'done',
      cycleKey: '2026-07-01',
      amountCents: 1500,
      claimedAt: '2026-09-10T12:00:00.000Z',
    ),
  ],
  settings: defaultSettings,
);

class Calls {
  final List<String> opened = [];
  final List<String> logged = [];
  final List<String> muted = [];
}

Future<Calls> pumpRows(WidgetTester tester, {double textScale = 1}) async {
  final calls = Calls();
  final instances = currentInstances(_household(), '2026-09-16');
  tester.view.physicalSize = const Size(402, 874);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    MaterialApp(
      theme: nocturneTheme(Brightness.dark),
      home: Scaffold(
        body: ListView(
          key: const Key('list'),
          padding: const EdgeInsets.all(20),
          children: [
            for (final instance in instances)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: CreditRow(
                  key: ValueKey('row-${instance.benefit.id}'),
                  instance: instance,
                  onOpen: () => calls.opened.add(instance.benefit.id),
                  onLogAll: () => calls.logged.add(instance.benefit.id),
                  onToggleMute: () => calls.muted.add(instance.benefit.id),
                ),
              ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return calls;
}

Finder row(String id) => find.byKey(ValueKey('row-$id'));

/// How far the row's content has slid from its resting place.
double slide(WidgetTester tester, String id) {
  final content = find.descendant(
    of: row(id),
    matching: find.byKey(const Key('swipe-content')),
  );
  return tester.getTopLeft(content).dx - tester.getTopLeft(row(id)).dx;
}

void main() {
  // @lat: [[mobile-tests#Swipe row#A drag right parks the row open on Log]]
  testWidgets('60 px right parks the row open; Log acts; a tap away closes', (
    tester,
  ) async {
    final calls = await pumpRows(tester);

    await tester.drag(row('b0'), const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(slide(tester, 'b0'), swipeActionWidth);
    expect(find.text('Log it').hitTestable(), findsOneWidget);
    expect(calls.logged, isEmpty, reason: 'parking must not fire');

    await tester.tap(find.text('Log it'));
    await tester.pumpAndSettle();
    expect(calls.logged, ['b0']);
    expect(slide(tester, 'b0'), 0);

    await tester.drag(row('b0'), const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(slide(tester, 'b0'), swipeActionWidth);
    await tester.tapAt(tester.getCenter(row('b3')));
    await tester.pumpAndSettle();
    expect(slide(tester, 'b0'), 0);
    expect(calls.logged, ['b0']);
  });

  // @lat: [[mobile-tests#Swipe row#A short drag springs back]]
  testWidgets('under 55% of the width springs back', (tester) async {
    final calls = await pumpRows(tester);

    await tester.drag(row('b0'), const Offset(40, 0));
    await tester.pumpAndSettle();
    expect(slide(tester, 'b0'), 0);
    expect(calls.logged, isEmpty);
  });

  // @lat: [[mobile-tests#Swipe row#A vertical drag scrolls the list]]
  testWidgets('a mostly vertical drag scrolls and never opens the row', (
    tester,
  ) async {
    await pumpRows(tester);
    final before = tester.getTopLeft(row('b0')).dy;

    await tester.drag(row('b0'), const Offset(6, -40));
    await tester.pumpAndSettle();

    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    expect(position.pixels, greaterThan(0));
    expect(tester.getTopLeft(row('b0')).dy, lessThan(before));
    expect(slide(tester, 'b0'), 0);
  });

  // @lat: [[mobile-tests#Swipe row#A flick commits before the distance]]
  testWidgets('a fast flick parks the row open without reaching 55%', (
    tester,
  ) async {
    await pumpRows(tester);

    await tester.fling(row('b0'), const Offset(30, 0), 1200);
    await tester.pumpAndSettle();

    expect(slide(tester, 'b0'), swipeActionWidth);
  });

  // @lat: [[mobile-tests#Swipe row#A drag left parks the row open on Silence]]
  testWidgets('60 px left parks on Silence, which mutes', (tester) async {
    final calls = await pumpRows(tester);

    await tester.drag(row('b1'), const Offset(-60, 0));
    await tester.pumpAndSettle();
    expect(slide(tester, 'b1'), -swipeActionWidth);
    expect(find.text('Silence').hitTestable(), findsOneWidget);

    await tester.tap(find.text('Silence'));
    await tester.pumpAndSettle();
    expect(calls.muted, ['b1']);
    expect(slide(tester, 'b1'), 0);
  });

  // @lat: [[mobile-tests#Swipe row#A captured row has nothing to log]]
  testWidgets('a captured row does not open to the right', (tester) async {
    final calls = await pumpRows(tester);
    await tester.scrollUntilVisible(row('done'), 200);
    await tester.pumpAndSettle();

    await tester.drag(row('done'), const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(slide(tester, 'done'), 0);
    expect(calls.logged, isEmpty);
  });

  // @lat: [[mobile-tests#Swipe row#Every gesture is a semantics action]]
  testWidgets('the row exposes Log the full credit and Silence as actions', (
    tester,
  ) async {
    final calls = await pumpRows(tester);

    final node = tester.getSemantics(row('b2'));
    final ids = node.getSemanticsData().customSemanticsActionIds!;
    final labels = {
      for (final id in ids) CustomSemanticsAction.getAction(id)!.label: id,
    };
    expect(labels.keys, containsAll(['Log the full credit', 'Silence']));

    final owner = node.owner!;
    owner.performAction(
      node.id,
      SemanticsAction.customAction,
      labels['Log the full credit'],
    );
    owner.performAction(
      node.id,
      SemanticsAction.customAction,
      labels['Silence'],
    );
    await tester.pump();

    expect(calls.logged, ['b2']);
    expect(calls.muted, ['b2']);
    expect(slide(tester, 'b2'), 0);
  });

  // @lat: [[mobile-tests#Swipe row#The bell silences by name]]
  testWidgets('the bell button silences the named credit', (tester) async {
    final calls = await pumpRows(tester);

    await tester.tap(find.bySemanticsLabel('Silence reminders for Credit 0'));
    await tester.pumpAndSettle();

    expect(calls.muted, ['b0']);
    expect(calls.opened, isEmpty);
  });

  // @lat: [[mobile-tests#Swipe row#Tap opens, at 200% too]]
  testWidgets('a tap opens the sheet and the row still swipes at 2.0', (
    tester,
  ) async {
    final calls = await pumpRows(tester, textScale: 2);

    await tester.tap(row('b0'));
    await tester.pumpAndSettle();
    expect(calls.opened, ['b0']);

    await tester.drag(row('b0'), const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(slide(tester, 'b0'), swipeActionWidth);
    expect(find.text('Log it').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
