import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reward/screens/welcome_hero.dart';
import 'package:reward/screens/welcome_screen.dart';
import 'package:reward/theme/theme.dart';
import 'package:reward/widgets/brand_lockup.dart';

/// The welcome slideshow's layout: the lockup header, the order and copy of
/// the slides, and the decorative hero panel above left-aligned text.

Future<void> pumpWelcome(
  WidgetTester tester, {
  Size size = const Size(402, 874),
  double textScale = 1.0,
  Brightness brightness = Brightness.light,
  VoidCallback? onDone,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    MaterialApp(
      theme: nocturneTheme(brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: WelcomeScreen(onDone: onDone ?? () {}),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> nextSlide(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('welcome-next')));
  await tester.pumpAndSettle();
}

int levelOneHeadings(WidgetTester tester) {
  var count = 0;
  void visit(SemanticsNode node) {
    if (node.getSemanticsData().headingLevel == 1) count++;
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  var root = tester.getSemantics(find.byType(Scaffold).first);
  while (root.parent != null) {
    root = root.parent!;
  }
  visit(root);
  return count;
}

const titles = [
  'Upcoming rewards at a glance',
  'Timely reminders',
  'Premium features',
];

void main() {
  // @lat: [[mobile-tests#Welcome layout#Three slides in the new order]]
  testWidgets('the slides read in the new order; the last says Get started', (
    tester,
  ) async {
    expect(welcomeSlides.map((s) => s.title), titles);
    expect(welcomeSlides[0].body, contains('household'));
    expect(welcomeSlides[1].body, contains('one notification'));
    expect(welcomeSlides[2].body, contains('bank linking'));
    await pumpWelcome(tester);
    for (var i = 0; i < titles.length; i++) {
      expect(find.text(titles[i]), findsOneWidget);
      expect(find.text(i == 2 ? 'Get started' : 'Next'), findsOneWidget);
      if (i < 2) await nextSlide(tester);
    }
  });

  // @lat: [[mobile-tests#Welcome layout#The lockup heads the slideshow]]
  testWidgets('the header draws the lockup and Skip still finishes', (
    tester,
  ) async {
    var done = 0;
    await pumpWelcome(tester, onDone: () => done++);
    expect(find.byType(BrandLockup), findsOneWidget);
    expect(find.text('HelpMe Reward'), findsNothing);
    final lockup = tester.getRect(find.byType(BrandLockup));
    final skip = tester.getRect(find.byKey(const Key('welcome-skip')));
    expect(lockup.left, lessThan(skip.left));
    expect(lockup.center.dy, closeTo(skip.center.dy, 1));
    await tester.tap(find.byKey(const Key('welcome-skip')));
    expect(done, 1);
  });

  // @lat: [[mobile-tests#Welcome layout#The hero is decoration]]
  testWidgets('each slide has a hero whose child ignores taps and adds no '
      'semantics', (tester) async {
    await pumpWelcome(tester);
    for (var i = 0; i < titles.length; i++) {
      expect(find.byType(WelcomeHero), findsOneWidget, reason: titles[i]);
      if (i < 2) await nextSlide(tester);
    }

    final handle = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: nocturneTheme(Brightness.light),
        home: Center(
          child: SizedBox(
            width: 360,
            height: 300,
            child: WelcomeHero(
              child: GestureDetector(
                onTap: () => taps++,
                child: Semantics(
                  label: 'probe',
                  button: true,
                  child: const SizedBox(width: 360, height: 300),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.bySemanticsLabel('probe'), findsNothing);
    await tester.tap(find.byType(WelcomeHero), warnIfMissed: false);
    expect(taps, 0);
    handle.dispose();
  });

  // @lat: [[mobile-tests#Welcome layout#The hero ignores the text scale]]
  testWidgets('the hero lays its child out 360 wide at text scale 1.0', (
    tester,
  ) async {
    BoxConstraints? constraints;
    double? scaled;
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: nocturneTheme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2.0)),
          child: child!,
        ),
        home: Center(
          child: SizedBox(
            width: 272,
            height: 300,
            child: WelcomeHero(
              child: LayoutBuilder(
                builder: (context, c) {
                  constraints = c;
                  scaled = MediaQuery.textScalerOf(context).scale(10);
                  return const SizedBox(height: 400);
                },
              ),
            ),
          ),
        ),
      ),
    );
    expect(constraints!.maxWidth, WelcomeHero.designWidth);
    expect(constraints!.minWidth, WelcomeHero.designWidth);
    expect(WelcomeHero.designWidth, 360);
    expect(scaled, 10);
    expect(tester.takeException(), isNull);
  });

  // @lat: [[mobile-tests#Welcome layout#Text sits below the hero on a phone]]
  testWidgets('at 402 x 874 the headline sits below the panel, not in the '
      'top third', (tester) async {
    await pumpWelcome(tester);
    for (var i = 0; i < titles.length; i++) {
      final panel = tester.getRect(find.byType(WelcomeHero));
      final headline = tester.getRect(find.text(titles[i]));
      final body = tester.getRect(find.text(welcomeSlides[i].body));
      expect(panel.height, greaterThan(874 * 0.4), reason: titles[i]);
      expect(headline.top, greaterThanOrEqualTo(panel.bottom));
      expect(body.bottom, greaterThan(874 / 3));
      expect(headline.left, closeTo(body.left, 0.5));
      expect(headline.left, closeTo(panel.left, 0.5));
      if (i < 2) await nextSlide(tester);
    }
  });

  // @lat: [[mobile-tests#Welcome layout#A small phone at 2.0 drops the hero]]
  testWidgets('at 320 x 568 and 2.0 every slide fits its text and button '
      'with no hero', (tester) async {
    await pumpWelcome(tester, size: const Size(320, 568), textScale: 2.0);
    for (var i = 0; i < titles.length; i++) {
      expect(tester.takeException(), isNull, reason: titles[i]);
      expect(find.byType(WelcomeHero), findsNothing, reason: titles[i]);
      for (final target in [
        find.text(titles[i]),
        find.text(welcomeSlides[i].body),
      ]) {
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        expect(tester.getRect(target).top, greaterThanOrEqualTo(0));
      }
      final button = tester.getRect(find.byKey(const Key('welcome-next')));
      expect(button.bottom, lessThanOrEqualTo(568));
      if (i < 2) await nextSlide(tester);
    }
  });

  // @lat: [[mobile-tests#Welcome layout#The headline is the one heading]]
  testWidgets('each slide has one level-one heading, its headline', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpWelcome(tester);
    for (var i = 0; i < titles.length; i++) {
      expect(levelOneHeadings(tester), 1, reason: titles[i]);
      final node = tester.getSemantics(find.text(titles[i])).getSemanticsData();
      expect(node.headingLevel, 1, reason: titles[i]);
      if (i < 2) await nextSlide(tester);
    }
    handle.dispose();
  });

  testWidgets('both themes lay out with no exception', (tester) async {
    for (final b in Brightness.values) {
      await pumpWelcome(tester, brightness: b);
      expect(tester.takeException(), isNull);
    }
  });
}
