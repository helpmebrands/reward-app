import 'package:domain/domain.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:reward/data/household_api.dart';
import 'package:reward/data/snapshot_store.dart';
import 'package:reward/logic/app_store.dart';
import 'package:reward/logic/ui_state.dart';
import 'package:reward/main.dart';
import 'package:reward/screens/card_editor_screen.dart';
import 'package:reward/screens/convert_screen.dart';
import 'package:reward/shell/router.dart';

import 'support/fake_api.dart';

/// Cards the catalogue keeps up to date and cards the household maintains:
/// the two groups on Cards, read-only terms on a system card, and the
/// conversion that makes it the household's own.

final now = DateTime(2026, 9, 16, 10);

/// A household with a Gold from the catalogue, a claim on its Uber Cash,
/// and a card of the household's own.
Future<({AppStore store, FakeApi api, UiState ui, String gold})> pump(
  WidgetTester tester, {
  String location = Paths.cards,
}) async {
  final api = FakeApi(
    data: serverHousehold().copyWith(cards: [], benefits: []),
  );
  final gold = await api.addCard({
    'templateId': 'amex-gold',
    'anniversaryOn': '2024-05-01',
    'kind': 'personal',
  });
  await api.addCard({
    'issuer': 'Chase',
    'product': 'Freedom',
    'anniversaryOn': '2023-01-15',
    'kind': 'personal',
  });
  final uber = api.data.benefits.firstWhere(
    (b) => b.templateBenefitId == 'amex-gold/uber-cash',
  );
  await api.postClaim('k', {
    'benefitId': uber.id,
    'cycleKey': '2026-09-01',
    'amountCents': 500,
    'claimedAt': '2026-09-05T12:00:00.000Z',
  });
  final store = AppStore(
    store: MemorySnapshotStore(),
    api: api,
    clock: () => now,
  );
  await store.load();
  final ui = UiState();
  tester.view.physicalSize = const Size(402, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    RewardApp(
      store: store,
      ui: ui,
      initialLocation: location.replaceAll('{gold}', gold.id),
    ),
  );
  await tester.pumpAndSettle();
  return (store: store, api: api, ui: ui, gold: gold.id);
}

Finder key(String k) => find.byKey(Key(k));

/// Which group a card's title sits in on Cards.
String groupOf(WidgetTester tester, String title) {
  final y = tester.getTopLeft(find.text(title).first).dy;
  final system = tester.getTopLeft(key('cards-system')).dy;
  final user = tester.getTopLeft(key('cards-user')).dy;
  return y > user ? 'user' : (y > system ? 'system' : 'none');
}

void main() {
  // @lat: [[mobile-tests#System and user cards#Cards groups system and user cards]]
  testWidgets('a template card is under system cards, a blank one under '
      '"Maintained by you"', (tester) async {
    await pump(tester);
    expect(find.text('Kept up to date'), findsOneWidget);
    expect(find.text('Maintained by you'), findsOneWidget);
    expect(groupOf(tester, 'American Express Gold'), 'system');
    expect(groupOf(tester, 'Chase Freedom'), 'user');
  });

  // @lat: [[mobile-tests#System and user cards#A system card's terms are read-only]]
  testWidgets('a system card’s terms are read-only and "Change the terms" '
      'explains before anything changes', (tester) async {
    final app = await pump(tester, location: '/cards/{gold}');
    expect(find.byType(CardEditorScreen), findsOneWidget);
    expect(tester.widget<TextField>(key('field-fee')).readOnly, isTrue);
    expect(find.widgetWithText(OutlinedButton, 'Add'), findsNothing);
    // Household fields stay the household's.
    expect(tester.widget<TextField>(key('field-label')).readOnly, isFalse);

    await tester.ensureVisible(key('change-terms'));
    await tester.tap(key('change-terms'));
    await tester.pumpAndSettle();
    expect(find.byType(ConvertScreen), findsOneWidget);
    expect(
      find.textContaining('no longer update automatically'),
      findsOneWidget,
    );
    expect(find.textContaining('keeps its claims'), findsOneWidget);
    expect(app.api.converted, isEmpty);
  });

  // @lat: [[mobile-tests#System and user cards#Conversion keeps the claims]]
  testWidgets('converting moves the card to "Maintained by you" with the '
      'same claims and captured total', (tester) async {
    final app = await pump(tester, location: '/cards/{gold}/convert');
    final captured = app.store.totals.capturedCents;
    expect(captured, 500);

    await tester.tap(key('convert-confirm'));
    await tester.pumpAndSettle();
    expect(app.api.converted, [app.gold]);
    expect(find.byType(CardEditorScreen), findsOneWidget);
    final card = app.store.data!.cards.firstWhere((c) => c.product == 'Gold');
    expect(maintainedBy(card), MaintainedBy.user);
    expect(app.store.totals.capturedCents, captured);
    expect(app.store.data!.claims.single.amountCents, 500);
    // The converted card's terms are the household's now.
    expect(tester.widget<TextField>(key('field-fee')).readOnly, isFalse);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(groupOf(tester, 'American Express Gold'), 'user');
  });

  // @lat: [[mobile-tests#System and user cards#A second card of a product is numbered]]
  testWidgets('adding a second Gold proposes "American Express Gold (1)"', (
    tester,
  ) async {
    await pump(tester, location: Paths.newCard);
    final gold = key('template-amex-gold');
    await tester.scrollUntilVisible(gold, 200);
    await tester.tap(gold);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(key('field-label')).controller!.text,
      'American Express Gold (1)',
    );
  });

  test('the catalogue comes from the api in the service-tier mode', () async {
    final api = FakeApi();
    final store = AppStore(store: MemorySnapshotStore(), api: api);
    await store.load();
    expect(store.templates.map((t) => t.id), contains('amex-gold'));
    expect(store.templates.last.id, 'blank');
    expect(api.role, MemberRole.editor);
  });
}
