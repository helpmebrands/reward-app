import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../shell/router.dart';
import '../theme/nocturne_tokens.dart';
import '../widgets/screen_title.dart';

/// The not-found screen: the PWA's `NotFound`, with a way back.
class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(Space.s8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.explore_outlined, color: tokens.textSecondary),
                const SizedBox(height: Space.s3),
                ScreenTitle(
                  label: 'That screen does not exist.',
                  windowTitle: 'Not found',
                  style: text.titleMedium,
                ),
                const SizedBox(height: Space.s6),
                OutlinedButton(
                  onPressed: () => context.go(Paths.today),
                  child: const Text('Back to Today'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
