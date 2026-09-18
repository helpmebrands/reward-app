import 'package:flutter/material.dart';

import 'data/snapshot_store.dart';
import 'logic/app_store.dart';
import 'screens/today_screen.dart';
import 'theme/theme.dart';

void main() {
  final store = AppStore(store: const SharedPreferencesSnapshotStore());
  store.load();
  runApp(RewardApp(store: store));
}

/// The app shell: Material on Nocturne's tokens, following the system theme,
/// with the store handed down to the screens.
class RewardApp extends StatelessWidget {
  const RewardApp({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HelpMe Reward',
      theme: nocturneTheme(Brightness.light),
      darkTheme: nocturneTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: Scaffold(
        body: SafeArea(child: TodayScreen(store: store)),
      ),
    );
  }
}
