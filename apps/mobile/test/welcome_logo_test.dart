import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:reward/data/snapshot_store.dart';
import 'package:reward/logic/app_store.dart';
import 'package:reward/logic/session.dart';
import 'package:reward/logic/ui_state.dart';
import 'package:reward/main.dart';
import 'package:reward/screens/settings_screen.dart';
import 'package:reward/screens/sign_in_screen.dart';
import 'package:reward/screens/today_screen.dart';
import 'package:reward/screens/welcome_screen.dart';
import 'package:reward/shell/logo_hand_off.dart';
import 'package:reward/widgets/brand_lockup.dart';
import 'package:reward/widgets/brand_logo.dart';

import 'sign_in_test.dart' show FakeAuth;

/// The logo's hand-off from the native splash on every cold start: icon
/// alone where the splash drew it, the stacked logo, then the lockup of
/// whichever screen the app opened on, under a page-colour cover.

const window = Size(402, 874);

/// A cold start of the whole app at [location]. With [session] the router
/// redirects as on a device; without one it opens [location] directly.
Future<void> coldStart(
  WidgetTester tester, {
  String location = '/',
  Session? session,
  bool disableAnimations = false,
  Brightness brightness = Brightness.light,
  Size size = window,
}) async {
  final store = AppStore(
    store: MemorySnapshotStore(emptyAppData()),
    clock: () => DateTime(2026, 9, 16, 8),
  );
  await store.load();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      FakeAccessibilityFeatures(disableAnimations: disableAnimations);
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    RewardApp(
      store: store,
      ui: UiState(),
      session: session,
      initialLocation: location,
      coldStart: true,
    ),
  );
}

/// A signed-out session, before or after the slideshow was seen.
Future<Session> signedOut({required bool introSeen}) async {
  final session = Session(
    auth: FakeAuth(),
    intro: MemoryIntroStore(seen: introSeen),
  );
  await session.load();
  return session;
}

Finder layer(String name) => find.byKey(Key('logo-layer-$name'));

final cover = find.byKey(const Key('logo-cover'));

double lockupOpacity(WidgetTester tester) => tester
    .widget<Opacity>(
      find
          .descendant(
            of: find.byType(BrandLockup),
            matching: find.byType(Opacity),
          )
          .first,
    )
    .opacity;

double coverOpacity(WidgetTester tester) => tester
    .widget<Opacity>(
      find.descendant(of: cover, matching: find.byType(Opacity)).first,
    )
    .opacity;

/// The screen is finished: no layers, no cover, the lockup opaque and
/// nothing animating.
void expectFinished(WidgetTester tester) {
  expect(layer('icon'), findsNothing);
  expect(layer('wordmark'), findsNothing);
  expect(cover, findsNothing);
  expect(lockupOpacity(tester), 1);
  expect(tester.binding.transientCallbackCount, 0);
}

/// Steps to the end of the move, before the cover fades, and checks icon
/// and wordmark together cover exactly the lockup's rect with no tagline.
Future<void> expectLandsOnLockup(WidgetTester tester, String reason) async {
  await tester.pump();
  // The stacked logo: all three layers.
  await tester.pump(logoHandOffDuration * 0.3);
  expect(layer('wordmark'), findsOneWidget, reason: reason);
  expect(layer('tagline'), findsOneWidget, reason: reason);

  await tester.pump(logoHandOffDuration * 0.5);
  final lockup = tester.getRect(find.byType(BrandLockup));
  final union = tester
      .getRect(layer('icon'))
      .expandToInclude(tester.getRect(layer('wordmark')));
  expect(union.left, closeTo(lockup.left, 0.5), reason: reason);
  expect(union.top, closeTo(lockup.top, 0.5), reason: reason);
  expect(union.right, closeTo(lockup.right, 0.5), reason: reason);
  expect(union.bottom, closeTo(lockup.bottom, 0.5), reason: reason);
  expect(lockup.size.width, BrandLockup.lockupSize.width, reason: reason);
  expect(layer('tagline'), findsNothing, reason: reason);
  expect(coverOpacity(tester), 1, reason: reason);

  await tester.pumpAndSettle();
  expectFinished(tester);
}

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
      await coldStart(tester);
      expect(find.byType(TodayScreen), findsOneWidget);
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
      expect(coverOpacity(tester), 1);
      await tester.pumpAndSettle();
    }
    debugDefaultTargetPlatformOverride = null;
  });

  // @lat: [[mobile-tests#Welcome logo#The icon follows the theme like the splash]]
  testWidgets('the icon layer draws the dark icon in the dark theme', (
    tester,
  ) async {
    for (final (brightness, file) in [
      (Brightness.light, 'assets/logo/helpmereward-icon.png'),
      (Brightness.dark, 'assets/logo/helpmereward-icon-dark.png'),
    ]) {
      await coldStart(tester, brightness: brightness);
      final image = tester.widget<Image>(
        find.descendant(of: layer('icon'), matching: find.byType(Image)),
      );
      expect(
        (image.image as AssetImage).assetName,
        file,
        reason: '$brightness',
      );
      await tester.pumpAndSettle();
    }
  });

  // @lat: [[mobile-tests#Welcome logo#The layers land on the lockup]]
  testWidgets('the layers end on the lockup of whichever screen opened', (
    tester,
  ) async {
    await coldStart(tester);
    await expectLandsOnLockup(tester, 'Today');

    await coldStart(tester, session: await signedOut(introSeen: false));
    expect(find.byType(WelcomeScreen), findsOneWidget);
    await expectLandsOnLockup(tester, 'Welcome');

    await coldStart(tester, location: '/invite/ABC123');
    await expectLandsOnLockup(tester, 'Join');

    await coldStart(tester, location: '/nope');
    await expectLandsOnLockup(tester, 'Not found');
  });

  // @lat: [[mobile-tests#Welcome logo#It plays once per process]]
  testWidgets('navigating or rebuilding the app does not replay it', (
    tester,
  ) async {
    await coldStart(tester);
    await tester.pumpAndSettle();
    expectFinished(tester);

    // A theme change rebuilds MaterialApp and the router's child.
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pump();
    expect(layer('icon'), findsNothing);
    expect(cover, findsNothing);

    GoRouter.of(tester.element(find.byType(TodayScreen))).go('/credits');
    await tester.pump();
    expect(layer('icon'), findsNothing);
    expect(cover, findsNothing);
    await tester.pumpAndSettle();
    expectFinished(tester);
  });

  // @lat: [[mobile-tests#Welcome logo#It settles within a second]]
  testWidgets('the sequence settles in under a second and then takes taps', (
    tester,
  ) async {
    expect(logoHandOffDuration, lessThan(const Duration(seconds: 1)));
    await coldStart(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 999));
    expectFinished(tester);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  // @lat: [[mobile-tests#Welcome logo#The cover blocks taps]]
  testWidgets('while the cover is up a tap does nothing', (tester) async {
    await coldStart(tester);
    await tester.pump();
    await tester.pump(logoHandOffDuration * 0.5);
    await tester.tap(find.byTooltip('Settings'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsNothing);
  });

  // @lat: [[mobile-tests#Welcome logo#Learn more opens on the lockup]]
  testWidgets('a replay from Learn more draws the lockup in place at once', (
    tester,
  ) async {
    await coldStart(tester, session: await signedOut(introSeen: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sign-in-learn-more')));
    await tester.pump();
    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(layer('icon'), findsNothing);
    expect(cover, findsNothing);
    expect(lockupOpacity(tester), 1);
    await tester.pumpAndSettle();
    expectFinished(tester);
  });

  // @lat: [[mobile-tests#Welcome logo#Reduced motion skips the sequence]]
  testWidgets('with animations off the first frame is the finished screen', (
    tester,
  ) async {
    await coldStart(tester, disableAnimations: true);
    expectFinished(tester);
  });

  // @lat: [[mobile-tests#Welcome logo#Too narrow for the lockup places it]]
  testWidgets('a lockup narrower than 224 is placed with no move', (
    tester,
  ) async {
    await coldStart(tester, size: const Size(260, 700));
    await tester.pump();
    expect(
      tester.getSize(find.byType(BrandLockup)).width,
      lessThan(BrandLockup.lockupSize.width),
    );
    expectFinished(tester);
  });

  // @lat: [[mobile-tests#Welcome logo#With no logo the layers fade in place]]
  testWidgets('with no lockup on screen the layers fade out where they are', (
    tester,
  ) async {
    await coldStart(tester, location: '/settings');
    expect(find.byType(SettingsScreen), findsOneWidget);
    final splash = tester.getRect(layer('icon'));
    await tester.pump();
    await tester.pump(logoHandOffDuration * 0.5);
    expect(tester.getRect(layer('icon')), splash);
    await tester.pumpAndSettle();
    expect(layer('icon'), findsNothing);
    expect(cover, findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
  });

  // @lat: [[mobile-tests#Welcome logo#One logo node throughout]]
  testWidgets('the semantics tree has one "HelpMe reward" node throughout', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await coldStart(tester);
    expect(find.bySemanticsLabel('HelpMe reward'), findsOneWidget);
    await tester.pump();
    await tester.pump(logoHandOffDuration * 0.5);
    expect(find.bySemanticsLabel('HelpMe reward'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('HelpMe reward'), findsOneWidget);
    handle.dispose();
  });

  group('Sign in', () {
    /// Where each layer sits in `helpmereward-logo-vertical.png`, 480 x 511,
    /// measured from its alpha: icon, two-line wordmark, tagline.
    const artwork = Size(480, 511);
    const parts = {
      'icon': Rect.fromLTRB(130, 0, 351, 220),
      'wordmark': Rect.fromLTRB(74, 235, 405, 444),
      'tagline': Rect.fromLTRB(0, 490, 480, 511),
    };

    Future<void> coldStartSignIn(
      WidgetTester tester, {
      Brightness brightness = Brightness.light,
      bool disableAnimations = false,
    }) async {
      await coldStart(
        tester,
        session: await signedOut(introSeen: true),
        brightness: brightness,
        disableAnimations: disableAnimations,
      );
      expect(find.byType(SignInScreen), findsOneWidget);
    }

    double logoOpacity(WidgetTester tester) => tester
        .widget<Opacity>(
          find
              .descendant(
                of: find.byType(BrandLogo),
                matching: find.byType(Opacity),
              )
              .first,
        )
        .opacity;

    String asset(WidgetTester tester, String name) =>
        (tester
                    .widget<Image>(
                      find.descendant(
                        of: layer(name),
                        matching: find.byType(Image),
                      ),
                    )
                    .image
                as AssetImage)
            .assetName;

    // @lat: [[mobile-tests#Welcome logo#Sign in starts from the splash icon]]
    testWidgets('a signed-out cold start draws only the icon at first', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await coldStartSignIn(tester);
      expect(
        tester.getRect(layer('icon')),
        Rect.fromCenter(
          center: window.center(Offset.zero),
          width: 120,
          height: 120,
        ),
      );
      expect(layer('wordmark'), findsNothing);
      expect(layer('tagline'), findsNothing);
      expect(logoOpacity(tester), 0);
      await tester.pumpAndSettle();
      debugDefaultTargetPlatformOverride = null;
    });

    // @lat: [[mobile-tests#Welcome logo#Sign in lands on the stacked logo]]
    testWidgets('the three layers end on their parts of the stacked logo', (
      tester,
    ) async {
      await coldStartSignIn(tester);
      await tester.pump();
      await tester.pump(logoHandOffDuration * 0.3);
      expect(layer('tagline'), findsOneWidget);

      await tester.pump(logoHandOffDuration * 0.5);
      final logo = tester.getRect(find.byType(BrandLogo));
      final scale = math.min(
        logo.width / artwork.width,
        logo.height / artwork.height,
      );
      final origin =
          logo.center -
          Offset(artwork.width * scale / 2, artwork.height * scale / 2);
      for (final MapEntry(key: name, value: part) in parts.entries) {
        final expected = Rect.fromLTRB(
          origin.dx + part.left * scale,
          origin.dy + part.top * scale,
          origin.dx + part.right * scale,
          origin.dy + part.bottom * scale,
        );
        final actual = tester.getRect(layer(name));
        expect(actual.left, closeTo(expected.left, 0.5), reason: name);
        expect(actual.top, closeTo(expected.top, 0.5), reason: name);
        expect(actual.right, closeTo(expected.right, 0.5), reason: name);
        expect(actual.bottom, closeTo(expected.bottom, 0.5), reason: name);
      }
      expect(asset(tester, 'wordmark'), contains('wordmark-stacked'));

      await tester.pumpAndSettle();
      expect(layer('icon'), findsNothing);
      expect(cover, findsNothing);
      expect(logoOpacity(tester), 1);
    });

    // @lat: [[mobile-tests#Welcome logo#The stacked layers follow the theme]]
    testWidgets('the dark theme draws the dark layers', (tester) async {
      for (final (brightness, suffix) in [
        (Brightness.light, ''),
        (Brightness.dark, '-dark'),
      ]) {
        await coldStartSignIn(tester, brightness: brightness);
        await tester.pump();
        await tester.pump(logoHandOffDuration * 0.5);
        expect(
          asset(tester, 'icon'),
          'assets/logo/helpmereward-icon$suffix.png',
        );
        expect(
          asset(tester, 'wordmark'),
          'assets/logo/helpmereward-wordmark-stacked$suffix.png',
        );
        expect(
          asset(tester, 'tagline'),
          'assets/logo/helpmereward-tagline$suffix.png',
        );
        await tester.pumpAndSettle();
      }
    });

    // @lat: [[mobile-tests#Welcome logo#Sign in settles or skips]]
    testWidgets('it settles within a second, and reduced motion skips it', (
      tester,
    ) async {
      await coldStartSignIn(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 999));
      expect(layer('icon'), findsNothing);
      expect(logoOpacity(tester), 1);
      expect(tester.binding.transientCallbackCount, 0);

      await coldStartSignIn(tester, disableAnimations: true);
      expect(layer('icon'), findsNothing);
      expect(cover, findsNothing);
      expect(logoOpacity(tester), 1);
      expect(tester.binding.transientCallbackCount, 0);
    });

    // @lat: [[mobile-tests#Welcome logo#Sign in keeps one logo node]]
    testWidgets('one "HelpMe reward" node throughout', (tester) async {
      final handle = tester.ensureSemantics();
      await coldStartSignIn(tester);
      expect(find.bySemanticsLabel('HelpMe reward'), findsOneWidget);
      await tester.pump();
      await tester.pump(logoHandOffDuration * 0.5);
      expect(find.bySemanticsLabel('HelpMe reward'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('HelpMe reward'), findsOneWidget);
      handle.dispose();
    });
  });
}
