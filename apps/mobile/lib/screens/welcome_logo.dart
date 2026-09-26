import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// The side of the icon the native splash draws, centred in the window
/// (`mobile-architecture#Native brand assets`): 120pt on the iOS launch
/// screen, 128dp in Android 12's splash. Android before 12 draws it at
/// 120dp, which this cannot tell apart, so there it grows by 8dp.
double splashIconExtent(TargetPlatform platform) =>
    platform == TargetPlatform.android ? 128 : 120;

/// How long the first launch's logo sequence takes, start to finish.
const welcomeLogoDuration = Duration(milliseconds: 900);

/// Where the icon and wordmark layers sit inside [BrandLockup]'s 224 x 32
/// artwork, measured from `assets/logo/helpmereward-logo-horz-sanstag.png`,
/// and the layers' proportions. Together the two rects cover the lockup.
abstract final class LogoLayers {
  static const Rect lockupIcon = Rect.fromLTWH(0, 0, 31.15, 31.15);
  static const Rect lockupWordmark = Rect.fromLTRB(37.55, 5.08, 224, 32);
  static const double wordmarkAspect = 844 / 122;
  static const double taglineAspect = 637 / 28;

  /// The wordmark's and tagline's width in the stacked logo.
  static const double stackedWidth = 224;
}

/// The logo in layers over the whole Welcome screen while the first
/// launch's sequence runs, driven by [progress] from 0 to 1:
///
/// 1. to 0.3, the wordmark and tagline fade in under the icon, which stays
///    where the splash drew it, forming the stacked logo;
/// 2. from 0.3 to 0.8, the icon and wordmark move onto [lockup], the header
///    lockup's rect, while the tagline fades out by 0.5;
/// 3. the screen fades its slides in over the rest.
///
/// Decoration only: the header lockup keeps the one semantics node.
class WelcomeLogoLayers extends StatelessWidget {
  const WelcomeLogoLayers({
    super.key,
    required this.progress,
    required this.lockup,
  });

  final Animation<double> progress;

  /// The header lockup's rect in this widget's coordinates, once laid out.
  final Rect? lockup;

  @override
  Widget build(BuildContext context) {
    final suffix = Theme.of(context).brightness == Brightness.dark
        ? '-dark'
        : '';
    return ExcludeSemantics(
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (context, constraints) => AnimatedBuilder(
            animation: progress,
            builder: (context, _) {
              final t = progress.value;
              final extent = splashIconExtent(defaultTargetPlatform);
              final splash = Rect.fromCenter(
                center: constraints.biggest.center(Offset.zero),
                width: extent,
                height: extent,
              );
              const width = LogoLayers.stackedWidth;
              final stackedWordmark = Rect.fromLTWH(
                splash.center.dx - width / 2,
                splash.bottom + 20,
                width,
                width / LogoLayers.wordmarkAspect,
              );
              final tagline = Rect.fromLTWH(
                stackedWordmark.left,
                stackedWordmark.bottom + 12,
                width,
                width / LogoLayers.taglineAspect,
              );

              final fadeIn = const Interval(0, 0.3).transform(t);
              final move = const Interval(
                0.3,
                0.8,
                curve: Curves.easeInOutCubic,
              ).transform(t);
              final taglineOpacity =
                  fadeIn * (1 - const Interval(0.3, 0.5).transform(t));
              final target = lockup;
              final icon = target == null
                  ? splash
                  : Rect.lerp(
                      splash,
                      LogoLayers.lockupIcon.shift(target.topLeft),
                      move,
                    )!;
              final wordmark = target == null
                  ? stackedWordmark
                  : Rect.lerp(
                      stackedWordmark,
                      LogoLayers.lockupWordmark.shift(target.topLeft),
                      move,
                    )!;

              Widget layer(String name, String asset, Rect rect, double o) =>
                  Positioned.fromRect(
                    key: Key('logo-layer-$name'),
                    rect: rect,
                    child: Opacity(
                      opacity: o,
                      child: Image.asset(
                        'assets/logo/$asset',
                        fit: BoxFit.fill,
                        excludeFromSemantics: true,
                      ),
                    ),
                  );

              return Stack(
                children: [
                  if (taglineOpacity > 0)
                    layer(
                      'tagline',
                      'helpmereward-tagline$suffix.png',
                      tagline,
                      taglineOpacity,
                    ),
                  if (fadeIn > 0)
                    layer(
                      'wordmark',
                      'helpmereward-wordmark$suffix.png',
                      wordmark,
                      fadeIn,
                    ),
                  layer('icon', 'helpmereward-icon.png', icon, 1),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
