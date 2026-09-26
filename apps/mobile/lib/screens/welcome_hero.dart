import 'package:flutter/material.dart';

import '../theme/nocturne_tokens.dart';

/// The picture at the top of a welcome slide, showing the product's own
/// widgets straight on the page, with no panel behind them.
///
/// The child is laid out at [designWidth] and text scale 1.0 whatever the
/// screen, tilted a few degrees with a slight perspective, and clipped at the
/// hero's bounds so its rows run off the edges. It is decoration: nothing in
/// it can be tapped or reaches the semantics tree, since the slide's headline
/// and body carry the message.
class WelcomeHero extends StatelessWidget {
  const WelcomeHero({super.key, required this.child});

  static const double designWidth = 360;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: MediaQuery.withNoTextScaling(
            child: Padding(
              padding: const EdgeInsets.only(top: Space.s12),
              child: OverflowBox(
                alignment: Alignment.topCenter,
                minWidth: designWidth,
                maxWidth: designWidth,
                minHeight: 0,
                maxHeight: double.infinity,
                child: Transform(
                  alignment: Alignment.topCenter,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.0008)
                    ..rotateX(0.12)
                    ..rotateZ(-0.07),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
