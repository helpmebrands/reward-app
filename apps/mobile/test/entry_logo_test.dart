import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reward/logic/session.dart';
import 'package:reward/screens/sign_in_screen.dart';
import 'package:reward/screens/welcome_screen.dart';
import 'package:reward/theme/theme.dart';

/// Welcome and Sign in carry the stacked brand logo, centred, in place of
/// the generic piggy bank.

const stacked = 'assets/logo/helpmereward-logo-vertical.png';
const stackedDark = 'assets/logo/helpmereward-logo-vertical-dark.png';

Widget screen(String name) => name == 'welcome'
    ? WelcomeScreen(onDone: () {})
    : SignInScreen(auth: UnconfiguredAuth(), onLearnMore: () {});

Future<void> pumpScreen(
  WidgetTester tester,
  String name, {
  Brightness brightness = Brightness.light,
  Size size = const Size(402, 874),
  double textScale = 1.0,
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
      home: screen(name),
    ),
  );
  await tester.pumpAndSettle();
}

Finder get logo => find.byWidgetPredicate(
  (w) =>
      w is Image &&
      w.image is AssetImage &&
      [stacked, stackedDark].contains((w.image as AssetImage).assetName),
);

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

const screens = ['welcome', 'sign in'];

void main() {
  // @lat: [[mobile-tests#Entry logo#The stacked logo replaces the piggy bank]]
  testWidgets('both draw the stacked logo, centred, and no piggy bank', (
    tester,
  ) async {
    for (final name in screens) {
      for (final b in Brightness.values) {
        await pumpScreen(tester, name, brightness: b);
        expect(find.byIcon(Icons.savings_outlined), findsNothing);
        expect(logo, findsOneWidget, reason: '$name $b');
        expect(
          (tester.widget<Image>(logo).image as AssetImage).assetName,
          b == Brightness.dark ? stackedDark : stacked,
          reason: '$name $b',
        );
        expect(tester.getCenter(logo).dx, closeTo(201, 0.5));
      }
    }
  });

  // @lat: [[mobile-tests#Entry logo#The buttons stay reachable on a small phone at 2.0]]
  testWidgets('at 320 x 568 and text scale 2.0 the buttons can be reached', (
    tester,
  ) async {
    for (final name in screens) {
      await pumpScreen(
        tester,
        name,
        size: const Size(320, 568),
        textScale: 2.0,
      );
      expect(tester.takeException(), isNull, reason: name);
      final button = find.byKey(
        Key(name == 'welcome' ? 'welcome-next' : 'sign-in-google'),
      );
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      final rect = tester.getRect(button);
      expect(rect.top, greaterThanOrEqualTo(0), reason: name);
      expect(rect.bottom, lessThanOrEqualTo(568), reason: name);
    }
  });

  // @lat: [[mobile-tests#Entry logo#One heading, the logo is an image]]
  testWidgets('each keeps one level-one heading; the logo is an image', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    for (final name in screens) {
      await pumpScreen(tester, name);
      expect(levelOneHeadings(tester), 1, reason: name);
      final node = tester
          .getSemantics(find.bySemanticsLabel('HelpMe reward'))
          .getSemanticsData();
      expect(node.flagsCollection.isImage, isTrue, reason: name);
      expect(node.flagsCollection.isHeader, isFalse, reason: name);
    }
    handle.dispose();
  });
}
