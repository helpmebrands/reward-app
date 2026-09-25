import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reward/data/snapshot_store.dart';
import 'package:reward/logic/app_store.dart';
import 'package:reward/logic/session.dart';
import 'package:reward/logic/ui_state.dart';
import 'package:reward/main.dart';
import 'package:reward/screens/join_screen.dart';
import 'package:reward/screens/not_found_screen.dart';
import 'package:reward/theme/theme.dart';
import 'package:reward/widgets/brand_lockup.dart';
import 'package:reward/widgets/screen_title.dart';

import 'sign_in_test.dart' show FakeAuth;

/// Join household and Not found are reached from a link, often before the
/// app is set up, so they say where the person landed: the lockup in the
/// bar and the two-line logo above the message.

const logo = 'assets/logo/helpmereward-logo.png';
const logoDark = 'assets/logo/helpmereward-logo-dark.png';

Future<AppStore> emptyStore() async {
  final store = AppStore(
    store: MemorySnapshotStore(emptyAppData()),
    clock: () => DateTime(2026, 9, 16, 8),
  );
  await store.load();
  return store;
}

/// Each screen on its own, as the router builds it, signed in or out.
Future<Widget> screen(String name, {required bool signedIn}) async =>
    name == 'join'
    ? JoinScreen(
        store: await emptyStore(),
        ui: UiState(),
        code: 'ABC123',
        showSettings: signedIn,
      )
    : NotFoundScreen(showSettings: signedIn);

Future<void> pumpScreen(
  WidgetTester tester,
  String name, {
  bool signedIn = false,
  Brightness brightness = Brightness.light,
}) async {
  final child = await screen(name, signedIn: signedIn);
  tester.view.physicalSize = const Size(402, 874);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    MaterialApp(theme: nocturneTheme(brightness), home: child),
  );
  await tester.pumpAndSettle();
}

/// Through the router with a signed-in session.
Future<void> pumpSignedIn(WidgetTester tester, String location) async {
  final session = Session(
    auth: FakeAuth(signedIn: const SignedInUser(uid: 'u-1')),
    intro: MemoryIntroStore(seen: true),
  );
  await session.load();
  tester.view.physicalSize = const Size(402, 874);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    RewardApp(
      store: await emptyStore(),
      ui: UiState(),
      session: session,
      initialLocation: location,
    ),
  );
  await tester.pumpAndSettle();
}

Finder get appBar => find.byType(AppBar);

Finder get settings => find.bySemanticsLabel('Settings');

/// The logo image above the message, as opposed to the bar's lockup.
Finder get logoImage => find.byWidgetPredicate(
  (w) =>
      w is Image &&
      w.image is AssetImage &&
      [logo, logoDark].contains((w.image as AssetImage).assetName),
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

void main() {
  // @lat: [[mobile-tests#Landing screens#The lockup bar, with the gear only when signed in]]
  testWidgets('signed out: the lockup and no gear; signed in: the gear', (
    tester,
  ) async {
    for (final name in ['join', 'not found']) {
      await pumpScreen(tester, name);
      expect(appBar, findsOneWidget, reason: name);
      expect(tester.getSize(appBar).height, 64, reason: name);
      expect(
        find.descendant(of: appBar, matching: find.byType(BrandLockup)),
        findsOneWidget,
        reason: name,
      );
      expect(find.byTooltip('Back'), findsNothing, reason: name);
      expect(settings, findsNothing, reason: name);
    }
    for (final location in ['/invite/ABC123', '/nowhere']) {
      await pumpSignedIn(tester, location);
      expect(
        find.descendant(of: appBar, matching: find.byType(BrandLockup)),
        findsOneWidget,
        reason: location,
      );
      expect(settings, findsOneWidget, reason: location);
    }
  });

  // @lat: [[mobile-tests#Landing screens#The two-line logo above the message]]
  testWidgets('both draw the two-line logo above their message', (
    tester,
  ) async {
    for (final name in ['join', 'not found']) {
      for (final b in Brightness.values) {
        await pumpScreen(tester, name, brightness: b);
        expect(logoImage, findsOneWidget, reason: '$name $b');
        final image = tester.widget<Image>(logoImage);
        expect(
          (image.image as AssetImage).assetName,
          b == Brightness.dark ? logoDark : logo,
          reason: '$name $b',
        );
        expect(
          tester.getRect(logoImage).bottom,
          lessThanOrEqualTo(tester.getRect(find.byType(ScreenTitle)).top),
          reason: '$name $b',
        );
      }
    }
  });

  // @lat: [[mobile-tests#Landing screens#Still one heading, the logo is an image]]
  testWidgets('each keeps one level-one heading; the logos are images', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    for (final name in ['join', 'not found']) {
      await pumpScreen(tester, name);
      expect(levelOneHeadings(tester), 1, reason: name);
      final labels = find.bySemanticsLabel('HelpMe reward');
      expect(labels, findsNWidgets(2), reason: name);
      for (var i = 0; i < 2; i++) {
        final data = tester.getSemantics(labels.at(i)).getSemanticsData();
        expect(data.flagsCollection.isImage, isTrue, reason: name);
        expect(data.flagsCollection.isHeader, isFalse, reason: name);
      }
    }
    handle.dispose();
  });
}
