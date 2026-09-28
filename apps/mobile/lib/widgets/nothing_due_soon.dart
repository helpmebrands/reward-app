import 'package:domain/domain.dart';
import 'package:flutter/material.dart';

import '../theme/nocturne_tokens.dart';

/// "Resy Dining Credit is next, $100 by Dec 31.": the open credit whose
/// window shuts first. A rolling credit's window has no end to name.
String nothingDueSoonLine(BenefitInstance next, IsoDate today) {
  final money = formatMoney(next.remainingCents);
  if (next.cycle.end == '2999-12-31') {
    return '${next.benefit.name} is open, $money, with no deadline.';
  }
  return '${next.benefit.name} is next, $money by '
      '${formatDate(next.cycle.end, today)}.';
}

/// The quiet note where Today's Use soon section would be when money is open
/// but nothing closes within 30 days: why there are no rows, the next
/// deadline, and a link to Credits, which lists every open credit.
class NothingDueSoon extends StatelessWidget {
  const NothingDueSoon({
    super.key,
    required this.next,
    required this.today,
    this.onOpenCredits,
  });

  final BenefitInstance next;
  final IsoDate today;
  final VoidCallback? onOpenCredits;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    final text = Theme.of(context).textTheme;
    final onOpenCredits = this.onOpenCredits;
    final glyph = tokens == NocturneTokens.dark
        ? tokens.background
        : tokens.surface;
    return CustomPaint(
      key: const Key('today-nothing-due-soon'),
      painter: _DashedOutline(tokens.controlBorder),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.s4,
          Space.s4,
          Space.s4,
          Space.s2,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Container(
                width: 22,
                height: 22,
                margin: const EdgeInsets.only(top: 1),
                decoration: BoxDecoration(
                  color: tokens.valueEarned,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.check, size: 15, color: glyph),
              ),
            ),
            const SizedBox(width: Space.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Nothing closes in the next 30 days',
                    style: text.titleSmall,
                  ),
                  Text(
                    nothingDueSoonLine(next, today),
                    style: text.bodySmall?.copyWith(
                      color: tokens.textSecondary,
                    ),
                  ),
                  if (onOpenCredits != null)
                    TextButton(
                      onPressed: onOpenCredits,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        alignment: Alignment.centerLeft,
                      ),
                      child: const Text('See open credits on Credits'),
                    )
                  else
                    const SizedBox(height: Space.s2),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A dashed rounded outline around the note.
class _DashedOutline extends CustomPainter {
  _DashedOutline(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(0.5),
          const Radius.circular(Radii.md),
        ),
      );
    const dash = 4.0;
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += dash * 2) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedOutline oldDelegate) => oldDelegate.color != color;
}
