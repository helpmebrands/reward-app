import 'package:domain/domain.dart';
import 'package:flutter/material.dart';

import '../theme/nocturne_tokens.dart';

/// Which of the five tones a row is drawn in. Every status maps to one, so a
/// row's colour is always a token and never a hex.
enum RowTone { soon, available, locked, captured, missed }

RowTone toneFor(BenefitStatus status) => switch (status) {
  BenefitStatus.useSoon => RowTone.soon,
  BenefitStatus.available => RowTone.available,
  BenefitStatus.locked => RowTone.locked,
  BenefitStatus.captured || BenefitStatus.manual => RowTone.captured,
  BenefitStatus.missed => RowTone.missed,
};

/// One credit in a list: its name, its cadence, window and holder, and the
/// money at stake with the deadline. The PWA's row, without the swipe, which
/// arrives with the actions.
class CreditRow extends StatelessWidget {
  const CreditRow({super.key, required this.instance, this.showCard = false});

  final BenefitInstance instance;

  /// Shows the holder in the subtitle. Off inside a per-card group.
  final bool showCard;

  RowTone get tone => toneFor(instance.status);

  String get subtitle {
    final parts = [
      cadenceLabel(instance.benefit.cadence),
      instance.cycle.label,
    ];
    // The holder, not the full card name: two identical Platinums differ only
    // by who holds them.
    if (showCard) {
      parts.add(
        instance.card.holder.isNotEmpty
            ? instance.card.holder
            : cardLabel(instance.card),
      );
    }
    return parts.join(' · ');
  }

  String get deadline {
    final status = instance.status;
    if (status == BenefitStatus.manual) return 'No deadline';
    if (status == BenefitStatus.captured) return 'Captured';
    if (instance.daysRemaining < 0) return 'Expired';
    return formatDaysRemaining(instance.daysRemaining);
  }

  String get amount => formatMoney(
    instance.status == BenefitStatus.captured
        ? instance.claimedCents
        : instance.remainingCents,
  );

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    final palette = switch (tone) {
      RowTone.soon => tokens.soon,
      RowTone.available => tokens.available,
      RowTone.locked => tokens.locked,
      RowTone.captured => tokens.captured,
      RowTone.missed => tokens.missed,
    };
    final text = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      label: instance.status == BenefitStatus.locked
          ? statusLabel(BenefitStatus.locked)
          : null,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(
          horizontal: Space.s4,
          vertical: Space.s3,
        ),
        decoration: BoxDecoration(
          color: palette.ground,
          borderRadius: const BorderRadius.all(Radius.circular(Radii.md)),
          border: Border.all(color: palette.line),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The name wraps rather than ellipsises: at a large text
                  // size a truncated name loses the one thing the row is for.
                  Text(
                    instance.benefit.name,
                    style: text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: text.bodySmall?.copyWith(
                      color: tokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Space.s3),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  amount,
                  style: text.bodyMedium?.copyWith(color: palette.foreground),
                ),
                Text(
                  deadline,
                  style: text.bodySmall?.copyWith(color: tokens.textSecondary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
