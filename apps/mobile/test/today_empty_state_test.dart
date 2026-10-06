import 'package:domain/domain.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reward/data/snapshot_store.dart';
import 'package:reward/logic/app_store.dart';
import 'package:reward/logic/ui_state.dart';
import 'package:reward/main.dart';
import 'package:reward/screens/add_card_screen.dart';
import 'package:reward/screens/join_screen.dart';
import 'package:reward/screens/today_screen.dart';
import 'package:reward/theme/theme.dart';
import 'package:reward/widgets/empty_card_slot.dart';
import 'package:reward/widgets/today_headline.dart';
import 'package:reward/widgets/value_bar.dart';

import 'contrast_test.dart' show ratio;
import 'support/fake_api.dart';

/// Today before any card: the empty state's copy, its two actions, who sees
/// them, and its layout at the three width classes.

const heading = 'Add a card to start tracking its credits';
const body =
    'Reward cards pay back through monthly, quarterly and yearly credits '
    'that expire if you don’t use them. Add a card and HelpMe Reward will '
    'show what’s about to close.';

final addButton = find.byKey(const Key('empty-add-card'));
final inviteButton = find.byKey(const Key('today-invite-code'));

AppData _household({
  List<Card> cards = const [],
  List<Benefit> benefits = const [],
}) => emptyAppData().copyWith(cards: cards, benefits: benefits);

/// The whole app at Today, local unless [api] is given.
Future<AppStore> pumpApp(
  WidgetTester tester, {
  AppData? data,
  FakeApi? api,
  Size size = const Size(402, 874),
}) async {
  final store = AppStore(
    store: MemorySnapshotStore(api == null ? data : null),
    api: api,
    clock: () => DateTime(2026, 9, 16, 10),
  );
  await store.load();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(RewardApp(store: store, ui: UiState()));
  await tester.pumpAndSettle();
  return store;
}

/// The first node flagged as a header, in traversal order.
String? firstHeader(WidgetTester tester) {
  final root = tester
      .binding
      .renderViews
      .first
      .owner!
      .semanticsOwner!
      .rootSemanticsNode!;
  String? found;
  void visit(SemanticsNode node) {
    if (found != null) return;
    if (node.getSemanticsData().flagsCollection.isHeader) {
      found = node.getSemanticsData().label;
      return;
    }
    for (final child in node.debugListChildrenInOrder(
      DebugSemanticsDumpOrder.traversalOrder,
    )) {
      visit(child);
    }
  }

  visit(root);
  return found;
}

void main() {
  // @lat: [[mobile-tests#Today empty state#The heading is the screen's first header]]
  testWidgets('with no cards the heading is the first header', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpApp(tester);
    expect(find.text(heading), findsOneWidget);
    expect(firstHeader(tester), heading);
    handle.dispose();
  });

  // @lat: [[mobile-tests#Today empty state#No value bar without a card]]
  testWidgets('with no active card Today draws no value bar', (tester) async {
    await pumpApp(tester);
    expect(find.text(heading), findsOneWidget);
    expect(find.byType(ValueBar), findsNothing);
  });

  // @lat: [[mobile-tests#Today empty state#The body clears 4.5:1 in both themes]]
  testWidgets('the body is shown and clears 4.5:1 in light and dark', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      await pumpApp(tester);
      final paragraph = tester.renderObject<RenderParagraph>(find.text(body));
      final colour = paragraph.text.style!.color!;
      final page = nocturneTheme(brightness).scaffoldBackgroundColor;
      expect(
        ratio(colour, page),
        greaterThanOrEqualTo(4.5),
        reason: brightness.name,
      );
    }
    tester.platformDispatcher.clearPlatformBrightnessTestValue();
  });

  // @lat: [[mobile-tests#Today empty state#Add your first card opens the catalogue and Back returns]]
  testWidgets('Add your first card pushes the catalogue; Back returns', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(
      find.descendant(
        of: addButton,
        matching: find.text('Add your first card'),
      ),
      findsOneWidget,
    );
    await tester.tap(addButton);
    await tester.pumpAndSettle();
    expect(find.byType(AddCardScreen), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(AddCardScreen), findsNothing);
    expect(find.text(heading), findsOneWidget);
  });

  // @lat: [[mobile-tests#Today empty state#Only archived cards read Add a card]]
  testWidgets('with only archived cards the button reads Add a card', (
    tester,
  ) async {
    await pumpApp(
      tester,
      data: _household(cards: [card1.copyWith(archived: true)]),
    );
    expect(find.text(heading), findsOneWidget);
    expect(
      find.descendant(of: addButton, matching: find.text('Add a card')),
      findsOneWidget,
    );
  });

  // @lat: [[mobile-tests#Today empty state#Loading is not empty]]
  testWidgets('while loading the spinner shows, not the empty state', (
    tester,
  ) async {
    final store = AppStore(store: MemorySnapshotStore());
    await tester.pumpWidget(
      MaterialApp(
        theme: nocturneTheme(Brightness.dark),
        home: Scaffold(body: TodayScreen(store: store)),
      ),
    );
    expect(store.loading, isTrue);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text(heading), findsNothing);
  });

  // @lat: [[mobile-tests#Today empty state#The first card switches Today to its normal layout]]
  testWidgets('adding a card switches to the normal layout', (tester) async {
    final store = await pumpApp(tester);
    expect(find.text(heading), findsOneWidget);
    await store.addCardFromTemplate(cardTemplates.first);
    await tester.pumpAndSettle();
    expect(find.text(heading), findsNothing);
    expect(find.byType(TodayHeadline), findsOneWidget);
  });

  // @lat: [[mobile-tests#Today empty state#A household with only locked credits is not empty]]
  testWidgets('a card whose credits are all locked shows the normal layout', (
    tester,
  ) async {
    await pumpApp(
      tester,
      data: _household(
        cards: [card1],
        benefits: [benefit1.copyWith(enrollmentRequired: true)],
      ),
      size: const Size(402, 2000),
    );
    expect(find.text(heading), findsNothing);
    expect(find.textContaining('Locked behind enrollment'), findsOneWidget);
  });

  // @lat: [[mobile-tests#Today empty state#The invite button shows signed in and opens the join screen]]
  testWidgets('the invite button is signed-in only and joins by code', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(inviteButton, findsNothing);

    await pumpApp(tester, api: FakeApi(data: _household()));
    expect(
      find.descendant(
        of: inviteButton,
        matching: find.text('Joining a household? Enter an invite code'),
      ),
      findsOneWidget,
    );
    await tester.tap(inviteButton);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('invite-code-field')),
      'abcd2345',
    );
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.byType(JoinScreen), findsOneWidget);
    expect(find.text('ABCD2345'), findsOneWidget);
  });

  // @lat: [[mobile-tests#Today empty state#Both buttons are 48 high]]
  testWidgets('both buttons are at least 48 high', (tester) async {
    await pumpApp(tester, api: FakeApi(data: _household()));
    expect(tester.getSize(addButton).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(inviteButton).height, greaterThanOrEqualTo(48));
  });

  // @lat: [[mobile-tests#Today empty state#Stacked at compact and medium, side by side at expanded]]
  testWidgets('layout: stacked, then the illustration beside the text', (
    tester,
  ) async {
    for (final size in const [Size(402, 874), Size(768, 1024)]) {
      await pumpApp(
        tester,
        api: FakeApi(data: _household()),
        size: size,
      );
      expect(tester.takeException(), isNull, reason: '$size');
      final slot = tester.getRect(find.byType(EmptyCardSlot));
      final title = tester.getRect(find.text(heading));
      expect(slot.bottom, lessThanOrEqualTo(title.top), reason: '$size');
      final add = tester.getRect(addButton);
      expect(add.bottom, lessThanOrEqualTo(size.height), reason: '$size');
    }

    const expanded = Size(1280, 832);
    await pumpApp(
      tester,
      api: FakeApi(data: _household()),
      size: expanded,
    );
    expect(tester.takeException(), isNull);
    final slot = tester.getRect(find.byType(EmptyCardSlot));
    final title = tester.getRect(find.text(heading));
    expect(slot.right, lessThanOrEqualTo(title.left));
    final add = tester.getRect(addButton);
    expect(add.top, greaterThanOrEqualTo(0));
    expect(add.bottom, lessThanOrEqualTo(expanded.height));
  });

  // @lat: [[mobile-tests#Today empty state#The app bar and navigation stay]]
  testWidgets('the app bar gear and the navigation stay', (tester) async {
    await pumpApp(tester);
    expect(find.text(heading), findsOneWidget);
    expect(find.bySemanticsLabel('Settings'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
