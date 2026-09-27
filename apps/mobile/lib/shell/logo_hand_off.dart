import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../widgets/brand_lockup.dart';
import '../widgets/logo_target.dart';

/// The side of the icon the native splash draws, centred in the window
/// (`mobile-architecture#Native brand assets`): 120pt on the iOS launch
/// screen, 128dp in Android 12's splash. Android before 12 draws it at
/// 120dp, which this cannot tell apart, so there it grows by 8dp.
double splashIconExtent(TargetPlatform platform) =>
    platform == TargetPlatform.android ? 128 : 120;

/// How long the cold start's logo sequence takes, start to finish.
const logoHandOffDuration = Duration(milliseconds: 900);

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

  /// `BrandLogo.stacked`'s artwork, `helpmereward-logo-vertical.png`, and
  /// where its icon, two-line wordmark (`helpmereward-wordmark-stacked`)
  /// and tagline sit in it, measured from its alpha.
  static const Size vertical = Size(480, 511);
  static const Rect verticalIcon = Rect.fromLTRB(130, 0, 351, 220);
  static const Rect verticalWordmark = Rect.fromLTRB(74, 235, 405, 444);
  static const Rect verticalTagline = Rect.fromLTRB(0, 490, 480, 511);
}

/// Where the hand-off lands: a target's rect and the logo it draws.
typedef LogoLanding = ({Rect rect, LogoShape shape});

/// The logo's hand-off from the native splash, played once per process
/// over the first screen, [child]: the layers ([LogoHandOffLayers]) fly to
/// whichever [LogoTarget] that screen mounted, over a page-colour cover
/// that hides the screen and ignores taps until it fades.
///
/// Without [play], and with reduced motion, it is just [child] and the
/// targets are drawn at once.
class LogoHandOff extends StatefulWidget {
  const LogoHandOff({super.key, required this.play, required this.child});

  /// True for the first frame after `main`, when the native splash showed.
  final bool play;

  final Widget child;

  @override
  State<LogoHandOff> createState() => _LogoHandOffState();
}

class _LogoHandOffState extends State<LogoHandOff>
    with SingleTickerProviderStateMixin {
  late final _targets = LogoTargets(widget.play);
  final _stackKey = GlobalKey();
  AnimationController? _progress;
  LogoLanding? _target;
  bool _looked = false;

  bool get _playing => _targets.hidden;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_playing || _progress != null) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      // Before the first build, so nothing listens yet.
      _targets.hidden = false;
      return;
    }
    final progress = _progress =
        AnimationController(vsync: this, duration: logoHandOffDuration)
          ..addListener(_onTick)
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) {
              setState(() => _targets.hidden = false);
            }
          });
    // The target's rect is known after the first layout.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _measure();
      // Too narrow for the icon beside the wordmark: place it with no move.
      if (target != null && _tooNarrow(target)) {
        progress.value = 1;
        return;
      }
      setState(() => _target = target);
      progress.forward();
    });
  }

  /// A screen still loading at the first frame may mount its logo later:
  /// look once more when the move starts, else the layers fade in place.
  void _onTick() {
    if (_target != null || _looked || _progress!.value < 0.3) return;
    _looked = true;
    final target = _measure();
    if (target != null && !_tooNarrow(target)) {
      setState(() => _target = target);
    }
  }

  /// A lockup given less than its width shows the wordmark alone.
  bool _tooNarrow(LogoLanding target) =>
      target.shape == LogoShape.lockup &&
      target.rect.width < BrandLockup.lockupSize.width;

  LogoLanding? _measure() {
    final target = _targets.laidOut;
    final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (target == null || stack == null) return null;
    final box = target.box;
    return (
      rect: box.localToGlobal(Offset.zero, ancestor: stack) & box.size,
      shape: target.shape,
    );
  }

  @override
  void dispose() {
    _progress?.dispose();
    _targets.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    final playing = _playing && progress != null;
    return LogoTargetsScope(
      targets: _targets,
      child: Stack(
        key: _stackKey,
        fit: StackFit.expand,
        children: [
          AbsorbPointer(absorbing: playing, child: widget.child),
          if (playing) ...[
            Positioned.fill(
              key: const Key('logo-cover'),
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: progress,
                  builder: (context, _) => Opacity(
                    opacity:
                        1 - const Interval(0.8, 1).transform(progress.value),
                    child: ColoredBox(
                      color: Theme.of(context).scaffoldBackgroundColor,
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: LogoHandOffLayers(progress: progress, target: _target),
            ),
          ],
        ],
      ),
    );
  }
}

/// The logo in layers over the whole window while the cold start's
/// sequence runs, driven by [progress] from 0 to 1:
///
/// 1. to 0.3, the wordmark and tagline fade in under the icon, which stays
///    where the splash drew it, forming the stacked logo;
/// 2. from 0.3 to 0.8, the icon and wordmark move onto [target], the
///    lockup's rect, while the tagline fades out by 0.5; onto a stacked
///    logo the stacked layers form its artwork around the icon and the
///    three move and scale onto their parts of it; with no target they
///    fade out where they are instead;
/// 3. the cover fades over the rest, uncovering the screen.
///
/// Decoration only: the target keeps the one semantics node.
class LogoHandOffLayers extends StatelessWidget {
  const LogoHandOffLayers({
    super.key,
    required this.progress,
    required this.target,
  });

  final Animation<double> progress;

  /// The target's rect in this widget's coordinates, once laid out, and
  /// its shape.
  final LogoLanding? target;

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
              final target = this.target?.rect;
              final stacked = this.target?.shape == LogoShape.stacked;
              // With nowhere to land, the move is a fade where they stand.
              final shown = target == null
                  ? 1 - const Interval(0.3, 0.8).transform(t)
                  : 1.0;
              final taglineOpacity = stacked
                  ? fadeIn
                  : fadeIn * (1 - const Interval(0.3, 0.5).transform(t));
              final Rect icon;
              final Rect wordmark;
              var taglineRect = tagline;
              if (target == null) {
                icon = splash;
                wordmark = stackedWordmark;
              } else if (stacked) {
                // The vertical artwork, first scaled so its icon is the
                // splash icon, then fitted to the target as the image is.
                const art = LogoLayers.vertical;
                final formed = extent / LogoLayers.verticalIcon.width;
                final formedAt =
                    splash.topLeft - LogoLayers.verticalIcon.topLeft * formed;
                final landed = math.min(
                  target.width / art.width,
                  target.height / art.height,
                );
                final landedAt =
                    target.center -
                    Offset(art.width * landed / 2, art.height * landed / 2);
                Rect at(Rect part, double scale, Offset origin) =>
                    Rect.fromLTRB(
                      origin.dx + part.left * scale,
                      origin.dy + part.top * scale,
                      origin.dx + part.right * scale,
                      origin.dy + part.bottom * scale,
                    );
                Rect flight(Rect from, Rect part) =>
                    Rect.lerp(from, at(part, landed, landedAt), move)!;
                icon = flight(splash, LogoLayers.verticalIcon);
                wordmark = flight(
                  at(LogoLayers.verticalWordmark, formed, formedAt),
                  LogoLayers.verticalWordmark,
                );
                taglineRect = flight(
                  at(LogoLayers.verticalTagline, formed, formedAt),
                  LogoLayers.verticalTagline,
                );
              } else {
                icon = Rect.lerp(
                  splash,
                  LogoLayers.lockupIcon.shift(target.topLeft),
                  move,
                )!;
                wordmark = Rect.lerp(
                  stackedWordmark,
                  LogoLayers.lockupWordmark.shift(target.topLeft),
                  move,
                )!;
              }

              Widget layer(String name, String asset, Rect rect, double o) =>
                  Positioned.fromRect(
                    key: Key('logo-layer-$name'),
                    rect: rect,
                    child: Opacity(
                      opacity: o * shown,
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
                      taglineRect,
                      taglineOpacity,
                    ),
                  if (fadeIn > 0)
                    layer(
                      'wordmark',
                      stacked
                          ? 'helpmereward-wordmark-stacked$suffix.png'
                          : 'helpmereward-wordmark$suffix.png',
                      wordmark,
                      fadeIn,
                    ),
                  layer('icon', 'helpmereward-icon$suffix.png', icon, 1),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
