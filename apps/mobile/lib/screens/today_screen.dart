import 'package:domain/domain.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/semantics.dart';
import 'package:go_router/go_router.dart';

import '../logic/app_store.dart';
import '../logic/credit_actions.dart';
import '../logic/ui_state.dart';
import 'join_screen.dart';
import '../shell/router.dart';
import '../shell/width_class.dart';
import '../theme/nocturne_tokens.dart';
import '../widgets/add_card_button.dart';
import '../widgets/credit_row.dart';
import '../widgets/empty_card_slot.dart';
import '../widgets/nothing_due_soon.dart';
import '../widgets/screen_title.dart';
import '../widgets/today_caught_up.dart';
import '../widgets/today_headline.dart';
import '../widgets/value_bar.dart';

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
          return _EmptyToday(store: store);
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
    // A card shared only to view logs nothing; silencing stays the
    // person's own.
    final records = store.accessTo(instance.card.id).records;
    return CreditRow(
      key: ValueKey('row-${instance.benefit.id}'),
      instance: instance,
      showCard: showCard,
      cardName: store.cardName(instance.card),
      onOpen: ui == null ? null : () => ui.openCredit(instance.benefit.id),
      onLogAll: actions == null || !records
          ? null
          : () => actions.logAll(instance),
      onToggleMute: actions == null ? null : () => actions.toggleMute(instance),
      mutePending: store.isMutePending(instance.benefit.id),
      onOptOut: actions == null || !records
          ? null
          : () => actions.optOut(instance),
    );
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

    // The headline, then the household's value bar for the year to date.
    // With nothing left to claim, the number gives way to "All caught up".
    final headline = _Section(
      order: 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (totals.claimableCents == 0)
            TodayCaughtUp(
              eyebrow: todayEyebrow(store.today),
              today: store.today,
              capturedCents: totals.capturedCents,
              lockedCents: totals.lockedCents,
              cards: store.cardCount,
              next: store.nextOpening,
            )
          else
            TodayHeadline(
              eyebrow: todayEyebrow(store.today),
              claimableCents: totals.claimableCents,
              sub: todayHeadlineSub(
                open: store.instances.where(isClaimable).length,
                cards: store.cardCount,
                resetOn: resetOn,
              ),
            ),
          const SizedBox(height: Space.s4),
          ValueBar(breakdown: store.householdValue),
        ],
      ),
    );

    // With money open but nothing closing within 30 days, a note says why
    // there are no rows and names the next deadline.
    final open = store.instances.where(isClaimable).toList();
    final router = GoRouter.maybeOf(context);
    final soonSection = soon.isEmpty
        ? open.isEmpty
              ? null
              : _Section(
                  order: 2,
                  child: Padding(
                    padding: const EdgeInsets.only(top: Space.s8),
                    child: NothingDueSoon(
                      next: open.reduce(
                        (a, b) => compareIsoDate(b.cycle.end, a.cycle.end) < 0
                            ? b
                            : a,
                      ),
                      today: store.today,
                      onOpenCredits: router == null
                          ? null
                          : () => router.go(Paths.credits),
                    ),
                  ),
                )
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
                    _OverlapCard(
                      overlap: overlap,
                      cardName: store.cardName,
                      onCompare: compare,
                    ),
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
                              cardName: store.cardName,
                              onCompare: compare,
                            ),
                          ),
                          const SizedBox(width: Space.s2),
                          Expanded(
                            child: i + 1 < overlaps.length
                                ? _OverlapCard(
                                    overlap: overlaps[i + 1],
                                    cardName: store.cardName,
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
    final byEnrollment = reasons.contains(LockReason.enrollment);
    final lockedTitle = bySpend && byEnrollment
        ? 'Locked behind enrollment and spend'
        : bySpend
        ? 'Locked behind a spend threshold'
        : 'Locked behind enrollment';
    final lockedNote = bySpend && byEnrollment
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
      children: [headline, body],
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
  const _OverlapCard({
    required this.overlap,
    required this.cardName,
    this.onCompare,
  });

  final OverlapGroup overlap;

  /// Each card's name as the app shows it (`AppStore.cardName`).
  final String Function(Card card) cardName;
  final ValueChanged<String>? onCompare;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    final text = Theme.of(context).textTheme;
    final cards = overlap.instances.map((i) => cardName(i.card)).join(' and ');
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

/// Today before any active card: what to do, why it matters, and one
/// button to the catalogue. It sits inside the shell, so Settings and
/// household sharing stay a tap away; the invite button is there for a
/// signed-in person who meant to join someone else's household.
class _EmptyToday extends StatelessWidget {
  const _EmptyToday({required this.store});

  static const heading = 'Add a card to start tracking its credits';
  static const body =
      'Reward cards pay back through monthly, quarterly and yearly credits '
      'that expire if you don’t use them. Add a card and HelpMe Reward will '
      'show what’s about to close.';

  final AppStore store;

  Future<void> _enterCode(BuildContext context) async {
    final code = await askForInviteCode(context);
    if (code != null && context.mounted) context.go(invitePath(code));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    final text = Theme.of(context).textTheme;
    final widthClass = WidthClass.of(context);
    final expanded = widthClass == WidthClass.expanded;
    final align = expanded ? TextAlign.start : TextAlign.center;

    final words = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: expanded
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.stretch,
      children: [
        ScreenTitle(
          label: heading,
          windowTitle: 'Today',
          style: text.titleLarge,
          textAlign: align,
        ),
        const SizedBox(height: Space.s3),
        Text(
          body,
          textAlign: align,
          style: text.bodyMedium?.copyWith(color: tokens.textSecondary),
        ),
        const SizedBox(height: Space.s8),
        AddCardButton(store: store),
        if (store.remote) ...[
          const SizedBox(height: Space.s2),
          TextButton(
            key: const Key('today-invite-code'),
            onPressed: () => _enterCode(context),
            child: Text(
              'Joining a household? Enter an invite code',
              textAlign: align,
            ),
          ),
        ],
      ],
    );

    // Beside the text from expanded, so the button stays above the fold on
    // a laptop; stacked and centred below that.
    final content = expanded
        ? Row(
            children: [
              const EmptyCardSlot(size: 200),
              SizedBox(width: widthClass.padding),
              Expanded(child: words),
            ],
          )
        : ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: EmptyCardSlot(size: 160)),
                const SizedBox(height: Space.s6),
                words,
              ],
            ),
          );

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: EdgeInsets.all(widthClass.padding),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: constraints.maxHeight - 2 * widthClass.padding,
          ),
          child: Center(child: content),
        ),
      ),
    );
  }
}
