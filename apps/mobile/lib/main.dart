import 'dart:async';

import 'package:domain/domain.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'data/api_config.dart';
import 'data/claim_outbox.dart';
import 'data/firebase_auth_service.dart';
import 'data/household_api.dart';
import 'data/household_cache.dart';
import 'data/snapshot_store.dart';
import 'firebase_options.dart';
import 'logic/app_store.dart';
import 'logic/session.dart';
import 'logic/ui_state.dart';
import 'shell/app_scope.dart';
import 'shell/router.dart';
import 'shell/ui_scope.dart';
import 'theme/theme.dart';

/// Firebase first, when this build has an app for the platform; the
/// intro flag before the first frame, so the redirect never shows the wrong
/// screen for a moment.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final options = FirebaseConfig.currentPlatform;
  AuthService auth = UnconfiguredAuth();
  if (options != null) {
    await Firebase.initializeApp(options: options);
    auth = FirebaseAuthService();
  }
  final session = Session(
    auth: auth,
    intro: const SharedPreferencesIntroStore(),
  );
  await session.load();
  // With Firebase the household lives in the service tier; without it (a
  // local run on a platform with no Firebase app) the snapshot stays on
  // the device, as before sign-in existed.
  final store = options == null
      ? AppStore(store: const SharedPreferencesSnapshotStore())
      : AppStore(
          store: const SharedPreferencesSnapshotStore(),
          api: ApiClient(baseUrl: ApiConfig.baseUrl, token: auth.idToken),
          cache: const SharedPreferencesHouseholdCache(),
          outbox: const SharedPreferencesClaimOutbox(),
        );
  store.load();
  // Signing in fetches the household; signing out forgets it, so the next
  // person on this device never sees it or sends its queued claims.
  var signedIn = session.signedIn;
  session.addListener(() {
    if (session.signedIn == signedIn) return;
    signedIn = session.signedIn;
    signedIn ? store.refresh().ignore() : store.forget().ignore();
  });
  runApp(RewardApp(store: store, session: session));
}

/// The app: Material on Nocturne's tokens, following the system theme, the
/// store and the ui state in scope above the router, and the router owning
/// the shell.
class RewardApp extends StatefulWidget {
  const RewardApp({
    super.key,
    required this.store,
    this.ui,
    this.session,
    this.initialLocation = Paths.today,
  });

  final AppStore store;

  /// Sign-in and the welcome slideshow; without one there is no redirect,
  /// which is how tests reach the screens behind sign-in directly.
  final Session? session;

  /// Where the router starts; tests open a screen directly.
  final String initialLocation;

  /// The transient ui state; created here when not injected by a test.
  final UiState? ui;

  @override
  State<RewardApp> createState() => _RewardAppState();
}

class _RewardAppState extends State<RewardApp> {
  late final GoRouter _router = appRouter(
    widget.store,
    initialLocation: widget.initialLocation,
    session: widget.session,
  );
  late final UiState _ui = widget.ui ?? UiState();
  String? _location;
  AppLifecycleListener? _lifecycle;
  Timer? _retry;

  @override
  void initState() {
    super.initState();
    _router.routerDelegate.addListener(_onNavigation);
    widget.store.addListener(_onStore);
    if (widget.store.remote) {
      // Back from the background: fetch and send anything queued.
      _lifecycle = AppLifecycleListener(
        onResume: () => widget.store.refresh().ignore(),
      );
      // Offline, or with claims waiting, try again now and then; a success
      // flushes the outbox in order.
      _retry = Timer.periodic(const Duration(seconds: 30), (_) {
        final store = widget.store;
        if (store.offline || store.hasPending) store.refresh().ignore();
      });
    }
  }

  /// An edit the store could not make says why, in the snackbar.
  void _onStore() {
    final problem = widget.store.problem;
    if (problem == null) return;
    widget.store.clearProblem();
    _ui.snackbar.show(problem);
  }

  /// Moving between screens never reloads anything, so focus would stay
  /// wherever it was, often on a control that no longer exists, and a
  /// screen reader would say nothing. Each screen's heading takes focus on
  /// arrival (WCAG 2.4.3). A press on the bar or the rail is the exception:
  /// the user is still on the destination they pressed, and stays there.
  /// The first render is skipped so the app opens with focus at the top.
  void _onNavigation() {
    final location = _router.routerDelegate.currentConfiguration.uri.path;
    if (location == _location) return;
    final first = _location == null;
    _location = location;
    if (first) return;
    if (_ui.keepFocusOnDestination) {
      _ui.keepFocusOnDestination = false;
      return;
    }
    _ui.pendingHeadingFocus = location;
    // A screen already built, as a branch revisited, will not rebuild its
    // title; ask its registered node directly once the frame has settled.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _ui.pendingHeadingFocus == location) {
        _ui.pendingHeadingFocus = null;
        _ui.headings[location]?.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _retry?.cancel();
    _lifecycle?.dispose();
    widget.store.removeListener(_onStore);
    _router.routerDelegate.removeListener(_onNavigation);
    _router.dispose();
    if (widget.ui == null) _ui.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return UiScope(
      ui: _ui,
      child: AppScope(
        store: widget.store,
        // The theme mode is the settings' choice, read from the store so an
        // override takes effect the moment it is saved; System follows the
        // platform as before.
        child: ListenableBuilder(
          listenable: widget.store,
          builder: (context, _) => MaterialApp.router(
            title: 'HelpMe Reward',
            theme: nocturneTheme(Brightness.light),
            darkTheme: nocturneTheme(Brightness.dark),
            themeMode: switch (widget.store.data?.settings.theme) {
              ThemeSetting.dark => ThemeMode.dark,
              ThemeSetting.light => ThemeMode.light,
              _ => ThemeMode.system,
            },
            routerConfig: _router,
          ),
        ),
      ),
    );
  }
}
