import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../shell/brand_app_bar.dart';
import '../shell/router.dart';
import '../shell/width_class.dart';
import '../theme/nocturne_tokens.dart';
import '../widgets/brand_logo.dart';
import '../widgets/screen_title.dart';

/// The not-found screen: the PWA's `NotFound`, with a way back.
///
/// Reached from a link, so it carries the brand: the lockup in the bar and
/// the two-line logo above the message.
class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({super.key, this.showSettings = false});

  /// The gear in the bar, shown only when signed in.
  final bool showSettings;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: BrandAppBar(
        widthClass: WidthClass.forWidth(MediaQuery.sizeOf(context).width),
        onSettings: showSettings ? () => context.push(Paths.settings) : null,
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(Space.s8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const BrandLogo(),
                const SizedBox(height: Space.s6),
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
