import 'package:domain/domain.dart' hide Tone;
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/semantics.dart';
import 'package:go_router/go_router.dart';

import '../logic/app_store.dart';
import '../logic/snackbar_state.dart';
import '../logic/ui_state.dart';
import '../shell/router.dart';
import '../shell/width_class.dart';
import '../theme/nocturne_tokens.dart';
import '../widgets/screen_title.dart';

/// Which colour a verdict is drawn in.
enum VerdictTone { accent, locked, missed }

class CardVerdict {
  const CardVerdict(this.headline, this.body, this.tone);

  final String headline;
  final String body;
  final VerdictTone tone;
}

/// The verdict, worded as the PWA words it. It leads with an action rather
/// than a score, and it refuses to price lounge access or status, because
/// putting a number on those would be the one judgement the app should not
/// fake.
CardVerdict cardVerdict(CardSummary summary) {
  final net = summary.netCents;
  final short = formatMoney(net.abs());
  final claimable = summary.claimableCents;
  final locked = summary.lockedCents;
  final days = summary.daysUntilRenewal;
  if (summary.annualFeeCents == 0) {
    return const CardVerdict(
      'No fee',
      'Nothing to break even against — every credit you capture is upside.',
      VerdictTone.accent,
    );
  }
  if (net >= 0) {
    return CardVerdict(
      'Keep',
      'Already ${formatMoney(net)} past the fee, with ${formatMoney(claimable)} '
          'still open.',
      VerdictTone.accent,
    );
  }
  if (locked > 0 && claimable + locked >= net.abs()) {
    return CardVerdict(
      'Unlock first',
      '${formatMoney(locked)} is sitting behind an enrolment box. With it, '
          'there is enough left this year to clear the $short shortfall — so '
          'unlock it before you weigh a downgrade.',
      VerdictTone.locked,
    );
  }
  if (claimable >= net.abs()) {
    return CardVerdict(
      'Catch up',
      '${formatMoney(claimable)} is still claimable — more than the $short you '
          'are short. $days days to the renewal.',
      VerdictTone.accent,
    );
  }
  return CardVerdict(
    'Decide',
    '$short short with $days days to the renewal, and only '
        '${formatMoney(claimable)} left to claim. Lounge access and status are '
        'not counted here.',
    VerdictTone.missed,
  );
}

/// Cards: what each card is actually worth against its fee.
///
/// One card per active card from the store's summaries, the fee and captured
/// totals in the header, a menu per card with Mute, Archive and Delete, and
/// the way into the catalogue and the editors.
class CardsScreen extends StatelessWidget {
  const CardsScreen({super.key, required this.store, this.ui});

  final AppStore store;

  /// The snackbar for the menu's feedback; without it the menu still writes
  /// but reports nothing.
  final UiState? ui;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (store.loading) {
          return const Center(child: CircularProgressIndicator());
        }
        return _CardsBody(store: store, ui: ui);
      },
    );
  }
}

class _CardsBody extends StatelessWidget {
  const _CardsBody({required this.store, required this.ui});

  final AppStore store;
  final UiState? ui;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    final text = Theme.of(context).textTheme;
    final widthClass = WidthClass.of(context);
    final summaries = store.cardSummaries;
    final feeTotal = summaries.fold(0, (sum, s) => sum + s.annualFeeCents);
    final capturedTotal = summaries.fold(0, (sum, s) => sum + s.capturedCents);
    final note = text.bodySmall?.copyWith(color: tokens.textSecondary);

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ScreenTitle(label: 'Cards', style: text.titleMedium),
        if (summaries.isNotEmpty) ...[
          const SizedBox(height: Space.s2),
          Text(
            '${formatMoney(feeTotal)} in fees this cardmember year. '
            'Value captured so far: ${formatMoney(capturedTotal)}.',
            style: note,
          ),
        ],
      ],
    );

    final addCard = OutlinedButton.icon(
      key: const Key('add-card'),
      onPressed: () => context.go(Paths.newCard),
      icon: const Icon(Icons.add, size: 16),
      label: const Text('Add a card from the catalogue'),
    );

    final cards = [
      for (final summary in summaries)
        _CardStat(
          key: ValueKey('card-${summary.card.id}'),
          summary: summary,
          store: store,
          snackbar: ui?.snackbar,
          wide: widthClass == WidthClass.expanded,
        ),
    ];

    // One column on a phone, two across at medium, one wide row per card at
    // expanded with the verdict beside the figures.
    final Widget grid = widthClass == WidthClass.medium
        ? LayoutBuilder(
            builder: (context, constraints) {
              final width = (constraints.maxWidth - Space.s4) / 2;
              return Wrap(
                spacing: Space.s4,
                runSpacing: Space.s4,
                children: [
                  for (final card in cards) SizedBox(width: width, child: card),
                ],
              );
            },
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final card in cards) ...[
                card,
                const SizedBox(height: Space.s4),
              ],
            ],
          );

    return ListView(
      padding: EdgeInsets.all(widthClass.padding),
      children: [
        header,
        const SizedBox(height: Space.s6),
        grid,
        if (widthClass == WidthClass.medium) const SizedBox(height: Space.s4),
        addCard,
        if (summaries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.s12),
            child: Column(
              children: [
                Icon(Icons.credit_card_outlined, color: tokens.textSecondary),
                const SizedBox(height: Space.s3),
                Semantics(
                  header: true,
                  headingLevel: 2,
                  child: Text('Start with one card', style: text.titleSmall),
                ),
                const SizedBox(height: Space.s2),
                Text(
                  'Pick it from the catalogue and its credits come pre-filled, '
                  'including which ones are stuck behind an enrolment box. You '
                  'can edit every one of them afterwards.',
                  style: note,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

enum _CardAction { mute, archive, delete }

/// One card against its fee.
class _CardStat extends StatelessWidget {
  const _CardStat({
    super.key,
    required this.summary,
    required this.store,
    required this.snackbar,
    required this.wide,
  });

  final CardSummary summary;
  final AppStore store;
  final SnackbarState? snackbar;

  /// The verdict beside the figures rather than under them.
  final bool wide;

  Card get card => summary.card;
  String get label => cardLabel(card);

  Future<void> _act(BuildContext context, _CardAction action) async {
    switch (action) {
      case _CardAction.mute:
        final wasMuted = store.isCardMuted(card.id);
        await store.toggleCardMute(card.id);
        snackbar?.show(
          wasMuted
              ? 'Reminders back on for every credit on $label.'
              : 'Silenced every credit on $label.',
          action: SnackbarAction(
            label: 'Undo',
            semanticsLabel: wasMuted
                ? 'Undo reminders back on for $label'
                : 'Undo silencing $label',
            onAct: () => store.toggleCardMute(card.id),
          ),
        );
      case _CardAction.archive:
        await store.archiveCard(card.id);
        snackbar?.show(
          'Archived $label.',
          action: SnackbarAction(
            label: 'Undo',
            semanticsLabel: 'Undo archiving $label',
            onAct: () =>
                store.updateCard(card.id, (c) => c.copyWith(archived: false)),
          ),
        );
      case _CardAction.delete:
        // Deleting a card destroys its claim history, which no undo snackbar
        // can honestly cover, so this one asks first.
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Delete $label?'),
            content: Text(
              'Delete $label and everything logged against it? This cannot '
              'be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        await store.deleteCard(card.id);
        snackbar?.show('Card deleted.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    final text = Theme.of(context).textTheme;
    final verdict = cardVerdict(summary);
    final verdictColor = switch (verdict.tone) {
      VerdictTone.accent => tokens.accentRamp[300]!,
      VerdictTone.locked => tokens.locked.foreground,
      VerdictTone.missed => tokens.missed.foreground,
    };
    final quiet = text.labelSmall?.copyWith(color: tokens.textSecondary);
    final progress = summary.feeProgress.clamp(0.0, 1.0);
    final count = summary.instances.length;

    // Each block carries its place in the phone order, so the two-column
    // layout reads top to bottom the way the phone does.
    Widget block(int order, Widget child) => Semantics(
      container: true,
      sortKey: OrdinalSortKey(order.toDouble(), name: 'card-${card.id}'),
      child: child,
    );

    final head = block(
      0,
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(card.issuer, style: quiet),
                Semantics(
                  header: true,
                  headingLevel: 2,
                  child: Text(label, style: text.titleSmall),
                ),
              ],
            ),
          ),
          MergeSemantics(
            child: Semantics(
              label: 'Menu for $label',
              child: PopupMenuButton<_CardAction>(
                key: ValueKey('card-menu-${card.id}'),
                onSelected: (action) => _act(context, action),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: _CardAction.mute,
                    child: Text(store.isCardMuted(card.id) ? 'Unmute' : 'Mute'),
                  ),
                  const PopupMenuItem(
                    value: _CardAction.archive,
                    child: Text('Archive'),
                  ),
                  const PopupMenuItem(
                    value: _CardAction.delete,
                    child: Text('Delete'),
                  ),
                ],
                icon: Icon(
                  store.isCardMuted(card.id)
                      ? Icons.notifications_off_outlined
                      : Icons.more_vert,
                  size: 18,
                  color: store.isCardMuted(card.id)
                      ? tokens.accent
                      : tokens.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    final figures = block(
      1,
      Padding(
        key: ValueKey('card-figures-${card.id}'),
        padding: const EdgeInsets.only(top: Space.s4),
        child: Row(
          children: [
            for (final (title, value, color) in [
              ('Fee', formatMoney(summary.annualFeeCents), tokens.text),
              ('Captured', formatMoney(summary.capturedCents), tokens.text),
              (
                'Net vs fee',
                '${summary.netCents >= 0 ? '+' : '−'}'
                    '${formatMoney(summary.netCents.abs())}',
                summary.netCents >= 0
                    ? tokens.accentRamp[300]!
                    : tokens.neutral[400]!,
              ),
            ])
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title.toUpperCase(), style: quiet),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        value,
                        style: text.titleMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );

    // The 100% line is break-even, so cards with different fees stay
    // comparable.
    final bar = block(
      2,
      Padding(
        padding: const EdgeInsets.only(top: Space.s4),
        child: LinearProgressIndicator(
          value: progress,
          semanticsLabel: 'Share of the annual fee earned back',
        ),
      ),
    );

    final pct = block(
      3,
      Padding(
        padding: const EdgeInsets.only(top: Space.s2),
        child: Text(
          '${(summary.feeProgress * 100).round()}% of the fee earned back · '
          '${summary.daysUntilRenewal} days to renewal',
          style: text.bodySmall?.copyWith(color: tokens.textSecondary),
        ),
      ),
    );

    final verdictText = block(
      4,
      Padding(
        key: ValueKey('card-verdict-${card.id}'),
        padding: const EdgeInsets.only(top: Space.s4),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '${verdict.headline}. ',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: verdictColor,
                ),
              ),
              TextSpan(text: verdict.body),
            ],
          ),
          style: text.bodySmall,
        ),
      ),
    );

    final tags = block(
      5,
      Padding(
        padding: const EdgeInsets.only(top: Space.s4),
        child: Wrap(
          spacing: Space.s2,
          runSpacing: Space.s2,
          children: [
            if (summary.claimableCents > 0)
              _Tag(
                '${formatMoney(summary.claimableCents)} claimable',
                icon: Icons.hourglass_top,
                palette: tokens.available,
              ),
            if (summary.lockedCents > 0)
              _Tag(
                '${formatMoney(summary.lockedCents)} locked',
                icon: Icons.lock_outline,
                palette: tokens.locked,
              ),
            if (summary.missedCents > 0)
              _Tag(
                '${formatMoney(summary.missedCents)} missed',
                icon: Icons.hourglass_bottom,
                palette: tokens.missed,
              ),
            _Tag('$count credit${count == 1 ? '' : 's'}'),
            if (summary.card.kind == CardKind.business)
              const _Tag('Business', icon: Icons.work_outline),
          ],
        ),
      ),
    );

    final edit = block(
      6,
      Padding(
        padding: const EdgeInsets.only(top: Space.s4),
        child: OutlinedButton.icon(
          onPressed: () => context.go(cardPath(card.id)),
          icon: const Icon(Icons.tune, size: 16),
          label: const Text('Edit card and credits'),
        ),
      ),
    );

    final body = wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [head, figures, bar, pct],
                ),
              ),
              const SizedBox(width: Space.s10),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [verdictText, tags, edit],
                ),
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [head, figures, bar, pct, verdictText, tags, edit],
          );

    return Container(
      padding: const EdgeInsets.all(Space.s4),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: const BorderRadius.all(Radius.circular(Radii.md)),
        border: Border.all(color: tokens.surfaceLine),
      ),
      child: body,
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.icon, this.palette});

  final String text;
  final IconData? icon;
  final Tone? palette;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    final style = Theme.of(context).textTheme.labelSmall;
    final foreground = palette?.foreground ?? tokens.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s3,
        vertical: Space.s1,
      ),
      decoration: BoxDecoration(
        color: palette?.ground ?? tokens.surfaceQuiet,
        borderRadius: const BorderRadius.all(Radius.circular(Radii.sm)),
        border: Border.all(color: palette?.line ?? tokens.surfaceLine),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: foreground),
            const SizedBox(width: Space.s1),
          ],
          Flexible(
            child: Text(text, style: style?.copyWith(color: foreground)),
          ),
        ],
      ),
    );
  }
}
