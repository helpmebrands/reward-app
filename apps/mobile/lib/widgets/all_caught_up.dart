import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/nocturne_tokens.dart';

/// The all-caught-up illustration: two stacked cards on a soft circle, a
/// check badge in the earned colour and three small accent ticks.
///
/// Decorative, so it is hidden from the screen reader; the heading beside it
/// says the credits are used. The badge pops once as the widget first
/// appears, unless the platform asks for reduced motion.
class AllCaughtUp extends StatefulWidget {
  const AllCaughtUp({super.key, required this.size});

  final double size;

  @override
  State<AllCaughtUp> createState() => _AllCaughtUpState();
}

class _AllCaughtUpState extends State<AllCaughtUp>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  // The mockup's overshooting ease, cubic-bezier(.2, 1.4, .4, 1).
  late final Animation<double> _scale = Tween(
    begin: 0.4,
    end: 1.0,
  ).animate(CurvedAnimation(parent: _pop, curve: const Cubic(.2, 1.4, .4, 1)));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.of(context).disableAnimations) {
      _pop.value = 1;
    } else {
      _pop.forward();
    }
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _scale,
          builder: (context, _) => CustomPaint(
            painter: AllCaughtUpPainter(
              AllCaughtUpPalette.of(tokens),
              badgeScale: _scale.value,
            ),
          ),
        ),
      ),
    );
  }
}

/// The illustration's colours, picked from the tokens so each edge clears
/// 3:1 against what it is drawn on in both themes (WCAG 1.4.11).
@immutable
class AllCaughtUpPalette {
  const AllCaughtUpPalette({
    required this.circle,
    required this.cardFill,
    required this.cardEdge,
    required this.ticks,
    required this.badge,
    required this.badgeGlyph,
  });

  factory AllCaughtUpPalette.of(NocturneTokens tokens) => AllCaughtUpPalette(
    circle: tokens.surfaceSunken,
    cardFill: tokens.surfaceRaised,
    cardEdge: tokens.controlBorder,
    ticks: tokens.accent,
    badge: tokens.valueEarned,
    // The filled button's foreground: the page in dark, white in light.
    badgeGlyph: tokens == NocturneTokens.dark
        ? tokens.background
        : tokens.surface,
  );

  final Color circle;
  final Color cardFill;
  final Color cardEdge;
  final Color ticks;
  final Color badge;
  final Color badgeGlyph;

  @override
  bool operator ==(Object other) =>
      other is AllCaughtUpPalette &&
      other.circle == circle &&
      other.cardFill == cardFill &&
      other.cardEdge == cardEdge &&
      other.ticks == ticks &&
      other.badge == badge &&
      other.badgeGlyph == badgeGlyph;

  @override
  int get hashCode =>
      Object.hash(circle, cardFill, cardEdge, ticks, badge, badgeGlyph);
}

/// Paints the illustration on the mockup's 160-unit grid, scaled to the
/// canvas. [badgeScale] sizes the check badge about its centre.
class AllCaughtUpPainter extends CustomPainter {
  AllCaughtUpPainter(this.palette, {this.badgeScale = 1});

  final AllCaughtUpPalette palette;
  final double badgeScale;

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.shortestSide / 160;
    Offset at(double x, double y) => Offset(x * u, y * u);
    Paint fill(Color c) => Paint()..color = c;
    Paint line(Color c, double width) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = width * u
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawCircle(at(80, 80), 74 * u, fill(palette.circle));

    final radius = Radius.circular(8 * u);
    void card(Rect rect) {
      final r = RRect.fromRectAndRadius(rect, radius);
      canvas.drawRRect(r, fill(palette.cardFill));
      canvas.drawRRect(r, line(palette.cardEdge, 2));
    }

    // The card behind, tilted.
    canvas.save();
    canvas.translate(80 * u, 80 * u);
    canvas.rotate(-10 * math.pi / 180);
    canvas.translate(-80 * u, -80 * u);
    card(Rect.fromLTWH(30 * u, 46 * u, 92 * u, 58 * u));
    canvas.restore();

    // The card in front, with a chip and a number line.
    card(Rect.fromLTWH(38 * u, 58 * u, 92 * u, 58 * u));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(48 * u, 70 * u, 16 * u, 12 * u),
        Radius.circular(2 * u),
      ),
      line(palette.cardEdge, 2),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(48 * u, 96 * u, 40 * u, 5 * u),
        Radius.circular(2.5 * u),
      ),
      fill(palette.cardEdge),
    );

    // Three accent ticks off the top-right corner.
    final ticks = line(palette.ticks, 3);
    canvas.drawLine(at(128, 36), at(134, 28), ticks);
    canvas.drawLine(at(138, 50), at(148, 48), ticks);
    canvas.drawLine(at(116, 28), at(116, 19), ticks);

    // The check badge, scaled about its centre.
    canvas.save();
    canvas.translate(118 * u, 110 * u);
    canvas.scale(badgeScale);
    canvas.translate(-118 * u, -110 * u);
    canvas.drawCircle(at(118, 110), 20 * u, fill(palette.badge));
    canvas.drawPath(
      Path()
        ..moveTo(109 * u, 110.5 * u)
        ..lineTo(115 * u, 116.5 * u)
        ..lineTo(127 * u, 103.5 * u),
      line(palette.badgeGlyph, 4),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(AllCaughtUpPainter oldDelegate) =>
      oldDelegate.palette != palette || oldDelegate.badgeScale != badgeScale;
}
