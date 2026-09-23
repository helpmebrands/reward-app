import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reward/main.dart' as app;
import 'package:reward/screens/benefit_editor_screen.dart';
import 'package:reward/screens/card_editor_screen.dart';
import 'package:reward/screens/settings_screen.dart';
import 'package:reward/widgets/credit_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The one end-to-end flow, on a real simulator or emulator through
/// `make e2e`: launch empty, add a card from the catalogue, see its credits
/// on Today, log one from the sheet, undo it from the snackbar, log it by
/// swipe, see it under Credits and on Value, mute the card from Cards, and
/// change the theme in Settings.

Future<void> settle(WidgetTester tester) =>
    tester.pumpAndSettle(const Duration(milliseconds: 100));

Future<void> show(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await settle(tester);
}

/// Scrolls a row to the top of its list, clear of the snackbar that sits
/// over the bottom of the column for twenty seconds after a log.
Future<void> showTop(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0);
  await settle(tester);
}

Future<void> tab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await settle(tester);
}

Finder row(String name) =>
    find.ancestor(of: find.text(name), matching: find.byType(CreditRow)).first;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // @lat: [[mobile-tests#End to end#A fresh install launches to the first-run screen]]
  testWidgets('launches to the first-run screen on a fresh install', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    app.main();
    await settle(tester);
    expect(find.text('Start with one card'), findsOneWidget);
  });

  // @lat: [[mobile-tests#End to end#The parity flow runs through every screen]]
  testWidgets('adds a card, logs, undoes, swipes, and reads every screen', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    app.main();
    await settle(tester);

    // Add a card from the catalogue.
    await tab(tester, 'Cards');
    await show(tester, find.byKey(const Key('add-card')));
    await tester.tap(find.byKey(const Key('add-card')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('template-amex-platinum')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('field-holder')), 'Kathy');
    await tester.tap(find.text('Add this card'));
    await settle(tester);
    expect(find.byType(CardEditorScreen), findsOneWidget);
    expect(find.text('American Express Platinum — Kathy'), findsWidgets);
    await tester.tap(find.byTooltip('Back'));
    await settle(tester);

    // Its credits are on Today.
    await tab(tester, 'Today');
    await showTop(tester, row('Uber Cash'));
    expect(row('Uber Cash'), findsOneWidget);
    expect(
      tester.widget<CreditRow>(row('Uber Cash')).tone,
      isNot(RowTone.captured),
    );

    // Log it from the sheet, then undo from the snackbar.
    await showTop(tester, row('Uber Cash'));
    await tester.tap(row('Uber Cash'));
    await settle(tester);
    await tester.tap(find.text('Mark the full \$15 used'));
    await settle(tester);
    expect(find.text('Logged \$15 on Uber Cash.'), findsOneWidget);
    expect(tester.widget<CreditRow>(row('Uber Cash')).tone, RowTone.captured);
    await tester.tap(find.byKey(const Key('snackbar-action')));
    await settle(tester);
    expect(
      tester.widget<CreditRow>(row('Uber Cash')).tone,
      isNot(RowTone.captured),
    );

    // Log it by swipe.
    await showTop(tester, row('Uber Cash'));
    await tester.drag(row('Uber Cash'), const Offset(80, 0));
    await settle(tester);
    await tester.tap(find.text('Log it'));
    await settle(tester);
    expect(tester.widget<CreditRow>(row('Uber Cash')).tone, RowTone.captured);

    // It is under Credits > Captured, and on Value.
    await tab(tester, 'Credits');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Captured'));
    await settle(tester);
    await showTop(tester, row('Uber Cash'));
    expect(row('Uber Cash'), findsOneWidget);
    await tab(tester, 'Value');
    expect(
      find.descendant(
        of: find.byKey(const Key('value-captured')),
        matching: find.text('\$15'),
      ),
      findsOneWidget,
    );

    // Open a credit's editor from its sheet, then leave. The first row: the
    // logged one now sits last, under the snackbar that stays up for undo.
    await tab(tester, 'Today');
    await showTop(tester, find.byType(CreditRow).first);
    await tester.tap(find.byType(CreditRow).first);
    await settle(tester);
    await show(tester, find.text('Edit this credit'));
    await tester.tap(find.text('Edit this credit'));
    await settle(tester);
    expect(find.byType(BenefitEditorScreen), findsOneWidget);
    // Back from a credit goes to its card, and from the card to Cards.
    await tester.tap(find.byTooltip('Back'));
    await settle(tester);
    expect(find.byType(CardEditorScreen), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await settle(tester);

    // Mute the card from Cards.
    await tab(tester, 'Cards');
    await tester.tap(
      find.bySemanticsLabel('Menu for American Express Platinum — Kathy'),
    );
    await settle(tester);
    await tester.tap(find.text('Mute'));
    await settle(tester);
    expect(
      find.text('Silenced every credit on American Express Platinum — Kathy.'),
      findsOneWidget,
    );

    // Change the theme in Settings.
    await tab(tester, 'Today');
    await show(tester, find.bySemanticsLabel('Settings', skipOffstage: false));
    await tester.tap(find.bySemanticsLabel('Settings'));
    await settle(tester);
    expect(find.byType(SettingsScreen), findsOneWidget);
    await show(tester, find.text('Dark'));
    await tester.tap(find.text('Dark'));
    await settle(tester);
    expect(
      Theme.of(tester.element(find.text('Appearance'))).brightness,
      Brightness.dark,
    );
  });
}
