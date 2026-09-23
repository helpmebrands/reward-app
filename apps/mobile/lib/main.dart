import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'data/snapshot_store.dart';
import 'logic/app_store.dart';
import 'logic/ui_state.dart';
import 'shell/app_scope.dart';
import 'shell/router.dart';
import 'shell/ui_scope.dart';
import 'theme/theme.dart';

void main() {
  final store = AppStore(store: const SharedPreferencesSnapshotStore());
  store.load();
  runApp(RewardApp(store: store));
}

/// The app: Material on Nocturne's tokens, following the system theme, the
/// store and the ui state in scope above the router, and the router owning
/// the shell.
class RewardApp extends StatefulWidget {
  const RewardApp({
    super.key,
    required this.store,
    this.ui,
    this.initialLocation = Paths.today,
  });

  final AppStore store;

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
  );
  late final UiState _ui = widget.ui ?? UiState();
  String? _location;

  @override
  void initState() {
    super.initState();
    _router.routerDelegate.addListener(_onNavigation);
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
