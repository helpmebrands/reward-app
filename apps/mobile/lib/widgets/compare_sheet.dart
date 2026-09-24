import 'package:domain/domain.dart';
import 'package:flutter/material.dart';

import '../logic/credit_actions.dart';
import '../theme/nocturne_tokens.dart';

/// Side by side, when the household holds the same credit twice: the PWA's
/// `CompareSheet`.
///
/// The advice is concrete about the thing people actually get wrong, that
/// one booking draws on one card, and stops short of ranking the two people,
/// which is not the app's business.
class CompareSheet extends StatelessWidget {
  const CompareSheet({
    super.key,
    required this.overlap,
    required this.actions,
    required this.onClose,
    required this.onOpenCredit,
  });

  final OverlapGroup overlap;
  final CreditActions actions;
  final VoidCallback onClose;
  final ValueChanged<String> onOpenCredit;

  /// What to do, in one paragraph, from the two balances.
  static String advice(OverlapGroup overlap) {
    if (overlap.instances.length < 2) return '';
    final first = overlap.instances[0];
    final second = overlap.instances[1];
    final behind = first.remainingCents >= second.remainingCents
        ? first
        : second;
    final ahead = identical(behind, first) ? second : first;
    if (behind.status == BenefitStatus.locked &&
        ahead.status != BenefitStatus.locked) {
      return 'The ${cardLabel(behind.card)} side is still behind an enrolment '
          'box, so only the ${formatMoney(ahead.remainingCents)} on '
          '${cardLabel(ahead.card)} can actually be spent today. Unlock it '
          'first — the money is already on the card.';
    }
    if (behind.remainingCents == ahead.remainingCents) {
      return 'Both sides are untouched at ${formatMoney(behind.remainingCents)} '
          'each. They cannot be combined, so this needs two separate purchases '
          '— not one larger one.';
    }
    return 'The ${cardLabel(behind.card)} side is the one at risk: '
        '${formatMoney(behind.remainingCents)} against '
        '${formatMoney(ahead.remainingCents)} on ${cardLabel(ahead.card)}. One '
        'purchase cannot draw on both cards, so clear the larger one first.';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    final text = Theme.of(context).textTheme;
    final today = actions.store.today;
    final note = text.bodySmall?.copyWith(color: tokens.textSecondary);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        Space.s6,
        Space.s4,
        Space.s6,
        Space.s8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      overlap.sameProduct
                          ? 'SAME CARD, HELD TWICE'
                          : 'SAME SPEND, TWO CARDS',
                      style: text.labelSmall?.copyWith(
                        color: tokens.accentRamp[400],
                      ),
                    ),
                    Semantics(
                      header: true,
                      child: Text(overlap.label, style: text.titleMedium),
                    ),
                    Text(
                      '${formatMoney(overlap.remainingCents)} unclaimed across '
                      '${overlap.instances.length} cards',
                      style: note,
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const Key('sheet-close'),
                tooltip: 'Close',
                onPressed: onClose,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: Space.s6),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (index, instance) in overlap.instances.indexed) ...[
                  if (index > 0) const SizedBox(width: Space.s3),
                  Expanded(
                    child: _Side(
                      instance: instance,
                      today: today,
                      onTap: () => onOpenCredit(instance.benefit.id),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: Space.s6),
          Container(
            padding: const EdgeInsets.all(Space.s4),
            decoration: BoxDecoration(
              color: tokens.section,
              borderRadius: const BorderRadius.all(Radius.circular(Radii.md)),
              border: Border.all(color: tokens.sectionGlow),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'WHAT TO DO',
                  style: text.labelSmall?.copyWith(
                    color: tokens.accentRamp[400],
                  ),
                ),
                const SizedBox(height: Space.s2),
                Text(
                  advice(overlap),
                  style: text.bodySmall?.copyWith(color: tokens.neutral[300]),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.s6),
          for (final instance in overlap.instances)
            if (instance.status != BenefitStatus.locked)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.s2),
                child: OutlinedButton.icon(
                  onPressed: () {
                    actions.log(instance);
                    onClose();
                  },
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: Text(
                    'Log ${formatMoney(instance.remainingCents)} on '
                    '${cardLabel(instance.card)}',
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _Side extends StatelessWidget {
  const _Side({
    required this.instance,
    required this.today,
    required this.onTap,
  });

  final BenefitInstance instance;
  final IsoDate today;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    final text = Theme.of(context).textTheme;
    final locked = instance.status == BenefitStatus.locked;
    final palette = locked ? tokens.locked : tokens.available;
    final name = cardLabel(instance.card);
    return Material(
      color: tokens.surfaceQuiet,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(Radii.md)),
        side: BorderSide(color: locked ? palette.line : tokens.surfaceLine),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(Radius.circular(Radii.md)),
        child: Padding(
          padding: const EdgeInsets.all(Space.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: text.labelSmall?.copyWith(color: tokens.textSecondary),
              ),
              Text(
                formatMoney(instance.remainingCents),
                style: text.titleLarge?.copyWith(fontWeight: FontWeight.w500),
              ),
              Text(
                'of ${formatMoney(instance.benefit.valueCents)}',
                style: text.bodySmall?.copyWith(color: tokens.textSecondary),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.s3),
                child: LinearProgressIndicator(
                  value: instance.benefit.valueCents == 0
                      ? 0
                      : instance.claimedCents / instance.benefit.valueCents,
                  semanticsLabel: 'Claimed so far',
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.s2,
                  vertical: Space.s1,
                ),
                decoration: BoxDecoration(
                  color: palette.ground,
                  borderRadius: const BorderRadius.all(
                    Radius.circular(Radii.sm),
                  ),
                  border: Border.all(color: palette.line),
                ),
                child: Text(
                  statusLabel(instance.status),
                  style: text.labelSmall?.copyWith(color: palette.foreground),
                ),
              ),
              const SizedBox(height: Space.s2),
              Text(
                instance.daysRemaining >= 0
                    ? 'Closes ${formatDate(instance.cycle.end, today)}'
                    : 'Closed ${formatDate(instance.cycle.end, today)}',
                style: text.bodySmall?.copyWith(color: tokens.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
