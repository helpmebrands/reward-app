import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'data/snapshot_store.dart';
import 'logic/app_store.dart';
import 'shell/app_scope.dart';
import 'shell/router.dart';
import 'theme/theme.dart';

void main() {
  final store = AppStore(store: const SharedPreferencesSnapshotStore());
  store.load();
  runApp(RewardApp(store: store));
}

/// The app: Material on Nocturne's tokens, following the system theme, the
/// store in scope above the router, and the router owning the shell.
class RewardApp extends StatefulWidget {
  const RewardApp({super.key, required this.store});

  final AppStore store;

  @override
  State<RewardApp> createState() => _RewardAppState();
}

class _RewardAppState extends State<RewardApp> {
  late final GoRouter _router = appRouter(widget.store);

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      store: widget.store,
      child: MaterialApp.router(
        title: 'HelpMe Reward',
        theme: nocturneTheme(Brightness.light),
        darkTheme: nocturneTheme(Brightness.dark),
        themeMode: ThemeMode.system,
        routerConfig: _router,
      ),
    );
  }
}
