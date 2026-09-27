import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/nocturne_tokens.dart';

/// The empty-state illustration: a dashed card where the first card will go,
/// a plain card behind it and a plus badge, on a soft circle.
///
/// Decorative, so it is hidden from the screen reader; the text beside it
/// says what to do. Every colour comes from the theme's tokens.
class EmptyCardSlot extends StatelessWidget {
  const EmptyCardSlot({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: EmptyCardSlotPainter(EmptyCardSlotPalette.of(tokens)),
        ),
      ),
    );
  }
}

/// The illustration's colours, picked from the tokens so each edge clears
/// 3:1 against what it is drawn on in both themes (WCAG 1.4.11).
@immutable
class EmptyCardSlotPalette {
  const EmptyCardSlotPalette({
    required this.circle,
    required this.plainFill,
    required this.plainEdge,
    required this.slotFill,
    required this.slotEdge,
    required this.badge,
    required this.badgeGlyph,
  });

  factory EmptyCardSlotPalette.of(NocturneTokens tokens) =>
      EmptyCardSlotPalette(
        circle: tokens.surfaceSunken,
        plainFill: tokens.surfaceRaised,
        plainEdge: tokens.controlBorder,
        slotFill: tokens.background,
        slotEdge: tokens.accent,
        badge: tokens.accent,
        // The filled button's foreground: the page in dark, white in light.
        badgeGlyph: tokens == NocturneTokens.dark
            ? tokens.background
            : tokens.surface,
      );

  final Color circle;
  final Color plainFill;
  final Color plainEdge;
  final Color slotFill;
  final Color slotEdge;
  final Color badge;
  final Color badgeGlyph;

  @override
  bool operator ==(Object other) =>
      other is EmptyCardSlotPalette &&
      other.circle == circle &&
      other.plainFill == plainFill &&
      other.plainEdge == plainEdge &&
      other.slotFill == slotFill &&
      other.slotEdge == slotEdge &&
      other.badge == badge &&
      other.badgeGlyph == badgeGlyph;

  @override
  int get hashCode => Object.hash(
    circle,
    plainFill,
    plainEdge,
    slotFill,
    slotEdge,
    badge,
    badgeGlyph,
  );
}

/// Paints the illustration in a unit square scaled to the canvas.
class EmptyCardSlotPainter extends CustomPainter {
  EmptyCardSlotPainter(this.palette);

  final EmptyCardSlotPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final stroke = math.max(1.5, s * 0.012);
    Paint fill(Color c) => Paint()..color = c;
    Paint line(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;

    canvas.drawCircle(Offset(s / 2, s / 2), s / 2, fill(palette.circle));

    final cardSize = Size(s * 0.56, s * 0.36);
    final radius = Radius.circular(s * 0.04);

    // The plain card, tilted behind.
    canvas.save();
    canvas.translate(s * 0.43, s * 0.43);
    canvas.rotate(-8 * math.pi / 180);
    final plain = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset.zero,
        width: cardSize.width,
        height: cardSize.height,
      ),
      radius,
    );
    canvas.drawRRect(plain, fill(palette.plainFill));
    canvas.drawRRect(plain, line(palette.plainEdge));
    canvas.restore();

    // The dashed slot in front, with a chip outline.
    final slotRect = Rect.fromCenter(
      center: Offset(s * 0.54, s * 0.57),
      width: cardSize.width,
      height: cardSize.height,
    );
    final slot = RRect.fromRectAndRadius(slotRect, radius);
    canvas.drawRRect(slot, fill(palette.slotFill));
    _dashed(canvas, Path()..addRRect(slot), line(palette.slotEdge), s * 0.035);
    final chip = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        slotRect.left + s * 0.06,
        slotRect.top + s * 0.08,
        s * 0.1,
        s * 0.075,
      ),
      Radius.circular(s * 0.015),
    );
    canvas.drawRRect(chip, line(palette.slotEdge));

    // The plus badge on the slot's top-right corner.
    final badgeCentre = slotRect.topRight;
    final badgeRadius = s * 0.1;
    canvas.drawCircle(badgeCentre, badgeRadius, fill(palette.badge));
    final arm = badgeRadius * 0.5;
    final plus = line(palette.badgeGlyph)
      ..strokeWidth = stroke * 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      badgeCentre - Offset(arm, 0),
      badgeCentre + Offset(arm, 0),
      plus,
    );
    canvas.drawLine(
      badgeCentre - Offset(0, arm),
      badgeCentre + Offset(0, arm),
      plus,
    );
  }

  void _dashed(Canvas canvas, Path path, Paint paint, double dash) {
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += dash * 2) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(EmptyCardSlotPainter oldDelegate) =>
      oldDelegate.palette != palette;
}
