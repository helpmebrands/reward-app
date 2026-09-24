import 'dart:convert';
import 'dart:io';

import 'package:domain/domain.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:reward/data/snapshot_store.dart';
import 'package:reward/logic/app_store.dart';
import 'package:reward/logic/ui_state.dart';
import 'package:reward/main.dart';
import 'package:reward/screens/benefit_editor_screen.dart';
import 'package:reward/screens/card_editor_screen.dart';
import 'package:reward/screens/cards_screen.dart';
import 'package:reward/shell/router.dart';

/// The card editor and the benefit editor: live-writing forms on the Field
/// pattern, with the benefit's window shown from its cadence and anchor.

AppData sampleHousehold() => appDataFromJson(
  jsonDecode(File('../pwa/samples/sample-household.json').readAsStringSync())
      as Map<String, dynamic>,
);

final DateTime now = DateTime(2026, 9, 16, 8);
const jim = 'card-0001';
const uber = 'ben-0003';

class App {
  App(this.store, this.ui);
  final AppStore store;
  final UiState ui;
}

Future<App> pumpAt(
  WidgetTester tester,
  String location, {
  Size size = const Size(402, 874),
  double textScale = 1,
}) async {
  final store = AppStore(
    store: MemorySnapshotStore(sampleHousehold()),
    clock: () => now,
  );
  await store.load();
  final ui = UiState();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    RewardApp(store: store, ui: ui, initialLocation: location),
  );
  await tester.pumpAndSettle();
  return App(store, ui);
}

Card cardOf(App app, String id) =>
    app.store.data!.cards.firstWhere((c) => c.id == id);
Benefit benefitOf(App app, String id) =>
    app.store.data!.benefits.firstWhere((b) => b.id == id);

Future<void> type(WidgetTester tester, String key, String text) async {
  await tester.enterText(find.byKey(Key(key)), text);
  await tester.pumpAndSettle();
}

/// Scrolls [finder] into view and lets the list settle before a tap.
Future<void> show(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> blurTo(WidgetTester tester, String key) async {
  await show(tester, find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void main() {
  group('card editor', () {
    // @lat: [[mobile-tests#Editors#The card editor writes valid values and shows errors for the rest]]
    testWidgets('writes valid fields live and holds invalid ones back', (
      tester,
    ) async {
      final app = await pumpAt(tester, cardPath(jim));
      expect(find.text('American Express Platinum'), findsWidgets);
      expect(find.text('12 credits'), findsOneWidget);
      expect(find.text('Fields marked * are required.'), findsOneWidget);

      await type(tester, 'field-label', 'Jim’s Platinum');
      expect(cardOf(app, jim).label, 'Jim’s Platinum');

      await type(tester, 'field-fee', 'abc');
      expect(cardOf(app, jim).annualFeeCents, 89500);
      await blurTo(tester, 'field-label');
      expect(
        find.text('Enter the amount as a number, like 695.'),
        findsOneWidget,
      );
      await type(tester, 'field-fee', '695');
      expect(cardOf(app, jim).annualFeeCents, 69500);
      expect(
        find.text('Enter the amount as a number, like 695.'),
        findsNothing,
      );

      await type(tester, 'field-anniversary', '2026-02-30');
      await blurTo(tester, 'field-label');
      expect(
        find.text('Enter the date the cardmember year starts.'),
        findsOneWidget,
      );
      expect(cardOf(app, jim).anniversaryOn, isNot('2026-02-30'));

      // Blank, the label falls back to the product name, which Kathy's
      // Platinum already shows.
      await type(tester, 'field-label', '');
      await blurTo(tester, 'field-fee');
      expect(
        find.text(
          'Another card is already called American Express Platinum. '
          'Enter a different label.',
        ),
        findsOneWidget,
      );
      expect(cardOf(app, jim).label, 'Jim’s Platinum');
    });

    // @lat: [[mobile-tests#Editors#Mute, archive and network are on the card editor]]
    testWidgets('mute, archive and the network write the card', (tester) async {
      final app = await pumpAt(tester, cardPath(jim));

      await show(tester, find.bySemanticsLabel('Silence every credit'));
      await tester.tap(find.bySemanticsLabel('Silence every credit'));
      await tester.pumpAndSettle();
      expect(cardOf(app, jim).muted, isTrue);

      await show(tester, find.byKey(const Key('field-network')));
      await tester.tap(find.byKey(const Key('field-network')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Visa').last);
      await tester.pumpAndSettle();
      expect(cardOf(app, jim).network, CardNetwork.visa);

      await show(tester, find.bySemanticsLabel('Archive this card'));
      await tester.tap(find.bySemanticsLabel('Archive this card'));
      await tester.pumpAndSettle();
      expect(cardOf(app, jim).archived, isTrue);
    });

    // @lat: [[mobile-tests#Editors#The card kind is a choice on the card editor]]
    testWidgets('the Personal and Business chips write the kind', (
      tester,
    ) async {
      final app = await pumpAt(tester, cardPath(jim));
      expect(cardOf(app, jim).kind, CardKind.personal);

      await show(tester, find.text('Business'));
      await tester.tap(find.text('Business'));
      await tester.pumpAndSettle();
      expect(cardOf(app, jim).kind, CardKind.business);

      await tester.tap(find.text('Personal'));
      await tester.pumpAndSettle();
      expect(cardOf(app, jim).kind, CardKind.personal);
    });

    // @lat: [[mobile-tests#Editors#The credit list opens each editor and adds a credit]]
    testWidgets('lists the credits by name, opens one, and adds a new one', (
      tester,
    ) async {
      final app = await pumpAt(
        tester,
        cardPath(jim),
        size: const Size(402, 3000),
      );
      final names =
          app.store.data!.benefits
              .where((b) => b.cardId == jim)
              .map((b) => b.name)
              .toList()
            ..sort();
      final links = find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key as ValueKey<String>).value.startsWith('benefit-link-'),
        skipOffstage: false,
      );
      expect(links, findsNWidgets(names.length));
      for (final (i, name) in names.indexed) {
        expect(
          find.descendant(
            of: links.at(i),
            matching: find.text(name, skipOffstage: false),
          ),
          findsOneWidget,
        );
      }

      await show(tester, find.byKey(const ValueKey('benefit-link-$uber')));
      await tester.tap(find.byKey(const ValueKey('benefit-link-$uber')));
      await tester.pumpAndSettle();
      expect(find.byType(BenefitEditorScreen), findsOneWidget);
      expect(find.text('Uber Cash'), findsWidgets);

      final app2 = await pumpAt(
        tester,
        cardPath(jim),
        size: const Size(402, 3000),
      );
      final before = app2.store.data!.benefits.length;
      await show(tester, find.text('Add'));
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(app2.store.data!.benefits, hasLength(before + 1));
      final added = app2.store.data!.benefits.last;
      expect(added.name, 'New credit');
      expect(added.cardId, jim);
      expect(find.byType(BenefitEditorScreen), findsOneWidget);
    });

    // @lat: [[mobile-tests#Editors#Deleting a card from its editor confirms, cascades and returns]]
    testWidgets('delete confirms, cascades and returns to Cards', (
      tester,
    ) async {
      final app = await pumpAt(tester, cardPath(jim));

      await tester.tap(find.bySemanticsLabel('Delete this card'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('and everything logged against it?'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(app.store.data!.cards.map((c) => c.id), ['card-0002']);
      expect(app.store.data!.benefits.any((b) => b.cardId == jim), isFalse);
      expect(find.byType(CardsScreen), findsOneWidget);
      expect(app.ui.snackbar.current!.text, 'Card deleted.');
    });

    // @lat: [[mobile-tests#Editors#Back with an unsaved draft asks first]]
    testWidgets('back asks only while a field holds an unsaved value', (
      tester,
    ) async {
      await pumpAt(tester, cardPath(jim));

      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.byType(CardsScreen), findsOneWidget);

      await pumpAt(tester, cardPath(jim));
      await type(tester, 'field-fee', 'abc');
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('Leave without saving?'), findsOneWidget);
      await tester.tap(find.text('Stay'));
      await tester.pumpAndSettle();
      expect(find.byType(CardEditorScreen), findsOneWidget);

      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leave'));
      await tester.pumpAndSettle();
      expect(find.byType(CardsScreen), findsOneWidget);
    });

    // @lat: [[mobile-tests#Editors#An unknown id shows the not-found state]]
    testWidgets('an unknown card id shows Card not found', (tester) async {
      await pumpAt(tester, cardPath('nope'));
      expect(find.text('Card not found'), findsOneWidget);
      expect(find.text('That card is no longer here.'), findsOneWidget);

      await pumpAt(tester, benefitPath('nope'));
      expect(find.text('Credit not found'), findsOneWidget);
      expect(find.text('That credit is no longer here.'), findsOneWidget);
    });
  });

  group('benefit editor', () {
    // @lat: [[mobile-tests#Editors#The window follows the cadence and the anchor live]]
    testWidgets('changing the cadence and anchor updates the shown window', (
      tester,
    ) async {
      final app = await pumpAt(tester, benefitPath(uber));
      expect(find.text('Uber Cash'), findsWidgets);
      expect(find.text('Jim'), findsWidgets);
      expect(
        find.text('This period runs Sep 1 – Sep 30 (Sep 2026).'),
        findsOneWidget,
      );
      expect(
        find.text('Reminders at 23 · 7 · last day days out.'),
        findsOneWidget,
      );

      await show(tester, find.byKey(const Key('field-cadence')));
      await tester.tap(find.byKey(const Key('field-cadence')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quarterly').last);
      await tester.pumpAndSettle();
      expect(
        find.text('This period runs Jul 1 – Sep 30 (Q3 2026).'),
        findsOneWidget,
      );
      expect(benefitOf(app, uber).cadence, Cadence.quarterly);

      await show(tester, find.text('Card anniversary'));
      await tester.tap(find.text('Card anniversary'));
      await tester.pumpAndSettle();
      final card = cardOf(app, jim);
      final cycle = cycleFor(benefitOf(app, uber), card, '2026-09-16')!;
      expect(
        find.text(
          'This period runs ${formatDate(cycle.start, '2026-09-16')} – '
          '${formatDate(cycle.end, '2026-09-16')} (${cycle.label}).',
        ),
        findsOneWidget,
      );
      expect(benefitOf(app, uber).anchor, CycleAnchor.anniversary);
    });

    // @lat: [[mobile-tests#Editors#The benefit editor writes valid values and shows errors for the rest]]
    testWidgets('an invalid value shows the domain error and writes nothing', (
      tester,
    ) async {
      final app = await pumpAt(tester, benefitPath(uber));

      await type(tester, 'field-value', '0');
      await blurTo(tester, 'field-name');
      expect(find.text('Enter a value above zero.'), findsOneWidget);
      expect(benefitOf(app, uber).valueCents, 1500);

      await type(tester, 'field-value', '45');
      expect(benefitOf(app, uber).valueCents, 4500);
      expect(find.text('Enter a value above zero.'), findsNothing);

      await type(tester, 'field-name', '');
      await blurTo(tester, 'field-value');
      expect(find.text('Enter what the credit is called.'), findsOneWidget);
      expect(benefitOf(app, uber).name, 'Uber Cash');

      await type(tester, 'field-merchant', 'Lyft');
      expect(benefitOf(app, uber).merchant, 'Lyft');
    });

    // @lat: [[mobile-tests#Editors#Enrolment, tracking and the switches write the benefit]]
    testWidgets('the switches and the enrolment page write the benefit', (
      tester,
    ) async {
      final app = await pumpAt(tester, benefitPath(uber));

      await show(tester, find.bySemanticsLabel('Needs enrolment'));
      await tester.tap(find.bySemanticsLabel('Needs enrolment'));
      await tester.pumpAndSettle();
      expect(benefitOf(app, uber).enrollmentRequired, isTrue);
      expect(find.text('Not yet — the credit is locked.'), findsOneWidget);

      await show(tester, find.bySemanticsLabel('Enrolled'));
      await tester.tap(find.bySemanticsLabel('Enrolled'));
      await tester.pumpAndSettle();
      expect(benefitOf(app, uber).enrolledAt, isNotNull);

      await type(tester, 'field-url', 'not a url');
      await blurTo(tester, 'field-merchant');
      expect(
        find.text('Enter a full web address, starting with https://.'),
        findsOneWidget,
      );
      await type(tester, 'field-url', 'https://amex.example/enrol');
      expect(benefitOf(app, uber).enrollmentUrl, 'https://amex.example/enrol');

      await show(tester, find.bySemanticsLabel('Track this credit'));
      await tester.tap(find.bySemanticsLabel('Track this credit'));
      await tester.pumpAndSettle();
      expect(benefitOf(app, uber).active, isFalse);

      await show(tester, find.bySemanticsLabel('Last call only'));
      await tester.tap(find.bySemanticsLabel('Last call only'));
      await tester.pumpAndSettle();
      expect(benefitOf(app, uber).lastCallOnly, isTrue);
    });

    // @lat: [[mobile-tests#Editors#A rolling credit asks for its interval and hides the anchor]]
    testWidgets('choosing Rolling asks for the months and hides the anchor', (
      tester,
    ) async {
      final app = await pumpAt(tester, benefitPath(uber));
      expect(find.byKey(const Key('field-interval')), findsNothing);
      expect(find.text('The calendar'), findsOneWidget);

      await show(tester, find.byKey(const Key('field-cadence')));
      await tester.tap(find.byKey(const Key('field-cadence')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rolling').last);
      await tester.pumpAndSettle();
      expect(benefitOf(app, uber).cadence, Cadence.rolling);
      expect(find.text('The calendar'), findsNothing);
      expect(find.byKey(const Key('field-interval')), findsOneWidget);

      await blurTo(tester, 'field-interval');
      await blurTo(tester, 'field-merchant');
      expect(
        find.text('Enter how many months between claims.'),
        findsOneWidget,
      );
      expect(benefitOf(app, uber).intervalMonths, isNull);

      await type(tester, 'field-interval', '48');
      expect(benefitOf(app, uber).intervalMonths, 48);
      expect(find.text('Enter how many months between claims.'), findsNothing);

      await type(tester, 'field-interval', '');
      await blurTo(tester, 'field-merchant');
      expect(benefitOf(app, uber).intervalMonths, 48);
      expect(
        find.text('Enter how many months between claims.'),
        findsOneWidget,
      );
    });

    // @lat: [[mobile-tests#Editors#A spend threshold and its reached switch write the benefit]]
    testWidgets(
      'a spend threshold writes the benefit and reveals the reached switch',
      (tester) async {
        final app = await pumpAt(tester, benefitPath(uber));
        expect(find.bySemanticsLabel('Spend reached this year'), findsNothing);

        await type(tester, 'field-spend-threshold', 'abc');
        await blurTo(tester, 'field-merchant');
        expect(
          find.text('Enter the amount as a number, like 695.'),
          findsOneWidget,
        );
        expect(benefitOf(app, uber).spendThresholdCents, isNull);

        await type(tester, 'field-spend-threshold', '5000');
        expect(benefitOf(app, uber).spendThresholdCents, 500000);

        await show(tester, find.bySemanticsLabel('Spend reached this year'));
        await tester.tap(find.bySemanticsLabel('Spend reached this year'));
        await tester.pumpAndSettle();
        expect(benefitOf(app, uber).spendMetAt, isNotNull);

        await type(tester, 'field-spend-threshold', '');
        expect(benefitOf(app, uber).spendThresholdCents, isNull);
      },
    );

    // @lat: [[mobile-tests#Editors#An end date is optional and validated]]
    testWidgets('an end date is optional, validated, and written when real', (
      tester,
    ) async {
      final app = await pumpAt(tester, benefitPath(uber));
      expect(benefitOf(app, uber).endsOn, isNull);
      const sentence =
          'Enter the last day it can be used as a date, or leave it blank.';

      await type(tester, 'field-ends-on', '2026-13-40');
      await blurTo(tester, 'field-merchant');
      expect(find.text(sentence), findsOneWidget);
      expect(benefitOf(app, uber).endsOn, isNull);

      await type(tester, 'field-ends-on', '2026-12-31');
      expect(benefitOf(app, uber).endsOn, '2026-12-31');
      expect(find.text(sentence), findsNothing);

      await type(tester, 'field-ends-on', '');
      expect(benefitOf(app, uber).endsOn, isNull);
    });

    // @lat: [[mobile-tests#Editors#Deleting a benefit takes its claims and returns to the card]]
    testWidgets('delete removes the credit and its claims, back to the card', (
      tester,
    ) async {
      final app = await pumpAt(tester, benefitPath(uber));
      expect(app.store.data!.claims.any((c) => c.benefitId == uber), isTrue);

      await tester.tap(find.bySemanticsLabel('Delete this credit'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(app.store.data!.benefits.any((b) => b.id == uber), isFalse);
      expect(app.store.data!.claims.any((c) => c.benefitId == uber), isFalse);
      expect(find.byType(CardEditorScreen), findsOneWidget);
      expect(app.ui.snackbar.current!.text, 'Credit deleted.');
    });

    // @lat: [[mobile-tests#Editors#Editor fields pair from expanded and survive 200%]]
    testWidgets('fields pair at 1280 and nothing overflows at 2.0', (
      tester,
    ) async {
      await pumpAt(tester, benefitPath(uber), size: const Size(1280, 800));
      final name = tester.getRect(find.byKey(const Key('field-name')));
      final value = tester.getRect(find.byKey(const Key('field-value')));
      expect(value.top, name.top);
      expect(value.left, greaterThan(name.right));

      await pumpAt(
        tester,
        benefitPath(uber),
        size: const Size(402, 6000),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      final texts = find.byType(Text);
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
