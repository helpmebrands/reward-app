import 'package:domain/domain.dart';
import 'package:flutter/material.dart';

import '../logic/app_store.dart';
import '../logic/credit_actions.dart';
import '../logic/ui_state.dart';
import '../shell/width_class.dart';
import '../theme/nocturne_tokens.dart';
import '../widgets/credit_row.dart';
import '../widgets/screen_title.dart';

/// The six filters, in the PWA's order.
enum CreditsFilter {
  all('All'),
  useSoon('Use soon'),
  open('Open'),
  locked('Locked'),
  captured('Captured'),
  missed('Missed');

  const CreditsFilter(this.label);

  final String label;
}

/// The three groupings, in the PWA's order.
enum CreditsGrouping {
  card('Card'),
  cycle('Cycle'),
  status('Status');

  const CreditsGrouping(this.label);

  final String label;
}

/// Closed windows folded in as first-class rows, so "Missed" is itemised per
/// credit rather than sitting as one number on the Value tab.
List<BenefitInstance> missedRows(AppStore store) {
  return [
    for (final entry in store.missed)
      BenefitInstance(
        benefit: entry.benefit,
        card: entry.card,
        cycle: entry.cycle,
        status: BenefitStatus.missed,
        claimedCents: entry.benefit.valueCents - entry.missedCents,
        remainingCents: entry.missedCents,
        daysRemaining: -1,
        cycleProgress: 1,
        muted: store.preferences.isMuted(entry.benefit),
      ),
  ];
}

/// The rows a filter keeps, from the live instances and the missed rows.
List<BenefitInstance> filterRows(
  List<BenefitInstance> rows,
  CreditsFilter filter,
) => switch (filter) {
  CreditsFilter.all => rows,
  CreditsFilter.useSoon => byStatus(rows, BenefitStatus.useSoon),
  CreditsFilter.open => rows.where(isClaimable).toList(),
  CreditsFilter.locked => byStatus(rows, BenefitStatus.locked),
  CreditsFilter.captured =>
    rows
        .where((r) => r.claimedCents > 0 && r.status != BenefitStatus.missed)
        .toList(),
  CreditsFilter.missed => byStatus(rows, BenefitStatus.missed),
};

/// The figure a group header carries, matched to the active filter: one
/// labelled number that never mixes claimable with missed.
String groupFigure(
  List<BenefitInstance> instances,
  CreditsFilter filter,
) => switch (filter) {
  CreditsFilter.missed => '${formatMoney(sumRemaining(instances))} missed',
  CreditsFilter.captured => '${formatMoney(sumClaimed(instances))} captured',
  CreditsFilter.locked => '${formatMoney(sumRemaining(instances))} locked',
  _ => '${formatMoney(sumRemaining(instances.where(isClaimable)))} claimable',
};

class CreditGroup {
  const CreditGroup({
    required this.key,
    required this.label,
    required this.instances,
    required this.figure,
  });

  final String key;
  final String label;
  final List<BenefitInstance> instances;
  final String figure;
}

/// Buckets the rows by card, cadence or status, in first-seen order as the
/// PWA does, each with its label and figure.
List<CreditGroup> groupRows(
  List<BenefitInstance> rows,
  CreditsGrouping grouping,
  CreditsFilter filter,
) {
  final buckets = <String, List<BenefitInstance>>{};
  for (final row in rows) {
    final key = switch (grouping) {
      CreditsGrouping.card => row.card.id,
      CreditsGrouping.cycle => row.benefit.cadence.name,
      CreditsGrouping.status => row.status.name,
    };
    buckets.putIfAbsent(key, () => []).add(row);
  }
  return [
    for (final entry in buckets.entries)
      CreditGroup(
        key: entry.key,
        label: switch (grouping) {
          CreditsGrouping.card => cardLabel(entry.value.first.card),
          CreditsGrouping.cycle => cadenceLabel(
            entry.value.first.benefit.cadence,
          ),
          CreditsGrouping.status => statusLabel(entry.value.first.status),
        },
        instances: entry.value,
        figure: groupFigure(entry.value, filter),
      ),
  ];
}

/// Credits: the ledger.
///
/// Today says *do this now*. This screen shows everything that exists and
/// where it stands, including the parts Today hides: locked, captured, and
/// the periods that already closed unused. Four totals rather than one:
/// claimable and missed are never summed, because money you can still get
/// and money you have already lost are not the same quantity.
class CreditsScreen extends StatefulWidget {
  const CreditsScreen({super.key, required this.store, this.ui});

  final AppStore store;

  /// The sheets and the snackbar; without it the rows are static.
  final UiState? ui;

  @override
  State<CreditsScreen> createState() => _CreditsScreenState();
}

class _CreditsScreenState extends State<CreditsScreen> {
  CreditsGrouping _grouping = CreditsGrouping.card;
  CreditsFilter _filter = CreditsFilter.all;

  AppStore get store => widget.store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (store.loading) {
          return const Center(child: CircularProgressIndicator());
        }
        return _body(context);
      },
    );
  }

  Widget _body(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    final text = Theme.of(context).textTheme;
    final widthClass = WidthClass.of(context);
    final ui = widget.ui;
    final actions = ui == null
        ? null
        : CreditActions(store: store, snackbar: ui.snackbar);
    final live = store.instances;
    final missed = missedRows(store);
    final totals = totalsFor(
      live,
      missed.fold(0, (sum, row) => sum + row.remainingCents),
    );
    final rows = filterRows([...live, ...missed], _filter);
    final groups = groupRows(rows, _grouping, _filter);
    final note = text.bodySmall?.copyWith(color: tokens.textSecondary);

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ScreenTitle(label: 'All credits', style: text.titleMedium),
        const SizedBox(height: Space.s2),
        Text(
          '${live.where(isClaimable).length} open · '
          '${byStatus(live, BenefitStatus.locked).length} locked · '
          '${store.missed.length} missed',
          style: note,
        ),
      ],
    );

    // Four totals kept deliberately apart: two by two on a phone, four
    // across from medium.
    final totalsGrid = LayoutBuilder(
      builder: (context, constraints) {
        final across = widthClass == WidthClass.compact ? 2 : 4;
        final width = (constraints.maxWidth - Space.s3 * (across - 1)) / across;
        return Wrap(
          spacing: Space.s3,
          runSpacing: Space.s3,
          children: [
            for (final (label, cents, emphasis) in [
              ('Claimable', totals.claimableCents, true),
              ('Locked', totals.lockedCents, false),
              ('Captured', totals.capturedCents, false),
              ('Missed', totals.missedCents, totals.missedCents > 0),
            ])
              SizedBox(
                width: width,
                child: _Total(
                  key: Key('total-$label'),
                  label: label,
                  cents: cents,
                  emphasis: emphasis,
                  missed: label == 'Missed',
                ),
              ),
          ],
        );
      },
    );

    final controls = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: 'Group credits by',
          container: true,
          explicitChildNodes: true,
          child: SegmentedButton<CreditsGrouping>(
            segments: [
              for (final grouping in CreditsGrouping.values)
                ButtonSegment(value: grouping, label: Text(grouping.label)),
            ],
            selected: {_grouping},
            showSelectedIcon: false,
            onSelectionChanged: (next) =>
                setState(() => _grouping = next.first),
          ),
        ),
        const SizedBox(height: Space.s3),
        Semantics(
          label: 'Filter by status',
          container: true,
          explicitChildNodes: true,
          child: Wrap(
            spacing: Space.s2,
            runSpacing: Space.s2,
            children: [
              for (final filter in CreditsFilter.values)
                ChoiceChip(
                  label: Text(filter.label),
                  selected: _filter == filter,
                  onSelected: (_) => setState(() => _filter = filter),
                ),
            ],
          ),
        ),
      ],
    );

    return ListView(
      padding: EdgeInsets.all(widthClass.padding),
      children: [
        header,
        const SizedBox(height: Space.s6),
        totalsGrid,
        const SizedBox(height: Space.s6),
        controls,
        const SizedBox(height: Space.s6),
        if (groups.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.s12),
            child: Column(
              children: [
                Icon(Icons.filter_alt_outlined, color: tokens.textSecondary),
                const SizedBox(height: Space.s3),
                Text('Nothing matches that filter.', style: note),
              ],
            ),
          )
        else
          for (final group in groups)
            _Group(
              group: group,
              grouping: _grouping,
              showCard: _grouping != CreditsGrouping.card,
              onOpen: ui?.openCredit,
              actions: actions,
            ),
      ],
    );
  }
}

class _Total extends StatelessWidget {
  const _Total({
    super.key,
    required this.label,
    required this.cents,
    required this.emphasis,
    required this.missed,
  });

  final String label;
  final int cents;
  final bool emphasis;
  final bool missed;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    final text = Theme.of(context).textTheme;
    final line = missed && emphasis ? tokens.missed.line : tokens.surfaceLine;
    return Container(
      padding: const EdgeInsets.all(Space.s4),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: const BorderRadius.all(Radius.circular(Radii.md)),
        border: Border.all(color: line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: text.labelSmall?.copyWith(
              color: emphasis ? tokens.accentRamp[400] : tokens.textSecondary,
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatMoney(cents),
              style: text.titleMedium?.copyWith(
                fontWeight: FontWeight.w500,
                color: missed && emphasis ? tokens.missed.foreground : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({
    required this.group,
    required this.grouping,
    required this.showCard,
    required this.onOpen,
    required this.actions,
  });

  final CreditGroup group;
  final CreditsGrouping grouping;
  final bool showCard;
  final ValueChanged<String>? onOpen;
  final CreditActions? actions;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    final text = Theme.of(context).textTheme;
    final first = group.instances.first;
    final dot = grouping == CreditsGrouping.status
        ? switch (first.status) {
            BenefitStatus.useSoon => tokens.soon.line,
            BenefitStatus.available => tokens.available.line,
            BenefitStatus.locked => tokens.locked.line,
            BenefitStatus.captured ||
            BenefitStatus.manual => tokens.captured.line,
            BenefitStatus.missed => tokens.missed.line,
          }
        : tokens.accentRamp[700]!;
    final actions = this.actions;
    final onOpen = this.onOpen;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A Wrap, not a Row: at a large text size the figure drops under
          // the label instead of overflowing the column.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: Space.s2),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
              ),
              const SizedBox(width: Space.s3),
              Expanded(
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: Space.s3,
                  children: [
                    Semantics(
                      header: true,
                      headingLevel: 2,
                      child: Text(
                        group.label,
                        key: ValueKey('group-label-${group.key}'),
                        style: text.titleSmall,
                      ),
                    ),
                    Text(
                      group.figure,
                      key: ValueKey('group-figure-${group.key}'),
                      style: text.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          for (final instance in group.instances)
            Padding(
              padding: const EdgeInsets.only(top: Space.s2),
              child: CreditRow(
                key: ValueKey(
                  'row-${instance.benefit.id}-${instance.cycle.key}',
                ),
                instance: instance,
                showCard: showCard,
                onOpen: onOpen == null
                    ? null
                    : () => onOpen.call(instance.benefit.id),
                onLogAll: actions == null || !actions.store.canWrite
                    ? null
                    : () => actions.logAll(instance),
                onToggleMute: actions == null
                    ? null
                    : () => actions.toggleMute(instance),
              ),
            ),
          if (grouping == CreditsGrouping.card)
            Padding(
              padding: const EdgeInsets.only(top: Space.s2),
              child: Text(
                '${categoryLabel(first.benefit.category)} and '
                '${group.instances.length - 1} more on this card',
                style: text.bodySmall?.copyWith(color: tokens.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}
