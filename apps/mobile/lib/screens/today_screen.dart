import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/semantics.dart';

import '../logic/app_store.dart';
import '../logic/credit_actions.dart';
import '../logic/ui_state.dart';
import '../shell/router.dart';
import '../shell/width_class.dart';
import '../theme/nocturne_tokens.dart';
import '../widgets/credit_row.dart';
import '../widgets/screen_title.dart';

/// Today: one number, a countdown, and the rows behind them.
///
/// The headline deliberately counts only what is *claimable*; locked credits
/// get their own section further down. Adding money the user cannot spend
/// into the number they are meant to act on would make the number a lie.
class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key, required this.store, this.ui});

  final AppStore store;

  /// The sheets; without it the screen is static, as tests
  /// and previews build it bare.
  final UiState? ui;

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
        return _TodayBody(store: store, ui: ui);
      },
    );
  }
}

class _TodayBody extends StatelessWidget {
  const _TodayBody({required this.store, required this.ui});

  final AppStore store;
  final UiState? ui;

  CreditRow row(BenefitInstance instance, bool showCard) {
    final ui = this.ui;
    final actions = ui == null
        ? null
        : CreditActions(store: store, snackbar: ui.snackbar);
    return CreditRow(
      key: ValueKey('row-${instance.benefit.id}'),
      instance: instance,
      showCard: showCard,
      onOpen: ui == null ? null : () => ui.openCredit(instance.benefit.id),
      // A reader sees the household but logs nothing in it.
      onLogAll: actions == null || !store.canWrite
          ? null
          : () => actions.logAll(instance),
      onToggleMute: actions == null ? null : () => actions.toggleMute(instance),
      onOptOut: actions == null || !store.canWrite
          ? null
          : () => actions.optOut(instance),
    );
  }

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
    final ui = this.ui;
    final compare = ui?.openOverlap;
    final resetOn = store.nextResetOn;
    final daysToReset = soon.isEmpty ? null : soon.first.daysRemaining;
    final parts = moneyParts(totals.claimableCents);

    final header = _Section(
      order: 0,
      // A Wrap, not a Row: at a large text size the date drops under the
      // title instead of running off the right edge.
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        spacing: Space.s3,
        runSpacing: Space.s2,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: Space.s3,
            children: [
              // The heading reads "Today"; the logotype is what is drawn.
              ScreenTitle(
                label: 'Today',
                text: 'HelpMe Reward',
                style: text.titleMedium,
              ),
              Text(
                formatHeaderDate(store.today),
                style: text.bodySmall?.copyWith(color: tokens.textSecondary),
              ),
            ],
          ),
          if (ui != null)
            Wrap(
              spacing: Space.s2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // The only way into Settings, and therefore into turning
                // reminders on at all, so it lives on the screen people
                // open every day.
                MergeSemantics(
                  child: Semantics(
                    label: 'Settings',
                    child: IconButton(
                      onPressed: () => context.go(Paths.settings),
                      icon: const Icon(Icons.settings_outlined, size: 18),
                    ),
                  ),
                ),
              ],
            ),
        ],
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
                  row(instance, showCard),
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
                    _OverlapCard(overlap: overlap, onCompare: compare),
                  ]
                else
                  for (var i = 0; i < overlaps.length; i += 2) ...[
                    const SizedBox(height: Space.s2),
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _OverlapCard(
                              overlap: overlaps[i],
                              onCompare: compare,
                            ),
                          ),
                          const SizedBox(width: Space.s2),
                          Expanded(
                            child: i + 1 < overlaps.length
                                ? _OverlapCard(
                                    overlap: overlaps[i + 1],
                                    onCompare: compare,
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ),
                  ],
              ],
            ),
          );

    // The section says what stands in the way: a box to tick, a spend to
    // reach, or both.
    final reasons = {
      for (final instance in locked)
        lockReason(instance.benefit, instance.card, store.today),
    };
    final bySpend = reasons.contains(LockReason.spend);
    final byEnrolment = reasons.contains(LockReason.enrollment);
    final lockedTitle = bySpend && byEnrolment
        ? 'Locked behind enrolment and spend'
        : bySpend
        ? 'Locked behind a spend threshold'
        : 'Locked behind enrolment';
    final lockedNote = bySpend && byEnrolment
        ? '${formatMoney(totals.lockedCents)} you cannot touch yet: some needs a box '
              'ticked on the issuer’s benefits page, some a spend threshold.'
        : bySpend
        ? '${formatMoney(totals.lockedCents)} you cannot touch until you reach the '
              'spend the issuer asks for.'
        : '${formatMoney(totals.lockedCents)} you cannot touch until you tick a box on the '
              'issuer’s benefits page.';
    final lockedSection = locked.isEmpty
        ? null
        : _Section(
            order: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: Space.s8),
                _SectionTitle(lockedTitle),
                Text(
                  lockedNote,
                  style: text.bodySmall?.copyWith(color: tokens.textSecondary),
                ),
                for (final instance in locked) ...[
                  const SizedBox(height: Space.s2),
                  row(instance, showCard),
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
                  row(instance, showCard),
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
              headingLevel: 2,
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

/// The one sanctioned saturated ground: the overlap card. Tapping it opens
/// the compare sheet for the group.
class _OverlapCard extends StatelessWidget {
  const _OverlapCard({required this.overlap, this.onCompare});

  final OverlapGroup overlap;
  final ValueChanged<String>? onCompare;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    final text = Theme.of(context).textTheme;
    final cards = overlap.instances.map((i) => cardLabel(i.card)).join(' and ');
    final onCompare = this.onCompare;
    return Material(
      color: tokens.section,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(Radii.md)),
        side: BorderSide(color: tokens.sectionGlow),
      ),
      child: InkWell(
        onTap: onCompare == null ? null : () => onCompare(overlap.label),
        borderRadius: const BorderRadius.all(Radius.circular(Radii.md)),
        child: Padding(
          padding: const EdgeInsets.all(Space.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                overlap.sameProduct
                    ? 'SAME CARD, TWICE'
                    : 'SAME SPEND, TWO CARDS',
                style: text.labelSmall?.copyWith(color: tokens.accentRamp[400]),
              ),
              Text(
                '${overlap.label} × ${overlap.instances.length}',
                style: text.titleSmall,
              ),
              // Neutral-300, not the secondary text colour: on the section
              // ground the light theme's secondary text falls short of 4.5:1.
              Text(
                '${formatMoney(overlap.remainingCents)} unclaimed across $cards.',
                style: text.bodySmall?.copyWith(color: tokens.neutral[300]),
              ),
              if (onCompare != null) ...[
                const SizedBox(height: Space.s2),
                Text(
                  'Compare →',
                  style: text.labelSmall?.copyWith(
                    color: tokens.accentRamp[300],
                  ),
                ),
              ],
            ],
          ),
        ),
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
          ScreenTitle(
            label: 'Today',
            text: 'HelpMe Reward',
            style: text.labelSmall,
          ),
          const SizedBox(height: Space.s6),
          Semantics(
            header: true,
            headingLevel: 2,
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
