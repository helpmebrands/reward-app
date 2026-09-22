import 'package:domain/domain.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reward/data/snapshot_store.dart';
import 'package:reward/logic/app_store.dart';
import 'package:reward/logic/ui_state.dart';
import 'package:reward/main.dart';
import 'package:reward/widgets/credit_sheet.dart';
import 'package:reward/widgets/sheet_host.dart';

/// The credit sheet: opened by benefit id from any tab, in the shape the
/// width calls for, showing the live balance and every credit action.

const _stamp = '2026-01-01T00:00:00.000Z';

Card _card(String id, String holder) => Card(
  id: id,
  issuer: 'American Express',
  product: 'Platinum',
  holder: holder,
  network: CardNetwork.amex,
  annualFeeCents: 89500,
  anniversaryOn: '2021-03-14',
  muted: false,
  archived: false,
  createdAt: _stamp,
  updatedAt: _stamp,
);

Benefit _benefit(
  String id,
  String name,
  int valueCents, {
  Cadence cadence = Cadence.quarterly,
  bool enrollmentRequired = false,
  List<String> steps = const [],
}) => Benefit(
  id: id,
  cardId: 'jim',
  name: name,
  category: BenefitCategory.dining,
  valueCents: valueCents,
  cadence: cadence,
  anchor: CycleAnchor.calendar,
  enrollmentRequired: enrollmentRequired,
  redemptionSteps: steps,
  muted: false,
  lastCallOnly: false,
  active: true,
  createdAt: _stamp,
  updatedAt: _stamp,
);

Claim _claim(String id, String benefitId, int cents, String day) => Claim(
  id: id,
  benefitId: benefitId,
  cycleKey: '2026-07-01',
  amountCents: cents,
  claimedAt: '${day}T12:00:00.000Z',
);

/// Jim's card with a $100 Resy credit ($10 then $20 logged, $70 left), a
/// locked $300 Equinox credit, and a $15 Uber credit fully used.
AppData _household() => AppData(
  version: 1,
  cards: [_card('jim', 'Jim'), _card('kathy', 'Kathy')],
  benefits: [
    _benefit(
      'resy',
      'Resy Dining Credit',
      10000,
      steps: const ['Book through Resy.', 'Pay with the card.'],
    ),
    _benefit(
      'equinox',
      'Equinox Credit',
      30000,
      cadence: Cadence.annual,
      enrollmentRequired: true,
    ),
    _benefit('uber', 'Uber Cash', 1500, cadence: Cadence.monthly),
  ],
  claims: [
    _claim('old', 'resy', 1000, '2026-09-02'),
    _claim('new', 'resy', 2000, '2026-09-10'),
    const Claim(
      id: 'u',
      benefitId: 'uber',
      cycleKey: '2026-09-01',
      amountCents: 1500,
      claimedAt: '2026-09-10T12:00:00.000Z',
    ),
  ],
  settings: defaultSettings,
);

class _App {
  _App(this.store, this.ui);
  final AppStore store;
  final UiState ui;
}

Future<_App> pumpApp(WidgetTester tester, Size size) async {
  final store = AppStore(
    store: MemorySnapshotStore(_household()),
    clock: () => DateTime(2026, 9, 16),
  );
  await store.load();
  final ui = UiState();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(RewardApp(store: store, ui: ui));
  await tester.pumpAndSettle();
  return _App(store, ui);
}

Future<_App> openResy(WidgetTester tester, Size size) async {
  final app = await pumpApp(tester, size);
  app.ui.openCredit('resy');
  await tester.pumpAndSettle();
  return app;
}

const phone = Size(402, 874);
const tablet = Size(800, 1000);
const desktop = Size(1280, 800);

Finder get sheet => find.byKey(const Key('credit-sheet'));

void main() {
  group('quick amounts', () {
    // @lat: [[mobile-tests#Credit sheet#Quick amounts are a quarter and a half in whole dollars]]
    test('are a quarter and a half of the remainder, rounded to dollars', () {
      expect(quickAmounts(10000), [2500, 5000]);
      expect(quickAmounts(9000), [2300, 4500]);
      expect(quickAmounts(7000), [1800, 3500]);
      expect(quickAmounts(1500), [400, 800]);
      expect(quickAmounts(600), [200, 300]);
    });

    // @lat: [[mobile-tests#Credit sheet#Quick amounts never reach the remainder]]
    test('never reach the remainder and vanish under five dollars', () {
      expect(quickAmounts(0), isEmpty);
      expect(quickAmounts(499), isEmpty);
      expect(quickAmounts(500), [100, 300]);
      for (final remaining in [500, 700, 1295, 2500, 30000]) {
        for (final cents in quickAmounts(remaining)) {
          expect(cents, lessThan(remaining));
          expect(cents % 100, 0);
          expect(cents, greaterThanOrEqualTo(100));
        }
      }
    });
  });

  group('content', () {
    // @lat: [[mobile-tests#Credit sheet#The sheet shows the live balance]]
    testWidgets('opens by id with the balance and follows a claim', (
      tester,
    ) async {
      final app = await openResy(tester, phone);

      expect(find.text('Resy Dining Credit'), findsWidgets);
      expect(find.text('\$70'), findsOneWidget);
      expect(find.text('left of \$100'), findsOneWidget);
      expect(find.text('Mark the full \$70 used'), findsOneWidget);
      expect(find.text('\$18'), findsOneWidget);
      expect(find.text('\$35'), findsOneWidget);

      final instance = app.store.instanceFor('resy')!;
      await app.store.claim(instance, amountCents: 2000);
      await tester.pumpAndSettle();

      expect(app.ui.openBenefitId, 'resy');
      expect(find.text('\$50'), findsOneWidget);
      expect(find.text('Mark the full \$50 used'), findsOneWidget);
      expect(find.text('\$13'), findsOneWidget);
      expect(find.text('\$25'), findsOneWidget);
    });

    // @lat: [[mobile-tests#Credit sheet#Marking the full amount logs the remainder and closes]]
    testWidgets('marking the full amount claims the remainder and closes', (
      tester,
    ) async {
      final app = await openResy(tester, phone);

      await tester.tap(find.text('Mark the full \$70 used'));
      await tester.pumpAndSettle();

      final claims = app.store.data!.claims
          .where((c) => c.benefitId == 'resy')
          .toList();
      expect(claims.last.amountCents, 7000);
      expect(app.ui.openBenefitId, isNull);
      expect(sheet, findsNothing);
    });

    // @lat: [[mobile-tests#Credit sheet#A quick amount logs that amount]]
    testWidgets('a quick amount logs that amount', (tester) async {
      final app = await openResy(tester, phone);

      await tester.tap(find.widgetWithText(OutlinedButton, '\$35'));
      await tester.pumpAndSettle();

      expect(
        app.store.data!.claims
            .where((c) => c.benefitId == 'resy')
            .last
            .amountCents,
        3500,
      );
    });

    // @lat: [[mobile-tests#Credit sheet#A custom amount is capped at what is left]]
    testWidgets('a custom amount is parsed and capped at the remainder', (
      tester,
    ) async {
      final app = await openResy(tester, phone);

      await tester.tap(find.text('Other…'));
      await tester.pumpAndSettle();
      final field = find.byKey(const Key('custom-amount'));
      expect(field, findsOneWidget);

      await tester.enterText(field, 'lots');
      await tester.tap(find.widgetWithText(OutlinedButton, 'Log'));
      await tester.pumpAndSettle();
      expect(find.text('Enter an amount in dollars.'), findsOneWidget);
      expect(app.store.data!.claims, hasLength(3));

      await tester.enterText(field, '500');
      await tester.tap(find.widgetWithText(OutlinedButton, 'Log'));
      await tester.pumpAndSettle();
      expect(
        app.store.data!.claims
            .where((c) => c.benefitId == 'resy')
            .last
            .amountCents,
        7000,
      );
    });

    // @lat: [[mobile-tests#Credit sheet#Logged this period lists newest first and removes one]]
    testWidgets('lists the cycle newest first and Remove deletes one claim', (
      tester,
    ) async {
      final app = await openResy(tester, phone);

      final section = find.byKey(const Key('sheet-claims'));
      expect(section, findsOneWidget);
      final rows = find.descendant(
        of: section,
        matching: find.byKey(const Key('sheet-claim'), skipOffstage: false),
      );
      expect(rows, findsNWidgets(2));
      expect(
        tester.getTopLeft(rows.at(0)).dy,
        lessThan(tester.getTopLeft(rows.at(1)).dy),
      );
      expect(
        find.descendant(of: rows.at(0), matching: find.textContaining('\$20')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: rows.at(1), matching: find.textContaining('\$10')),
        findsOneWidget,
      );

      await tester.tap(
        find.bySemanticsLabel('Remove the \$20 logged on Sep 10'),
      );
      await tester.pumpAndSettle();

      expect(
        app.store.data!.claims
            .where((c) => c.benefitId == 'resy')
            .map((c) => c.id),
        ['old'],
      );
      expect(find.text('\$90'), findsOneWidget);
    });

    // @lat: [[mobile-tests#Credit sheet#Silence and last call are switches on the sheet]]
    testWidgets('the silence and last-call switches write the benefit', (
      tester,
    ) async {
      final app = await openResy(tester, phone);

      await tester.ensureVisible(
        find.bySemanticsLabel('Silence reminders for Resy Dining Credit'),
      );
      await tester.tap(
        find.bySemanticsLabel('Silence reminders for Resy Dining Credit'),
      );
      await tester.pumpAndSettle();
      expect(app.store.data!.benefits.first.muted, isTrue);

      await tester.tap(
        find.bySemanticsLabel('Last call only for Resy Dining Credit'),
      );
      await tester.pumpAndSettle();
      expect(app.store.data!.benefits.first.lastCallOnly, isTrue);
    });

    // @lat: [[mobile-tests#Credit sheet#A locked credit unlocks from the sheet]]
    testWidgets('a locked credit shows the note and unlocks', (tester) async {
      final app = await pumpApp(tester, phone);
      app.ui.openCredit('equinox');
      await tester.pumpAndSettle();

      expect(find.textContaining('Not enrolled.'), findsOneWidget);
      expect(find.text('Mark the full \$300 used'), findsNothing);

      await tester.tap(find.text('I’ve enrolled — unlock this credit'));
      await tester.pumpAndSettle();

      expect(app.store.data!.benefits[1].enrolledAt, isNotNull);
      expect(find.text('Mark the full \$300 used'), findsOneWidget);
    });

    // @lat: [[mobile-tests#Credit sheet#A captured credit can be undone]]
    testWidgets('a captured credit offers Undo for the whole cycle', (
      tester,
    ) async {
      final app = await pumpApp(tester, phone);
      app.ui.openCredit('uber');
      await tester.pumpAndSettle();

      expect(find.textContaining('Fully captured.'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(
        app.store.data!.claims.where((c) => c.benefitId == 'uber'),
        isEmpty,
      );
      expect(find.text('Mark the full \$15 used'), findsOneWidget);
    });
  });

  group('presentation', () {
    // @lat: [[mobile-tests#Credit sheet#Compact is a bottom sheet with a scrim]]
    testWidgets('is a bottom sheet with a scrim at 402', (tester) async {
      await openResy(tester, phone);

      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(ModalBarrier), findsWidgets);
      final rect = tester.getRect(sheet);
      expect(rect.bottom, phone.height);
      expect(rect.width, phone.width);
      expect(rect.top, greaterThan(0));
    });

    // @lat: [[mobile-tests#Credit sheet#Medium is a centred dialog]]
    testWidgets('is a centred dialog at most 480 wide at 800', (tester) async {
      await openResy(tester, tablet);

      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(Dialog), findsOneWidget);
      final rect = tester.getRect(sheet);
      expect(rect.width, lessThanOrEqualTo(480));
      expect(rect.height, lessThanOrEqualTo(tablet.height * 0.85));
      expect(rect.center.dx, closeTo(tablet.width / 2, 1));
      expect(rect.center.dy, closeTo(tablet.height / 2, 1));
    });

    // @lat: [[mobile-tests#Credit sheet#Expanded is a side panel beside a usable list]]
    testWidgets('is a 380 panel on the trailing edge at 1280', (tester) async {
      final app = await openResy(tester, desktop);

      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(ModalBarrier), findsNothing);
      final rect = tester.getRect(sheet);
      expect(rect.width, 380);
      expect(rect.right, desktop.width);
      expect(rect.height, desktop.height);
      final column = tester.getRect(find.byKey(const Key('content-column')));
      expect(column.right, lessThanOrEqualTo(rect.left));

      // The screen beside the panel still takes taps: switch tabs while the
      // sheet stays open.
      await tester.tap(find.text('Credits'));
      await tester.pumpAndSettle();
      expect(
        find.text('This screen arrives with a later issue.'),
        findsOneWidget,
      );
      expect(app.ui.openBenefitId, 'resy');
      expect(sheet, findsOneWidget);
    });

    // @lat: [[mobile-tests#Credit sheet#Escape and back close the sheet]]
    testWidgets('Escape and the system back both close it', (tester) async {
      final app = await openResy(tester, tablet);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(app.ui.openBenefitId, isNull);
      expect(sheet, findsNothing);

      app.ui.openCredit('resy');
      await tester.pumpAndSettle();
      expect(sheet, findsOneWidget);
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(app.ui.openBenefitId, isNull);
      expect(sheet, findsNothing);
    });

    // @lat: [[mobile-tests#Credit sheet#Every control on the sheet has a label]]
    testWidgets('every button and switch on the sheet carries a label', (
      tester,
    ) async {
      await openResy(tester, phone);

      final unlabelled = <String>[];
      void walk(SemanticsNode node) {
        final flags = node.getSemanticsData().flagsCollection;
        final control =
            flags.isButton ||
            flags.isTextField ||
            flags.isToggled != Tristate.none;
        if (control && node.label.isEmpty && node.tooltip.isEmpty) {
          unlabelled.add(node.toString());
        }
        node.visitChildren((child) {
          walk(child);
          return true;
        });
      }

      walk(tester.getSemantics(sheet));
      expect(unlabelled, isEmpty);
    });
  });

  group('sheet host', () {
    // @lat: [[mobile-tests#Credit sheet#The sheet is a modal route that takes and returns focus]]
    testWidgets('scopes a route, takes focus on open and returns it on close', (
      tester,
    ) async {
      final rowFocus = FocusNode(debugLabel: 'row');
      addTearDown(rowFocus.dispose);
      final open = ValueNotifier(false);
      addTearDown(open.dispose);
      tester.view.physicalSize = phone;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder(
            valueListenable: open,
            builder: (context, isOpen, _) => SheetHost(
              open: isOpen,
              title: 'Resy Dining Credit',
              onClose: () => open.value = false,
              sheet: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Resy Dining Credit'),
                  OutlinedButton(
                    key: const Key('sheet-close'),
                    onPressed: () => open.value = false,
                    child: const Text('Close'),
                  ),
                ],
              ),
              child: Scaffold(
                body: Focus(focusNode: rowFocus, child: const Text('row')),
              ),
            ),
          ),
        ),
      );
      rowFocus.requestFocus();
      await tester.pump();
      expect(rowFocus.hasPrimaryFocus, isTrue);

      open.value = true;
      await tester.pumpAndSettle();

      final host = tester.getSemantics(sheet);
      final flags = host.getSemanticsData().flagsCollection;
      expect(flags.scopesRoute, isTrue);
      expect(flags.namesRoute, isTrue);
      expect(host.label, 'Resy Dining Credit');
      expect(rowFocus.hasPrimaryFocus, isFalse);
      final focused = FocusManager.instance.primaryFocus!;
      expect(
        focused.context!.findAncestorWidgetOfExactType<SheetHost>(),
        isNotNull,
      );
      expect(
        find.descendant(
          of: sheet,
          matching: find.byWidget(focused.context!.widget),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('sheet-close')));
      await tester.pumpAndSettle();
      expect(sheet, findsNothing);
      expect(rowFocus.hasPrimaryFocus, isTrue);
    });
  });
}
