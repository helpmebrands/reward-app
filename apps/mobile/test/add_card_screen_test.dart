import 'dart:convert';
import 'dart:io';

import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reward/data/snapshot_store.dart';
import 'package:reward/logic/app_store.dart';
import 'package:reward/logic/ui_state.dart';
import 'package:reward/main.dart';
import 'package:reward/screens/add_card_screen.dart';
import 'package:reward/shell/router.dart';

/// Add a card: pick a product, say whose it is and when the cardmember year
/// turns over, with the form rules applied the way the PWA applies them.

AppData sampleHousehold() => appDataFromJson(
  jsonDecode(File('../pwa/samples/sample-household.json').readAsStringSync())
      as Map<String, dynamic>,
);

final DateTime now = DateTime(2026, 9, 16, 8);

class App {
  App(this.store, this.ui);
  final AppStore store;
  final UiState ui;
}

Future<App> pumpAdd(
  WidgetTester tester, {
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
  // A fresh app each time, not a reused state with an old router.
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    RewardApp(store: store, ui: ui, initialLocation: Paths.newCard),
  );
  await tester.pumpAndSettle();
  return App(store, ui);
}

Future<void> pickPlatinum(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('template-amex-platinum')));
  await tester.pumpAndSettle();
}

Finder get holder => find.byKey(const Key('field-holder'));
Finder get anniversary => find.byKey(const Key('field-anniversary'));
Finder get save => find.text('Add this card');

void main() {
  // @lat: [[mobile-tests#Add a card#A template becomes a card with its credits]]
  testWidgets('picking a template and filling the form creates the card', (
    tester,
  ) async {
    final app = await pumpAdd(tester);
    expect(find.text('Add a card'), findsOneWidget);
    expect(find.text('1 of 2'), findsOneWidget);
    final template = findTemplate('amex-platinum')!;
    expect(find.text(template.product), findsWidgets);
    expect(
      find.text(
        '${formatMoney(templateAnnualValueCents(template))} in credits',
      ),
      findsOneWidget,
    );

    await pickPlatinum(tester);
    expect(find.text('Card details'), findsOneWidget);
    expect(find.text('2 of 2'), findsOneWidget);
    expect(find.text('Fields marked * are required.'), findsOneWidget);

    await tester.enterText(holder, 'Kathy');
    await tester.enterText(anniversary, '2024-05-01');
    final before = app.store.data!.cards.length;
    await tester.tap(save);
    await tester.pumpAndSettle();

    final cards = app.store.data!.cards;
    expect(cards, hasLength(before + 1));
    final card = cards.last;
    expect(card.holder, 'Kathy');
    expect(card.anniversaryOn, '2024-05-01');
    expect(card.issuer, template.issuer);
    expect(card.product, template.product);
    final mine = app.store.data!.benefits.where((b) => b.cardId == card.id);
    final expected = benefitsFromTemplate(template, card.id, 'x', () => 'id');
    expect(mine.map((b) => b.name), expected.map((b) => b.name));
    expect(mine.map((b) => b.valueCents), expected.map((b) => b.valueCents));
    expect(
      mine.map((b) => b.enrollmentRequired),
      expected.map((b) => b.enrollmentRequired),
    );
    expect(
      app.ui.snackbar.current!.text,
      'Added with ${template.benefits.length} credits. Check the terms — '
      'issuers change them.',
    );
    expect(find.byType(AddCardScreen), findsNothing);
  });

  // @lat: [[mobile-tests#Add a card#An empty holder is named and focused on submit]]
  testWidgets(
    'submitting with an empty holder shows the error and focuses it',
    (tester) async {
      final app = await pumpAdd(tester);
      await pickPlatinum(tester);

      await tester.enterText(holder, '');
      await tester.pumpAndSettle();
      expect(find.text('Enter whose card this is.'), findsNothing);

      final before = app.store.data!.cards.length;
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(find.text('Enter whose card this is.'), findsOneWidget);
      expect(app.store.data!.cards, hasLength(before));
      final focused = FocusManager.instance.primaryFocus!;
      expect(
        find.ancestor(
          of: find.byWidget(focused.context!.widget),
          matching: holder,
        ),
        findsOneWidget,
      );

      await tester.enterText(holder, 'Kathy');
      await tester.pumpAndSettle();
      expect(find.text('Enter whose card this is.'), findsNothing);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(app.store.data!.cards, hasLength(before + 1));
    },
  );

  // @lat: [[mobile-tests#Add a card#Typing shows no error before blur]]
  testWidgets('clearing the holder shows no error until it is left', (
    tester,
  ) async {
    await pumpAdd(tester);
    await pickPlatinum(tester);

    await tester.tap(holder);
    await tester.enterText(holder, '');
    await tester.pumpAndSettle();
    expect(find.text('Enter whose card this is.'), findsNothing);

    await tester.tap(anniversary);
    await tester.pumpAndSettle();
    expect(find.text('Enter whose card this is.'), findsOneWidget);
  });

  // @lat: [[mobile-tests#Add a card#A bad date shows the domain's sentence]]
  testWidgets(
    'an invalid anniversary shows the domain message, Save stays on',
    (tester) async {
      await pumpAdd(tester);
      await pickPlatinum(tester);

      await tester.enterText(anniversary, '2026-13-40');
      await tester.tap(holder);
      await tester.pumpAndSettle();

      expect(
        find.text('Enter the date the cardmember year starts.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Add this card'),
            )
            .enabled,
        isTrue,
      );
    },
  );

  // @lat: [[mobile-tests#Add a card#Back with a draft asks first]]
  testWidgets('back with a draft asks; back with no changes leaves at once', (
    tester,
  ) async {
    await pumpAdd(tester);
    await pickPlatinum(tester);

    // No changes yet: back returns to the catalogue at once.
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Add a card'), findsOneWidget);
    expect(find.text('1 of 2'), findsOneWidget);

    await pickPlatinum(tester);
    await tester.enterText(holder, 'Someone new');
    await tester.pumpAndSettle();
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Discard this card?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Card details'), findsOneWidget);

    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byType(AddCardScreen), findsNothing);
    expect(
      find.text('Add a card from the catalogue', skipOffstage: false),
      findsOneWidget,
    );
  });

  // @lat: [[mobile-tests#Add a card#Short fields pair from expanded]]
  testWidgets('holder and anniversary share a row at 1280, stack at 402', (
    tester,
  ) async {
    await pumpAdd(tester);
    await pickPlatinum(tester);
    expect(
      tester.getTopLeft(anniversary).dy,
      greaterThan(tester.getBottomLeft(holder).dy - 1),
    );

    await pumpAdd(tester, size: const Size(1280, 800));
    await pickPlatinum(tester);
    expect(tester.getTopLeft(anniversary).dy, tester.getTopLeft(holder).dy);
    expect(
      tester.getTopLeft(anniversary).dx,
      greaterThan(tester.getBottomRight(holder).dx),
    );
    final button = find.widgetWithText(OutlinedButton, 'Add this card');
    expect(
      tester.getSize(button).width,
      greaterThan(tester.getSize(holder).width * 1.5),
    );
  });

  // @lat: [[mobile-tests#Add a card#The form at 200% clips nothing]]
  testWidgets('at a 2.0 text scale nothing overflows', (tester) async {
    await pumpAdd(tester, textScale: 2, size: const Size(402, 4000));
    await pickPlatinum(tester);
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

  // @lat: [[mobile-tests#Add a card#The blank template asks for issuer and card]]
  testWidgets('setting one up by hand asks for the issuer and the card', (
    tester,
  ) async {
    final app = await pumpAdd(tester);
    await tester.dragUntilVisible(
      find.text('Set one up by hand'),
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set one up by hand'));
    await tester.pumpAndSettle();

    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Enter who issues the card.'), findsOneWidget);
    expect(find.text('Enter the name of the card.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('field-issuer')), 'Chase');
    await tester.enterText(find.byKey(const Key('field-product')), 'Sapphire');
    await tester.enterText(holder, 'Kathy');
    await tester.tap(save);
    await tester.pumpAndSettle();

    final card = app.store.data!.cards.last;
    expect(card.issuer, 'Chase');
    expect(card.product, 'Sapphire');
    expect(app.store.data!.benefits.where((b) => b.cardId == card.id), isEmpty);
    expect(app.ui.snackbar.current!.text, 'Card added. Add its credits next.');
  });
}
