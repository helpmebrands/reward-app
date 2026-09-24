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

/// Add a card: pick a product, label it when the household already holds
/// one, and say when the cardmember year turns over, with the form rules
/// applied the way the PWA applies them.

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

/// The template list; from medium up the filter panel scrolls beside it.
Finder get results => find.descendant(
  of: find.byKey(const Key('catalog-results')),
  matching: find.byType(Scrollable),
);

Finder get platinum => find.byKey(const Key('template-amex-platinum'));

/// The catalogue outgrows the screen, so scroll the Platinum into view first.
Future<void> showPlatinum(WidgetTester tester) async {
  await tester.scrollUntilVisible(platinum, 200, scrollable: results);
  await tester.ensureVisible(platinum);
  await tester.pumpAndSettle();
}

Future<void> pickPlatinum(WidgetTester tester) async {
  await showPlatinum(tester);
  await tester.tap(platinum);
  await tester.pumpAndSettle();
}

Finder get label => find.byKey(const Key('field-label'));
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
    await showPlatinum(tester);
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

    // The sample household holds two Platinums already.
    expect(
      tester.widget<TextField>(label).controller!.text,
      'American Express Platinum (1)',
    );
    await tester.enterText(anniversary, '2024-05-01');
    final before = app.store.data!.cards.length;
    await tester.tap(save);
    await tester.pumpAndSettle();

    final cards = app.store.data!.cards;
    expect(cards, hasLength(before + 1));
    final card = cards.last;
    expect(card.label, 'American Express Platinum (1)');
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

  const taken =
      'Another card is already called American Express Platinum. '
      'Enter a different label.';

  // @lat: [[mobile-tests#Add a card#A label another card shows is named and focused on submit]]
  testWidgets(
    'submitting a label another card already shows names it and focuses it',
    (tester) async {
      final app = await pumpAdd(tester);
      await pickPlatinum(tester);

      await tester.enterText(label, 'American Express Platinum');
      await tester.pumpAndSettle();
      expect(find.text(taken), findsNothing);

      final before = app.store.data!.cards.length;
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(find.text(taken), findsOneWidget);
      expect(app.store.data!.cards, hasLength(before));
      final focused = FocusManager.instance.primaryFocus!;
      expect(
        find.ancestor(
          of: find.byWidget(focused.context!.widget),
          matching: label,
        ),
        findsOneWidget,
      );

      await tester.enterText(label, 'Kathy’s Platinum');
      await tester.pumpAndSettle();
      expect(find.text(taken), findsNothing);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(app.store.data!.cards, hasLength(before + 1));
    },
  );

  // @lat: [[mobile-tests#Add a card#Typing shows no error before blur]]
  testWidgets('typing a taken label shows no error until it is left', (
    tester,
  ) async {
    await pumpAdd(tester);
    await pickPlatinum(tester);

    await tester.tap(label);
    await tester.enterText(label, 'American Express Platinum');
    await tester.pumpAndSettle();
    expect(find.text(taken), findsNothing);

    await tester.tap(anniversary);
    await tester.pumpAndSettle();
    expect(find.text(taken), findsOneWidget);
  });

  // @lat: [[mobile-tests#Add a card#A bad date shows the domain's sentence]]
  testWidgets(
    'an invalid anniversary shows the domain message, Save stays on',
    (tester) async {
      await pumpAdd(tester);
      await pickPlatinum(tester);

      await tester.enterText(anniversary, '2026-13-40');
      await tester.tap(label);
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
    await tester.enterText(label, 'Someone new');
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
  testWidgets('label and anniversary share a row at 1280, stack at 402', (
    tester,
  ) async {
    await pumpAdd(tester);
    await pickPlatinum(tester);
    expect(
      tester.getTopLeft(anniversary).dy,
      greaterThan(tester.getBottomLeft(label).dy - 1),
    );

    await pumpAdd(tester, size: const Size(1280, 800));
    await pickPlatinum(tester);
    expect(tester.getTopLeft(anniversary).dy, tester.getTopLeft(label).dy);
    expect(
      tester.getTopLeft(anniversary).dx,
      greaterThan(tester.getBottomRight(label).dx),
    );
    final button = find.widgetWithText(OutlinedButton, 'Add this card');
    expect(
      tester.getSize(button).width,
      greaterThan(tester.getSize(label).width * 1.5),
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

  // @lat: [[mobile-tests#Add a card#A business template lands as a business card]]
  testWidgets('a business template is business, and the chips can change it', (
    tester,
  ) async {
    final app = await pumpAdd(tester);
    final business = find.byKey(const Key('template-amex-business-platinum'));
    await tester.scrollUntilVisible(business, 200);
    await tester.ensureVisible(business);
    await tester.pumpAndSettle();
    await tester.tap(business);
    await tester.pumpAndSettle();

    await tester.enterText(anniversary, '2024-05-01');
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(app.store.data!.cards.last.kind, CardKind.business);
  });

  // @lat: [[mobile-tests#Add a card#The blank template asks for issuer and card]]
  testWidgets('adding a card manually asks for the issuer and the card', (
    tester,
  ) async {
    final app = await pumpAdd(tester);
    await tester.tap(find.byKey(const Key('add-manually-top')));
    await tester.pumpAndSettle();
    expect(find.text('Card details'), findsOneWidget);

    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Enter who issues the card.'), findsOneWidget);
    expect(find.text('Enter the name of the card.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('field-issuer')), 'Chase');
    await tester.enterText(find.byKey(const Key('field-product')), 'Sapphire');
    await tester.tap(save);
    await tester.pumpAndSettle();

    final card = app.store.data!.cards.last;
    expect(card.issuer, 'Chase');
    expect(card.product, 'Sapphire');
    expect(card.kind, CardKind.personal);
    expect(app.store.data!.benefits.where((b) => b.cardId == card.id), isEmpty);
    expect(app.ui.snackbar.current!.text, 'Card added. Add its credits next.');
  });

  // @lat: [[mobile-tests#Add a card#Manual entry sits at the top, labelled by width]]
  testWidgets('the top CTA is on screen at once, labelled by width', (
    tester,
  ) async {
    await pumpAdd(tester);
    final top = find.byKey(const Key('add-manually-top'));
    expect(
      find.descendant(of: top, matching: find.text('Add card')),
      findsOneWidget,
    );
    expect(tester.getRect(top).bottom, lessThanOrEqualTo(874));
    expect(tester.getSize(top).height, greaterThanOrEqualTo(48));

    await pumpAdd(tester, size: const Size(1280, 800));
    expect(
      find.descendant(of: top, matching: find.text('Add card manually')),
      findsOneWidget,
    );
    expect(tester.getRect(top).bottom, lessThanOrEqualTo(800));
  });

  // @lat: [[mobile-tests#Add a card#The end of the list offers manual entry]]
  testWidgets(
    '"Enter it manually" at the end of the list opens the blank form',
    (tester) async {
      final app = await pumpAdd(tester);
      final end = find.byKey(const Key('add-manually-end'));
      await tester.scrollUntilVisible(end, 300);
      await tester.pumpAndSettle();
      expect(find.text("Don't see your card?"), findsOneWidget);
      expect(find.text('Set one up by hand'), findsNothing);
      expect(tester.getSize(end).height, greaterThanOrEqualTo(48));
      await tester.tap(end);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('field-issuer')), findsOneWidget);
      expect(find.byKey(const Key('field-product')), findsOneWidget);

      await tester.enterText(find.byKey(const Key('field-issuer')), 'Chase');
      await tester.enterText(find.byKey(const Key('field-product')), 'Freedom');
        await tester.tap(save);
      await tester.pumpAndSettle();
      final card = app.store.data!.cards.last;
      expect(card.product, 'Freedom');
      expect(
        app.ui.snackbar.current!.text,
        'Card added. Add its credits next.',
      );
    },
  );

  // @lat: [[mobile-tests#Add a card#The catalogue is ordered by annual value]]
  testWidgets('the first tile is the template worth the most a year', (
    tester,
  ) async {
    await pumpAdd(tester);
    final best = sortByValue(
      filterTemplates(cardTemplates, const CatalogFilter()),
    ).first;
    final tiles = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('template-'),
    );
    expect(tester.widget(tiles.first).key, ValueKey('template-${best.id}'));
    for (final t in cardTemplates.where((t) => t.id != 'blank')) {
      expect(
        templateAnnualValueCents(best),
        greaterThanOrEqualTo(templateAnnualValueCents(t)),
      );
    }
  });

  // @lat: [[mobile-tests#Add a card#The catalogue at 200% clips nothing]]
  testWidgets('the catalogue at a 2.0 text scale clips nothing', (
    tester,
  ) async {
    await pumpAdd(tester, textScale: 2, size: const Size(402, 874));
    expect(tester.takeException(), isNull);
    final texts = find.byType(Text);
    for (var i = 0; i < texts.evaluate().length; i++) {
      expect(
        tester.getRect(texts.at(i)).right,
        lessThanOrEqualTo(402.5),
        reason: tester.widget<Text>(texts.at(i)).data,
      );
    }
    final end = find.byKey(const Key('add-manually-end'));
    await tester.scrollUntilVisible(end, 300);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getRect(end).right, lessThanOrEqualTo(402.5));
  });
}
