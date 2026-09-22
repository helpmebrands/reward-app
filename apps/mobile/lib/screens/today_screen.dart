import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../logic/app_store.dart';
import '../shell/width_class.dart';
import '../theme/nocturne_tokens.dart';
import '../widgets/credit_row.dart';

/// Today: one number, a countdown, and the rows behind them.
///
/// The headline deliberately counts only what is *claimable*; locked credits
/// get their own section further down. Adding money the user cannot spend
/// into the number they are meant to act on would make the number a lie.
class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (store.loading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!store.hasCards) {
          return const _FirstRun();
        }
        return _TodayBody(store: store);
      },
    );
  }
}

class _TodayBody extends StatelessWidget {
  const _TodayBody({required this.store});

  final AppStore store;

  String headlineSub() {
    final open = store.instances.where(isClaimable).length;
    if (open == 0) {
      return 'Nothing is waiting on you. Every open credit is used.';
    }
    final resetOn = store.nextResetOn;
    final soonest = resetOn != null
        ? ' The nearest window shuts ${formatResetDate(resetOn)}.'
        : '';
    final cards = store.cardCount;
    return '$open open credit${open == 1 ? '' : 's'} across '
        '$cards card${cards == 1 ? '' : 's'}.$soonest';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    final text = Theme.of(context).textTheme;
    final widthClass = WidthClass.of(context);
    final totals = store.totals;
    final soon = store.soon;
    final locked = store.locked;
    final captured = store.captured;
    final allOverlaps = store.overlaps;
    final overlaps = allOverlaps.take(3).toList();
    final showCard = store.cardCount > 1;
    final resetOn = store.nextResetOn;
    final daysToReset = soon.isEmpty ? null : soon.first.daysRemaining;
    final parts = moneyParts(totals.claimableCents);

    final header = _Section(
      order: 0,
      child: Semantics(
        header: true,
        // A Wrap, not a Row: at a large text size the date drops under the
        // title instead of running off the right edge.
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: Space.s3,
          children: [
            Text('HelpMe Reward', style: text.titleMedium),
            Text(
              formatHeaderDate(store.today),
              style: text.bodySmall?.copyWith(color: tokens.textSecondary),
            ),
          ],
        ),
      ),
    );

    final headline = _Section(
      order: 1,
      child: Column(
        key: const Key('today-headline'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'UNCLAIMED, OPEN PERIODS',
            style: text.labelSmall?.copyWith(color: tokens.textSecondary),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(parts.symbol, style: text.headlineSmall),
              // The number shrinks with the column rather than forcing a
              // sideways scroll, as the PWA's clamp() does.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    parts.digits,
                    key: const Key('today-amount'),
                    style: text.displayMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Text(
            headlineSub(),
            style: text.bodyMedium?.copyWith(color: tokens.textSecondary),
          ),
        ],
      ),
    );

    final soonSection = soon.isEmpty
        ? null
        : _Section(
            order: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: Space.s8),
                _SectionTitle(
                  resetOn != null
                      ? 'Use soon — resets ${formatResetDate(resetOn)}'
                      : 'Use soon',
                  trailing: daysToReset == null
                      ? null
                      : (daysToReset == 0 ? 'today' : '$daysToReset days'),
                ),
                for (final instance in soon) ...[
                  const SizedBox(height: Space.s2),
                  CreditRow(instance: instance, showCard: showCard),
                ],
              ],
            ),
          );

    final overlapsSection = overlaps.isEmpty
        ? null
        : _Section(
            order: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: Space.s8),
                const _SectionTitle('Two cards, one benefit'),
                Text(
                  'These credits exist twice in the household, and one purchase cannot draw on both.'
                  '${allOverlaps.length > overlaps.length ? ' Showing the ${overlaps.length} largest of ${allOverlaps.length}; the rest are on Credits.' : ''}',
                  style: text.bodySmall?.copyWith(color: tokens.textSecondary),
                ),
                // Two across from medium, as the PWA pairs them; the widget
                // order is the phone's either way.
                if (widthClass == WidthClass.compact)
                  for (final overlap in overlaps) ...[
                    const SizedBox(height: Space.s2),
                    _OverlapCard(overlap: overlap),
                  ]
                else
                  for (var i = 0; i < overlaps.length; i += 2) ...[
                    const SizedBox(height: Space.s2),
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: _OverlapCard(overlap: overlaps[i])),
                          const SizedBox(width: Space.s2),
                          Expanded(
                            child: i + 1 < overlaps.length
                                ? _OverlapCard(overlap: overlaps[i + 1])
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ),
                  ],
              ],
            ),
          );

    final lockedSection = locked.isEmpty
        ? null
        : _Section(
            order: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: Space.s8),
                const _SectionTitle('Locked behind enrolment'),
                Text(
                  '${formatMoney(totals.lockedCents)} you cannot touch until you tick a box on the '
                  'issuer’s benefits page.',
                  style: text.bodySmall?.copyWith(color: tokens.textSecondary),
                ),
                for (final instance in locked) ...[
                  const SizedBox(height: Space.s2),
                  CreditRow(instance: instance, showCard: showCard),
                ],
              ],
            ),
          );

    final capturedSection = captured.isEmpty
        ? null
        : _Section(
            order: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: Space.s8),
                _SectionTitle(
                  'Captured this period — ${formatMoney(totals.capturedCents)}',
                ),
                for (final instance in captured) ...[
                  const SizedBox(height: Space.s2),
                  CreditRow(instance: instance, showCard: showCard),
                ],
              ],
            ),
          );

    final body = widthClass == WidthClass.expanded
        // Two columns under the headline: what needs doing and what is done
        // on the left, what is locked on the right. The sections carry sort
        // keys so a screen reader still hears the phone order.
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [?soonSection, ?overlapsSection, ?capturedSection],
                ),
              ),
              SizedBox(width: widthClass.padding),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [?lockedSection],
                ),
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ?soonSection,
              ?overlapsSection,
              ?lockedSection,
              ?capturedSection,
            ],
          );

    return ListView(
      padding: EdgeInsets.all(widthClass.padding),
      children: [
        header,
        const SizedBox(height: Space.s8),
        headline,
        body,
      ],
    );
  }
}

/// One of Today's sections as a semantics node with its place in the phone
/// order, so the two-column layout reads top to bottom the way the phone
/// does rather than by position on screen.
class _Section extends StatelessWidget {
  const _Section({required this.order, required this.child});

  final int order;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    sortKey: OrdinalSortKey(order.toDouble(), name: 'today'),
    child: child,
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title, style: text.titleSmall),
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: text.bodySmall?.copyWith(color: tokens.textSecondary),
            ),
        ],
      ),
    );
  }
}

/// The one sanctioned saturated ground: the overlap card.
class _OverlapCard extends StatelessWidget {
  const _OverlapCard({required this.overlap});

  final OverlapGroup overlap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    final text = Theme.of(context).textTheme;
    final holders = overlap.instances
        .map(
          (i) => i.card.holder.isNotEmpty ? i.card.holder : cardLabel(i.card),
        )
        .join(' and ');
    return Container(
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
            overlap.sameProduct ? 'SAME CARD, TWICE' : 'SAME SPEND, TWO CARDS',
            style: text.labelSmall?.copyWith(color: tokens.accentRamp[400]),
          ),
          Text(
            '${overlap.label} × ${overlap.instances.length}',
            style: text.titleSmall,
          ),
          Text(
            '${formatMoney(overlap.remainingCents)} unclaimed across $holders.',
            style: text.bodySmall?.copyWith(color: tokens.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// The first-run screen: one thing to do, and the reason to do it.
class _FirstRun extends StatelessWidget {
  const _FirstRun();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(Space.s8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Semantics(
            header: true,
            child: Text('Start with one card', style: text.titleMedium),
          ),
          const SizedBox(height: Space.s3),
          const Text(
            'Pick it from the catalogue and its credits arrive pre-filled. HelpMe Reward then '
            'warns you before each window shuts, and shows what the card is really worth '
            'against its fee.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
