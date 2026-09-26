import 'dart:io';

import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reward/logic/sample_household.dart';
import 'package:reward/screens/welcome_hero.dart';
import 'package:reward/screens/welcome_heroes.dart';
import 'package:reward/screens/welcome_premium_mocks.dart';
import 'package:reward/screens/welcome_screen.dart';
import 'package:reward/theme/theme.dart';
import 'package:reward/widgets/credit_row.dart';
import 'package:reward/widgets/today_headline.dart';

/// The pictures on the welcome slides, built from the app's own widgets over
/// the sample household.

Future<void> pumpHero(
  WidgetTester tester,
  Widget hero, {
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = const Size(402, 874);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    MaterialApp(
      theme: nocturneTheme(brightness),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 368,
            height: 420,
            child: WelcomeHero(child: hero),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<BenefitInstance> sampleInstances() => [
  for (final i in currentInstances(sampleHousehold(), sampleToday))
    if (i.status != BenefitStatus.optedOut) i,
];

void main() {
  // @lat: [[mobile-tests#Welcome heroes#Slide one is Today's headline and rows]]
  testWidgets('slide one draws the headline total and credit rows in their '
      'tones from the sample household', (tester) async {
    for (final b in Brightness.values) {
      await pumpHero(tester, const UpcomingRewardsHero(), brightness: b);
      expect(tester.takeException(), isNull, reason: '$b');

      final claimable = totalsFor(sampleInstances(), 0).claimableCents;
      expect(find.byType(TodayHeadline), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(TodayHeadline),
          matching: find.text(moneyParts(claimable).digits),
        ),
        findsOneWidget,
      );

      final rows = tester.widgetList<CreditRow>(find.byType(CreditRow));
      expect(rows.length, greaterThanOrEqualTo(3));
      expect(rows.map((r) => r.tone).toSet(), {
        RowTone.soon,
        RowTone.available,
        RowTone.locked,
      });
      final ids = sampleInstances().map((i) => i.benefit.id).toSet();
      for (final row in rows) {
        expect(ids, contains(row.instance.benefit.id));
      }
    }
  });

  // @lat: [[mobile-tests#Welcome heroes#The first slide carries it]]
  testWidgets('the first slide shows the Today hero in its panel', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: nocturneTheme(Brightness.dark),
        home: WelcomeScreen(onDone: () {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(WelcomeHero),
        matching: find.byType(UpcomingRewardsHero),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  // @lat: [[mobile-tests#Welcome heroes#Slide two is a real reminder]]
  testWidgets('slide two draws the first notice reminder over the row of its '
      'biggest credit', (tester) async {
    final reminder = buildSchedule(
      sampleHousehold(),
      defaultMemberPreferences.copyWith(enabled: true),
      sampleClock,
    ).reminders.firstWhere((r) => r.tone.name == 'notice');
    for (final b in Brightness.values) {
      await pumpHero(tester, const TimelyRemindersHero(), brightness: b);
      expect(tester.takeException(), isNull, reason: '$b');

      final notification = find.byKey(const Key('welcome-notification'));
      expect(
        find.descendant(of: notification, matching: find.text(reminder.title)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: notification, matching: find.text(reminder.body)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: notification, matching: find.text('HelpMe Reward')),
        findsOneWidget,
      );

      final row = find.byType(CreditRow);
      expect(row, findsOneWidget);
      expect(
        tester.widget<CreditRow>(row).instance.benefit.id,
        reminder.items.first.benefitId,
      );
      expect(
        tester.getRect(notification).bottom,
        lessThanOrEqualTo(tester.getRect(row).top),
      );
    }
  });

  // @lat: [[mobile-tests#Welcome heroes#The second slide carries it]]
  testWidgets('the second slide shows the reminder hero in its panel', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: nocturneTheme(Brightness.light),
        home: WelcomeScreen(onDone: () {}),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('welcome-next')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(WelcomeHero),
        matching: find.byType(TimelyRemindersHero),
      ),
      findsOneWidget,
    );
  });

  // @lat: [[mobile-tests#Welcome heroes#Slide three mocks the premium features]]
  testWidgets('slide three draws a bank-tracked row and three insights', (
    tester,
  ) async {
    for (final b in Brightness.values) {
      await pumpHero(tester, const PremiumFeaturesHero(), brightness: b);
      expect(tester.takeException(), isNull, reason: '$b');

      final tracked = find.byKey(const Key('premium-tracked-row'));
      expect(
        find.descendant(of: tracked, matching: find.byType(CreditRow)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: tracked,
          matching: find.textContaining('Tracked from your bank'),
        ),
        findsOneWidget,
      );
      for (final kind in ['earn', 'use', 'missed']) {
        expect(
          find.descendant(
            of: find.byKey(const Key('premium-insights')),
            matching: find.byKey(Key('premium-insight-$kind')),
          ),
          findsOneWidget,
          reason: kind,
        );
      }
    }
  });

  // @lat: [[mobile-tests#Welcome heroes#The premium mocks use only tokens]]
  test('the premium mocks name no literal colour', () {
    final source = File(
      'lib/screens/welcome_premium_mocks.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('Color(')));
    expect(source, isNot(contains('Colors.')));
    expect(source, contains('placeholder'));
  });

  // @lat: [[mobile-tests#Welcome heroes#The third slide carries it]]
  testWidgets('the third slide shows the premium hero in its panel', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: nocturneTheme(Brightness.dark),
        home: WelcomeScreen(onDone: () {}),
      ),
    );
    await tester.pumpAndSettle();
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byKey(const Key('welcome-next')));
      await tester.pumpAndSettle();
    }
    expect(
      find.descendant(
        of: find.byType(WelcomeHero),
        matching: find.byType(PremiumFeaturesHero),
      ),
      findsOneWidget,
    );
  });
}
