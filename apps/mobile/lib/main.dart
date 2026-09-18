import 'package:flutter/material.dart';

import 'theme/theme.dart';

void main() {
  runApp(const RewardApp());
}

/// The app shell: Material on Nocturne's tokens, following the system theme.
class RewardApp extends StatelessWidget {
  const RewardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HelpMe Reward',
      theme: nocturneTheme(Brightness.light),
      darkTheme: nocturneTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const Scaffold(
        body: SafeArea(child: Center(child: Text('Today'))),
      ),
    );
  }
}
