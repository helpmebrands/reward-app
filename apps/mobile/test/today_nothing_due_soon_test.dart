import 'dart:convert';
import 'dart:io';

import 'package:domain/domain.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:reward/data/snapshot_store.dart';
import 'package:reward/logic/app_store.dart';
import 'package:reward/logic/ui_state.dart';
import 'package:reward/main.dart';
import 'package:reward/screens/credits_screen.dart';

/// Today with money open but nothing closing within 30 days: the quiet note
/// where the Use soon section would be.

const resyKathy = 'ben-0018'; // $100 a quarter, enrolled
const uberJim = 'ben-0003';

AppData sampleHousehold() => appDataFromJson(
  jsonDecode(
        File(
          '../../packages/domain/test/fixtures/sample-household.json',
        ).readAsStringSync(),
      )
      as Map<String, dynamic>,
);

AppData only(List<String> ids, {List<Claim> claims = const []}) {
  final data = sampleHousehold();
  return data.copyWith(
    benefits: data.benefits.where((b) => ids.contains(b.id)).toList(),
    claims: claims,
  );
}

/// The whole app at Today on [on].
Future<AppStore> pumpApp(
  WidgetTester tester,
  AppData data, {
  DateTime? on,
  double textScale = 1,
}) async {
  final store = AppStore(
    store: MemorySnapshotStore(data),
    clock: () => on ?? DateTime(2026, 10, 2, 10),
  );
  await store.load();
  tester.view.physicalSize = const Size(402, 874);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(RewardApp(store: store, ui: UiState()));
  await tester.pumpAndSettle();
  return store;
}

const title = 'Nothing closes in the next 30 days';
final note = find.byKey(const Key('today-nothing-due-soon'));
final link = find.text('See open credits on Credits');

void main() {
  // @lat: [[mobile-tests#Today nothing due soon#Open money with nothing due soon shows the note]]
  testWidgets('an open Resy credit ending Dec 31 is named in the note', (
    tester,
  ) async {
    await pumpApp(tester, only([resyKathy]));
    expect(find.text(title), findsOneWidget);
    expect(
      find.text('Resy Dining Credit is next, \$100 by Dec 31.'),
      findsOneWidget,
    );
    expect(link, findsOneWidget);
    expect(find.textContaining('Use soon'), findsNothing);
  });

  // @lat: [[mobile-tests#Today nothing due soon#The link opens Credits]]
  testWidgets('tapping the link opens Credits', (tester) async {
    await pumpApp(tester, only([resyKathy]));
    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(find.byType(CreditsScreen), findsOneWidget);
  });

  // @lat: [[mobile-tests#Today nothing due soon#Use soon rows or nothing claimable hide it]]
  testWidgets('no note beside a use-soon row, nor with nothing claimable', (
    tester,
  ) async {
    await pumpApp(tester, only([resyKathy, uberJim]));
    expect(find.textContaining('Use soon'), findsOneWidget);
    expect(find.text(title), findsNothing);

    await pumpApp(
      tester,
      only(
        [uberJim],
        claims: const [
          Claim(
            id: 'c1',
            benefitId: uberJim,
            cycleKey: '2026-10-01',
            amountCents: 1500,
            claimedAt: '2026-10-01T12:00:00.000Z',
          ),
        ],
      ),
    );
    expect(find.text('All caught up'), findsOneWidget);
    expect(find.text(title), findsNothing);
  });

  // @lat: [[mobile-tests#Today nothing due soon#The note is a 48 target and holds at 2x]]
  testWidgets('the note and its link are 48 high and hold at 2x', (
    tester,
  ) async {
    for (final scale in [1.0, 2.0]) {
      await pumpApp(tester, only([resyKathy]), textScale: scale);
      expect(tester.takeException(), isNull, reason: '$scale');
      await tester.ensureVisible(link);
      await tester.pumpAndSettle();
      expect(tester.getSize(note).height, greaterThanOrEqualTo(48));
      final button = find.ancestor(of: link, matching: find.byType(TextButton));
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
      expect(tester.getRect(note).right, lessThanOrEqualTo(402));
    }
  });
}
