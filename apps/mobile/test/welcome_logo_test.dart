import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reward/screens/welcome_logo.dart';
import 'package:reward/screens/welcome_screen.dart';
import 'package:reward/theme/theme.dart';
import 'package:reward/widgets/brand_lockup.dart';

/// The logo's hand-off from the native splash to the Welcome header on the
/// first launch: icon alone where the splash drew it, the stacked logo, then
/// the lockup in the header.

const window = Size(402, 874);

Future<void> pumpWelcome(
  WidgetTester tester, {
  required bool introLogo,
  bool disableAnimations = false,
}) async {
  tester.view.physicalSize = window;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: nocturneTheme(Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(disableAnimations: disableAnimations),
        child: child!,
      ),
      home: WelcomeScreen(introLogo: introLogo, onDone: () {}),
    ),
  );
}

Finder layer(String name) => find.byKey(Key('logo-layer-$name'));

double lockupOpacity(WidgetTester tester) => tester
    .widget<Opacity>(
      find
          .ancestor(
            of: find.byType(BrandLockup),
            matching: find.byType(Opacity),
          )
          .first,
    )
    .opacity;

double contentOpacity(WidgetTester tester) => tester
    .widget<FadeTransition>(
      find
          .ancestor(
            of: find.byKey(const Key('welcome-next')),
            matching: find.byType(FadeTransition),
          )
          .first,
    )
    .opacity
    .value;

void main() {
  // @lat: [[mobile-tests#Welcome logo#The first frame is the splash icon]]
  testWidgets('the first frame draws only the icon, where the splash drew it', (
    tester,
  ) async {
    for (final (platform, extent) in [
      (TargetPlatform.iOS, 120.0),
      (TargetPlatform.android, 128.0),
    ]) {
      debugDefaultTargetPlatformOverride = platform;
      expect(splashIconExtent(platform), extent);
      await pumpWelcome(tester, introLogo: true);
      expect(
        tester.getRect(layer('icon')),
        Rect.fromCenter(
          center: window.center(Offset.zero),
          width: extent,
          height: extent,
        ),
        reason: '$platform',
      );
      expect(layer('wordmark'), findsNothing);
      expect(layer('tagline'), findsNothing);
      expect(lockupOpacity(tester), 0);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    }
    debugDefaultTargetPlatformOverride = null;
  });

  // @lat: [[mobile-tests#Welcome logo#The layers land on the lockup]]
  testWidgets('the layers end on the header lockup with no tagline', (
    tester,
  ) async {
    await pumpWelcome(tester, introLogo: true);
    await tester.pump();
    // The stacked logo: all three layers.
    await tester.pump(welcomeLogoDuration * 0.3);
    expect(layer('wordmark'), findsOneWidget);
    expect(layer('tagline'), findsOneWidget);

    // The end of the move, before the slides have faded in.
    await tester.pump(welcomeLogoDuration * 0.55);
    final lockup = tester.getRect(find.byType(BrandLockup));
    final union = tester
        .getRect(layer('icon'))
        .expandToInclude(tester.getRect(layer('wordmark')));
    expect(union.left, closeTo(lockup.left, 0.5));
    expect(union.top, closeTo(lockup.top, 0.5));
    expect(union.right, closeTo(lockup.right, 0.5));
    expect(union.bottom, closeTo(lockup.bottom, 0.5));
    expect(lockup.size.width, BrandLockup.lockupSize.width);
    expect(layer('tagline'), findsNothing);

    await tester.pumpAndSettle();
    expect(layer('icon'), findsNothing);
    expect(lockupOpacity(tester), 1);
    expect(contentOpacity(tester), 1);
  });

  // @lat: [[mobile-tests#Welcome logo#It settles within a second]]
  testWidgets('the sequence settles in under a second', (tester) async {
    expect(welcomeLogoDuration, lessThan(const Duration(seconds: 1)));
    await pumpWelcome(tester, introLogo: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 999));
    expect(layer('icon'), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
    expect(lockupOpacity(tester), 1);
    expect(contentOpacity(tester), 1);
  });

  // @lat: [[mobile-tests#Welcome logo#Learn more opens on the lockup]]
  testWidgets('a replay from Learn more draws the lockup in place at once', (
    tester,
  ) async {
    await pumpWelcome(tester, introLogo: false);
    expect(layer('icon'), findsNothing);
    expect(lockupOpacity(tester), 1);
    expect(contentOpacity(tester), 1);
    expect(tester.binding.transientCallbackCount, 0);
  });

  // @lat: [[mobile-tests#Welcome logo#Reduced motion skips the sequence]]
  testWidgets('with animations off the first frame is the finished screen', (
    tester,
  ) async {
    await pumpWelcome(tester, introLogo: true, disableAnimations: true);
    expect(layer('icon'), findsNothing);
    expect(lockupOpacity(tester), 1);
    expect(contentOpacity(tester), 1);
    expect(tester.binding.transientCallbackCount, 0);
  });

  // @lat: [[mobile-tests#Welcome logo#One logo node throughout]]
  testWidgets('the semantics tree has one "HelpMe reward" node throughout', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpWelcome(tester, introLogo: true);
    expect(find.bySemanticsLabel('HelpMe reward'), findsOneWidget);
    await tester.pump();
    await tester.pump(welcomeLogoDuration * 0.5);
    expect(find.bySemanticsLabel('HelpMe reward'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('HelpMe reward'), findsOneWidget);
    handle.dispose();
  });
}
