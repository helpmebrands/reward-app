import 'package:domain/domain.dart';
import 'package:flutter/material.dart';

import '../theme/nocturne_tokens.dart';
import 'all_caught_up.dart';
import 'screen_title.dart';

/// "Next up: Uber Cash, $15 × 2": the credits opening next, by name.
String nextUpTitle(NextOpening next) {
  final names = next.benefits.map((b) => b.name).toSet();
  if (names.length > 1) {
    return 'Next up: ${names.first} and ${names.length - 1} more, '
        '${formatMoney(next.valueCents)}';
  }
  final values = next.benefits.map((b) => b.valueCents).toSet();
  final count = next.benefits.length;
  if (values.length == 1 && count > 1) {
    return 'Next up: ${names.single}, ${formatMoney(values.single)} × $count';
  }
  return 'Next up: ${names.single}, ${formatMoney(next.valueCents)}';
}

/// "Opens Oct 1, in 15 days".
String nextUpWhen(NextOpening next, IsoDate today) {
  final days = daysBetween(today, next.on);
  final date = formatDate(next.on, today);
  return days == 1 ? 'Opens $date, tomorrow' : 'Opens $date, in $days days';
}

/// Today's headline once nothing is claimable: the eyebrow, then the
/// all-caught-up illustration, a heading and a line in place of the number,
/// and the Next up card.
///
/// With credits still locked the heading does not say "all" and there is no
/// Next up card: the locked section below is the next thing to act on.
class TodayCaughtUp extends StatelessWidget {
  const TodayCaughtUp({
    super.key,
    required this.eyebrow,
    required this.today,
    required this.capturedCents,
    required this.lockedCents,
    required this.cards,
    this.next,
  });

  final String eyebrow;
  final IsoDate today;
  final int capturedCents;
  final int lockedCents;
  final int cards;
  final NextOpening? next;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    final text = Theme.of(context).textTheme;
    final locked = lockedCents > 0;
    final heading = locked ? 'Everything you can use is used' : 'All caught up';
    final line = locked
        ? '${formatMoney(lockedCents)} is still locked. Unlock it and it will '
              'show up here.'
        : capturedCents > 0
        ? 'You’ve used all ${formatMoney(capturedCents)} open this period '
              'across $cards card${cards == 1 ? '' : 's'}.'
        : 'Nothing is open this period.';
    final next = locked ? null : this.next;
    return Column(
      key: const Key('today-headline'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ScreenTitle(
          label: 'Today',
          text: eyebrow,
          style: text.labelSmall?.copyWith(color: tokens.textSecondary),
        ),
        const SizedBox(height: Space.s4),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: AllCaughtUp(size: locked ? 104 : 132)),
                const SizedBox(height: Space.s3),
                // Each its own node, so neither folds into the section's label
                // and the heading is read right after "Today".
                Semantics(
                  container: true,
                  header: true,
                  headingLevel: 2,
                  child: Text(
                    heading,
                    textAlign: TextAlign.center,
                    style: text.titleLarge,
                  ),
                ),
                const SizedBox(height: Space.s1),
                Semantics(
                  container: true,
                  child: Text(
                    line,
                    textAlign: TextAlign.center,
                    style: text.bodyMedium?.copyWith(
                      color: tokens.textSecondary,
                    ),
                  ),
                ),
                if (next != null) ...[
                  const SizedBox(height: Space.s4),
                  _NextUpCard(next: next, today: today),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The date the next credits open, as a calendar leaf beside their names.
class _NextUpCard extends StatelessWidget {
  const _NextUpCard({required this.next, required this.today});

  final NextOpening next;
  final IsoDate today;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    final text = Theme.of(context).textTheme;
    final date = formatDate(next.on, today).split(' ');
    return MergeSemantics(
      child: Container(
        key: const Key('today-next-up'),
        padding: const EdgeInsets.all(Space.s3),
        decoration: BoxDecoration(
          color: tokens.surfaceSunken,
          border: Border.all(color: tokens.surfaceLine),
          borderRadius: const BorderRadius.all(Radius.circular(Radii.md)),
        ),
        child: Row(
          children: [
            // The line under the name says the date; the leaf is drawn only.
            ExcludeSemantics(
              child: Container(
                width: 44,
                padding: const EdgeInsets.symmetric(vertical: Space.s1),
                decoration: BoxDecoration(
                  border: Border.all(color: tokens.controlBorder),
                  borderRadius: const BorderRadius.all(
                    Radius.circular(Radii.sm),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      date.first.toUpperCase(),
                      style: text.labelSmall?.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                    Text(date[1].replaceAll(',', ''), style: text.titleMedium),
                  ],
                ),
              ),
            ),
            const SizedBox(width: Space.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(nextUpTitle(next), style: text.titleSmall),
                  Text(
                    nextUpWhen(next, today),
                    style: text.bodySmall?.copyWith(
                      color: tokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
