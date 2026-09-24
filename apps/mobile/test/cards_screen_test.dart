import 'dart:convert';
import 'dart:io';

import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reward/data/snapshot_store.dart';
import 'package:reward/logic/app_store.dart';
import 'package:reward/logic/ui_state.dart';
import 'package:reward/screens/cards_screen.dart';
import 'package:reward/shell/width_class.dart';
import 'package:reward/theme/theme.dart';
import 'package:reward/widgets/snackbar_host.dart';

/// The Cards screen against what the PWA shows for the sample household on
/// 16 September 2026, dumped by `apps/pwa/scripts/cards-snapshot.ts`.

/// The PWA's sample household, its two Platinums labelled with the names
/// the PWA shows for them, so the PWA's fixtures still apply.
AppData sampleHousehold() {
  final data = appDataFromJson(
    jsonDecode(File('../pwa/samples/sample-household.json').readAsStringSync())
        as Map<String, dynamic>,
  );
  const labels = {
    'card-0001': 'American Express Platinum — Jim',
    'card-0002': 'American Express Platinum — Kathy',
  };
  return data.copyWith(
    cards: [for (final c in data.cards) c.copyWith(label: labels[c.id])],
  );
}

Map<String, dynamic> expected() =>
    jsonDecode(File('test/fixtures/sample-cards.json').readAsStringSync())
        as Map<String, dynamic>;

final DateTime now = DateTime(2026, 9, 16, 8);

class Pumped {
  Pumped(this.store, this.ui);
  final AppStore store;
  final UiState ui;
}

Future<Pumped> pumpCards(
  WidgetTester tester, {
  AppData? data,
  WidthClass widthClass = WidthClass.compact,
  double textScale = 1,
  double height = 3000,
}) async {
  final store = AppStore(
    store: MemorySnapshotStore(data ?? sampleHousehold()),
    clock: () => now,
  );
  await store.load();
  final ui = UiState();
  addTearDown(ui.dispose);
  tester.view.physicalSize = Size(widthClass.column, height);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    MaterialApp(
      theme: nocturneTheme(Brightness.dark),
      home: Scaffold(
        body: WidthClassScope(
          widthClass: widthClass,
          child: SnackbarHost(
            snackbar: ui.snackbar,
            child: CardsScreen(store: store, ui: ui),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return Pumped(store, ui);
}

Finder card(String id) => find.byKey(ValueKey('card-$id'));

Finder within(String id, String text) =>
    find.descendant(of: card(id), matching: find.text(text));

Future<void> openMenu(WidgetTester tester, String label) async {
  await tester.tap(find.bySemanticsLabel('Menu for $label'));
  await tester.pumpAndSettle();
}

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
  // @lat: [[mobile-tests#Cards#Each card carries the PWA's figures, verdict and tags]]
  testWidgets('renders every active card with the PWA verdict and tags', (
    tester,
  ) async {
    await pumpCards(tester);
    final fixture = expected();
    final cards = (fixture['cards'] as List).cast<Map<String, dynamic>>();

    expect(find.text('Cards'), findsOneWidget);
    expect(
      find.text(
        '${formatMoney(fixture['feeTotalCents'] as int)} in fees this '
        'cardmember year. Value captured so far: '
        '${formatMoney(fixture['capturedTotalCents'] as int)}.',
      ),
      findsOneWidget,
    );
    expect(find.byWidgetPredicate(_isCard), findsNWidgets(cards.length));
    for (final c in cards) {
      final id = c['id'] as String;
      expect(card(id), findsOneWidget);
      expect(within(id, c['issuer'] as String), findsOneWidget);
      expect(within(id, c['label'] as String), findsOneWidget);
      expect(within(id, c['fee'] as String), findsOneWidget);
      expect(within(id, c['captured'] as String), findsOneWidget);
      expect(within(id, c['net'] as String), findsOneWidget);
      expect(
        within(
          id,
          '${c['percent']}% of the fee earned back · '
          '${c['daysUntilRenewal']} days to renewal',
        ),
        findsOneWidget,
      );
      final verdict = c['verdict'] as Map<String, dynamic>;
      expect(
        find.descendant(
          of: card(id),
          matching: find.textContaining('${verdict['headline']}.'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: card(id),
          matching: find.textContaining(verdict['body'] as String),
        ),
        findsOneWidget,
      );
      for (final tag in (c['tags'] as List).cast<String>()) {
        expect(within(id, tag), findsOneWidget, reason: tag);
      }
      expect(within(id, 'Edit card and credits'), findsOneWidget);
    }
    expect(find.text('Add a card from the catalogue'), findsOneWidget);
  });

  // @lat: [[mobile-tests#Cards#A business card carries a Business mark]]
  testWidgets('a business card shows a Business tag and a personal one none', (
    tester,
  ) async {
    final sample = sampleHousehold();
    await pumpCards(
      tester,
      data: sample.copyWith(
        cards: [
          for (final c in sample.cards)
            c.id == 'card-0001' ? c.copyWith(kind: CardKind.business) : c,
        ],
      ),
    );
    expect(within('card-0001', 'Business'), findsOneWidget);
    expect(within('card-0002', 'Business'), findsNothing);
  });

  // @lat: [[mobile-tests#Cards#The verdict is the PWA's, case by case]]
  test('cardVerdict words each case as the PWA does', () {
    CardSummary summary({
      int fee = 89500,
      int net = -30000,
      int claimable = 50000,
      int locked = 0,
      int days = 100,
    }) => CardSummary(
      card: sampleHousehold().cards.first,
      instances: const [],
      annualValueCents: 0,
      capturedCents: fee + net,
      claimableCents: claimable,
      lockedCents: locked,
      missedCents: 0,
      annualFeeCents: fee,
      netCents: net,
      feeProgress: 0.5,
      daysUntilRenewal: days,
    );

    expect(cardVerdict(summary(fee: 0)).headline, 'No fee');
    expect(cardVerdict(summary(net: 1000)).headline, 'Keep');
    expect(
      cardVerdict(summary(net: 1000)).body,
      'Already \$10 past the fee, with \$500 still open.',
    );
    expect(
      cardVerdict(
        summary(net: -60000, claimable: 20000, locked: 50000),
      ).headline,
      'Unlock first',
    );
    expect(cardVerdict(summary()).headline, 'Catch up');
    expect(
      cardVerdict(summary()).body,
      '\$500 is still claimable — more than the \$300 you are short. 100 days to the renewal.',
    );
    final decide = cardVerdict(summary(net: -80000, claimable: 10000));
    expect(decide.headline, 'Decide');
    expect(
      decide.body,
      contains('Lounge access and status are not counted here.'),
    );
  });

  // @lat: [[mobile-tests#Cards#Mute from the menu offers an undo]]
  testWidgets('Mute from the menu silences the card with an Undo', (
    tester,
  ) async {
    final p = await pumpCards(tester);

    await openMenu(tester, 'American Express Platinum — Jim');
    await tester.tap(find.text('Mute'));
    await tester.pumpAndSettle();

    expect(p.store.data!.cards.first.muted, isTrue);
    final message = p.ui.snackbar.current!;
    expect(
      message.text,
      'Silenced every credit on American Express Platinum — Jim.',
    );
    expect(
      message.action!.semanticsLabel,
      'Undo silencing American Express Platinum — Jim',
    );
    message.action!.onAct();
    await tester.pumpAndSettle();
    expect(p.store.data!.cards.first.muted, isFalse);

    await openMenu(tester, 'American Express Platinum — Jim');
    expect(find.text('Mute'), findsOneWidget);
    expect(find.text('Unmute'), findsNothing);
  });

  // @lat: [[mobile-tests#Cards#Archive hides the card]]
  testWidgets('Archive hides the card and offers an Undo', (tester) async {
    final p = await pumpCards(tester);

    await openMenu(tester, 'American Express Platinum — Jim');
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();

    expect(p.store.data!.cards.first.archived, isTrue);
    expect(card('card-0001'), findsNothing);
    expect(card('card-0002'), findsOneWidget);
    expect(
      p.ui.snackbar.current!.text,
      'Archived American Express Platinum — Jim.',
    );
    p.ui.snackbar.current!.action!.onAct();
    await tester.pumpAndSettle();
    expect(card('card-0001'), findsOneWidget);
  });

  // @lat: [[mobile-tests#Cards#Delete asks first and cascades]]
  testWidgets('Delete asks first, then removes the card and its benefits', (
    tester,
  ) async {
    final p = await pumpCards(tester);
    const question =
        'Delete American Express Platinum — Jim and everything logged '
        'against it? This cannot be undone.';

    await openMenu(tester, 'American Express Platinum — Jim');
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text(question), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(card('card-0001'), findsOneWidget);
    expect(p.store.data!.cards, hasLength(2));

    await openMenu(tester, 'American Express Platinum — Jim');
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(card('card-0001'), findsNothing);
    expect(p.store.data!.cards.map((c) => c.id), ['card-0002']);
    expect(p.store.data!.benefits.any((b) => b.cardId == 'card-0001'), isFalse);
    expect(p.ui.snackbar.current!.text, 'Card deleted.');
    expect(p.ui.snackbar.current!.action, isNull);
  });

  // @lat: [[mobile-tests#Cards#One column, two across, then one wide row]]
  testWidgets('stacks at 402, pairs at medium, one wide row at expanded', (
    tester,
  ) async {
    await pumpCards(tester);
    expect(
      tester.getRect(card('card-0002')).top,
      greaterThan(tester.getRect(card('card-0001')).bottom - 1),
    );

    await pumpCards(tester, widthClass: WidthClass.medium);
    expect(
      tester.getRect(card('card-0002')).top,
      tester.getRect(card('card-0001')).top,
    );
    expect(
      tester.getRect(card('card-0002')).left,
      greaterThan(tester.getRect(card('card-0001')).right),
    );

    await pumpCards(tester, widthClass: WidthClass.expanded);
    final first = tester.getRect(card('card-0001'));
    expect(
      tester.getRect(card('card-0002')).top,
      greaterThan(first.bottom - 1),
    );
    expect(first.width, 720 - 2 * 28);
    final figures = tester.getRect(
      find.byKey(const Key('card-figures-card-0001')),
    );
    final verdict = tester.getRect(
      find.byKey(const Key('card-verdict-card-0001')),
    );
    expect(verdict.left, greaterThan(figures.right));
    expect(verdict.top, lessThan(figures.bottom));
  });

  // @lat: [[mobile-tests#Cards#The screen reader hears the phone order at every width]]
  testWidgets('semantics traversal at 1280 is the traversal at 402', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpCards(tester);
    final compact = spokenOrder(tester);
    await pumpCards(tester, widthClass: WidthClass.expanded);
    final expanded = spokenOrder(tester);
    handle.dispose();
    expect(compact, isNotEmpty);
    expect(expanded, compact);
  });

  // @lat: [[mobile-tests#Cards#Cards at 200% clips nothing]]
  testWidgets('at a 2.0 text scale nothing overflows or leaves the width', (
    tester,
  ) async {
    await pumpCards(tester, textScale: 2, height: 8000);
    expect(tester.takeException(), isNull);
    final texts = find.byType(Text, skipOffstage: false);
    for (var i = 0; i < texts.evaluate().length; i++) {
      expect(
        tester.getRect(texts.at(i)).right,
        lessThanOrEqualTo(402.5),
        reason: tester.widget<Text>(texts.at(i)).data,
      );
    }
  });

  // @lat: [[mobile-tests#Cards#Every control on a card has a label]]
  testWidgets('the menu and every button carry a label', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpCards(tester);

    final unlabelled = <String>[];
    void walk(SemanticsNode node) {
      final flags = node.getSemanticsData().flagsCollection;
      if (flags.isButton && node.label.isEmpty && node.tooltip.isEmpty) {
        unlabelled.add(node.toString());
      }
      node.visitChildren((child) {
        walk(child);
        return true;
      });
    }

    walk(tester.getSemantics(find.byType(ListView)));
    expect(unlabelled, isEmpty);
    expect(
      find.bySemanticsLabel('Menu for American Express Platinum — Jim'),
      findsOneWidget,
    );
    handle.dispose();
  });

  // @lat: [[mobile-tests#Cards#No cards shows the first-run copy]]
  testWidgets('with no cards it says to start with one', (tester) async {
    final data = sampleHousehold();
    await pumpCards(
      tester,
      data: data.copyWith(
        cards: const [],
        benefits: const [],
        claims: const [],
      ),
    );
    expect(find.text('Start with one card'), findsOneWidget);
    expect(find.byWidgetPredicate(_isCard), findsNothing);
    expect(find.text('Add a card from the catalogue'), findsOneWidget);
  });
}

bool _isCard(Widget w) =>
    w.key is ValueKey<String> &&
    (w.key as ValueKey<String>).value.startsWith('card-card-');
