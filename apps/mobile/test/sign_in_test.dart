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

/// The welcome slideshow and required sign-in, over a fake auth, through the
/// router's redirect: the three launch states, Skip, Learn more, sign-in and
/// sign-out.

class FakeAuth implements AuthService {
  FakeAuth({SignedInUser? signedIn}) : user = ValueNotifier(signedIn);

  @override
  final ValueNotifier<SignedInUser?> user;
  final List<String> calls = [];

  @override
  Future<void> signInWithGoogle() async {
    calls.add('google');
    user.value = const SignedInUser(uid: 'u-1', email: 'jim@example.com');
  }

  @override
  Future<void> signInWithApple() async {
    calls.add('apple');
    user.value = const SignedInUser(uid: 'u-1');
  }

  @override
  Future<void> signOut() async {
    calls.add('sign out');
    user.value = null;
  }

  @override
  Future<String?> idToken() async => user.value == null ? null : 'token';
}

Future<({Session session, FakeAuth auth, MemoryIntroStore intro})> launch(
  WidgetTester tester, {
  bool introSeen = false,
  bool signedIn = false,
}) async {
  final auth = FakeAuth(
    signedIn: signedIn ? const SignedInUser(uid: 'u-1') : null,
  );
  final intro = MemoryIntroStore(seen: introSeen);
  final session = Session(auth: auth, intro: intro);
  await session.load();
  final store = AppStore(
    store: MemorySnapshotStore(emptyAppData()),
    clock: () => DateTime(2026, 9, 16, 8),
  );
  await store.load();
  tester.view.physicalSize = const Size(402, 874);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    RewardApp(store: store, ui: UiState(), session: session),
  );
  await tester.pumpAndSettle();
  return (session: session, auth: auth, intro: intro);
}

Finder key(String k) => find.byKey(Key(k));

void main() {
  // @lat: [[mobile-tests#Sign-in#First launch shows the slideshow]]
  testWidgets('first launch shows the slideshow; Skip leads to sign-in', (
    tester,
  ) async {
    final app = await launch(tester);
    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(app.intro.seen, isFalse);
    // The first launch plays the logo's hand-off from the splash.
    expect(
      tester.widget<WelcomeScreen>(find.byType(WelcomeScreen)).introLogo,
      isTrue,
    );

    await tester.tap(key('welcome-skip'));
    await tester.pumpAndSettle();
    expect(find.byType(SignInScreen), findsOneWidget);
    expect(app.intro.seen, isTrue);
  });

  // @lat: [[mobile-tests#Sign-in#Finishing the slideshow leads to sign-in]]
  testWidgets('finishing the slideshow leads to sign-in and sets introSeen', (
    tester,
  ) async {
    final app = await launch(tester);
    while (find.text('Get started').evaluate().isEmpty) {
      await tester.tap(key('welcome-next'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    expect(find.byType(SignInScreen), findsOneWidget);
    expect(app.intro.seen, isTrue);
  });

  // @lat: [[mobile-tests#Sign-in#A returning signed-out launch goes to sign-in]]
  testWidgets('a later signed-out launch goes straight to sign-in; Learn more '
      'replays the slideshow', (tester) async {
    await launch(tester, introSeen: true);
    expect(find.byType(SignInScreen), findsOneWidget);
    expect(find.byType(WelcomeScreen), findsNothing);

    await tester.tap(key('sign-in-learn-more'));
    await tester.pumpAndSettle();
    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(
      tester.widget<WelcomeScreen>(find.byType(WelcomeScreen)).introLogo,
      isFalse,
    );
    await tester.tap(key('welcome-skip'));
    await tester.pumpAndSettle();
    expect(find.byType(SignInScreen), findsOneWidget);
  });

  // @lat: [[mobile-tests#Sign-in#A signed-in launch opens Today]]
  testWidgets('a signed-in launch opens Today', (tester) async {
    await launch(tester, introSeen: true, signedIn: true);
    expect(find.byType(TodayScreen), findsOneWidget);
    expect(find.byType(SignInScreen), findsNothing);
  });

  // @lat: [[mobile-tests#Sign-in#Signing in opens Today]]
  testWidgets('Continue with Google or Apple signs in and opens Today', (
    tester,
  ) async {
    for (final (button, call) in [
      ('sign-in-google', 'google'),
      ('sign-in-apple', 'apple'),
    ]) {
      final app = await launch(tester, introSeen: true);
      await tester.tap(key(button));
      await tester.pumpAndSettle();
      expect(app.auth.calls, [call]);
      expect(find.byType(TodayScreen), findsOneWidget);
    }
  });

  // @lat: [[mobile-tests#Sign-in#Signing out returns to sign-in]]
  testWidgets('signing out returns to sign-in without the slideshow', (
    tester,
  ) async {
    final app = await launch(tester, introSeen: true, signedIn: true);
    GoRouter.of(tester.element(find.byType(TodayScreen))).go('/settings');
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    await tester.ensureVisible(key('sign-out'));
    await tester.pumpAndSettle();
    await tester.tap(key('sign-out'));
    await tester.pumpAndSettle();
    expect(app.auth.calls, ['sign out']);
    expect(find.byType(SignInScreen), findsOneWidget);
    expect(find.byType(WelcomeScreen), findsNothing);
  });

  // @lat: [[mobile-tests#Sign-in#A failed sign-in says so]]
  testWidgets('a sign-in that fails shows why and stays', (tester) async {
    final auth = UnconfiguredAuth();
    final session = Session(auth: auth, intro: MemoryIntroStore(seen: true));
    await session.load();
    final store = AppStore(store: MemorySnapshotStore(emptyAppData()));
    await store.load();
    await tester.pumpWidget(
      RewardApp(store: store, ui: UiState(), session: session),
    );
    await tester.pumpAndSettle();
    await tester.tap(key('sign-in-google'));
    await tester.pumpAndSettle();
    expect(find.byType(SignInScreen), findsOneWidget);
    expect(find.textContaining('not set up'), findsOneWidget);
  });
}
