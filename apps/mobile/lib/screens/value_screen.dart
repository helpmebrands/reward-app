import 'package:domain/domain.dart';
import 'package:flutter/material.dart';

import '../logic/app_store.dart';
import '../shell/width_class.dart';
import '../theme/nocturne_tokens.dart';

/// Value: what the household actually got, and what leaked away.
///
/// Cards are ranked worst-first and plotted as a percentage of *their own*
/// fee rather than in dollars. Six cards with six different fees cannot
/// share a dollar axis; on a percentage axis the 100% line is break-even for
/// all of them, and a $325 Gold is comparable with an $895 Platinum.
class ValueScreen extends StatefulWidget {
  const ValueScreen({super.key, required this.store});

  final AppStore store;

  @override
  State<ValueScreen> createState() => _ValueScreenState();
}

class _ValueScreenState extends State<ValueScreen> {
  int _monthsBack = 9;

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
    final note = text.bodySmall?.copyWith(color: tokens.textSecondary);
    final data = store.data!;
    final missed = store.missed;
    final months = monthlyTotals(
      data,
      missed,
      on: store.today,
      months: _monthsBack,
    );
    final leaks = biggestLeaks(missed);
    final summaries = store.cardSummaries;
    final ranked = [...summaries]
      ..sort((a, b) => a.feeProgress.compareTo(b.feeProgress));
    final capturedTotal = months.fold(0, (sum, m) => sum + m.capturedCents);
    final missedTotal = months.fold(0, (sum, m) => sum + m.missedCents);
    // Bars share one scale, so a tall month is tall on every card.
    final peak = months.fold(
      1,
      (peak, m) => [
        peak,
        m.capturedCents,
        m.missedCents,
      ].reduce((a, b) => a > b ? a : b),
    );
    final scope = summaries.length == 1
        ? cardLabel(summaries.single.card)
        : '${summaries.length} cards';

    Widget sectionTitle(String title) =>
        Semantics(header: true, child: Text(title, style: text.titleSmall));

    return ListView(
      padding: EdgeInsets.all(widthClass.padding),
      children: [
        Semantics(header: true, child: Text('Value', style: text.titleMedium)),
        const SizedBox(height: Space.s2),
        Text('Last $_monthsBack months · $scope', style: note),
        const SizedBox(height: Space.s6),

        // Two totals side by side, never one figure.
        Row(
          children: [
            Expanded(
              child: _Total(
                key: const Key('value-captured'),
                label: 'Captured',
                cents: capturedTotal,
                color: tokens.accentRamp[300]!,
                emphasis: true,
              ),
            ),
            const SizedBox(width: Space.s3),
            Expanded(
              child: _Total(
                key: const Key('value-missed'),
                label: 'Missed',
                cents: missedTotal,
                color: tokens.neutral[500]!,
                emphasis: false,
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.s6),

        if (missedTotal > 0) ...[
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
                  '${formatMoney(missedTotal)} has expired unclaimed',
                  style: text.titleSmall,
                ),
                const SizedBox(height: Space.s2),
                Text(
                  leaks.isEmpty
                      ? 'Nothing is repeating — these were one-off windows.'
                      : 'The biggest single leak is ${leaks.first.label} at '
                            '${formatMoney(leaks.first.missedCents)}. Small '
                            'recurring credits are exactly the shape of loss '
                            'the reminder ladder exists for.',
                  style: text.bodySmall?.copyWith(color: tokens.neutral[300]),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.s8),
        ],

        // The chart.
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: Space.s3,
          runSpacing: Space.s2,
          children: [
            sectionTitle('Captured against missed, by month'),
            Semantics(
              label: 'Months shown',
              container: true,
              explicitChildNodes: true,
              child: Wrap(
                spacing: Space.s2,
                children: [
                  for (final count in const [6, 9, 12])
                    ChoiceChip(
                      label: Text('${count}m'),
                      selected: _monthsBack == count,
                      onSelected: (_) => setState(() => _monthsBack = count),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.s3),
        ExcludeSemantics(
          child: Text('Tallest bar = ${formatMoney(peak)}', style: note),
        ),
        const SizedBox(height: Space.s2),
        // The painted chart is one semantics node carrying every month's
        // figures as text, the counterpart of the PWA's hidden table.
        Semantics(
          label: [
            'Captured against missed, by month.',
            for (final m in months)
              '${m.label}: captured ${formatMoney(m.capturedCents)}, '
                  'missed ${formatMoney(m.missedCents)}.',
          ].join(' '),
          child: SizedBox(
            height: 140,
            child: CustomPaint(
              key: const Key('value-chart'),
              painter: MonthlyBarsPainter(
                months: months,
                peakCents: peak,
                captured: tokens.accent,
                missed: tokens.chartMissed,
              ),
              size: Size.infinite,
            ),
          ),
        ),
        ExcludeSemantics(
          child: Row(
            children: [
              for (final m in months)
                Expanded(
                  child: Text(
                    m.label,
                    key: ValueKey('month-label-${m.month}'),
                    textAlign: TextAlign.center,
                    style: text.labelSmall?.copyWith(
                      color: tokens.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: Space.s4),
        Wrap(
          spacing: Space.s6,
          runSpacing: Space.s2,
          children: [
            _Legend(color: tokens.accent, label: 'Captured'),
            _Legend(color: tokens.chartMissed, label: 'Missed'),
          ],
        ),

        if (ranked.length > 1) ...[
          const SizedBox(height: Space.s8),
          sectionTitle('Cards against their own fee'),
          const SizedBox(height: Space.s2),
          Text(
            'Worst first. The line at 100% is break-even, so cards with '
            'different fees stay comparable.',
            style: note,
          ),
          const SizedBox(height: Space.s4),
          for (final summary in ranked)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.s3),
              child: _Rank(summary: summary),
            ),
        ],

        if (leaks.isNotEmpty) ...[
          const SizedBox(height: Space.s8),
          sectionTitle('Biggest leaks'),
          const SizedBox(height: Space.s2),
          Text(
            'Recurring credits that expired unclaimed, worst first.',
            style: note,
          ),
          const SizedBox(height: Space.s4),
          for (final (i, leak) in leaks.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.s2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.hourglass_bottom,
                    size: 14,
                    color: tokens.textSecondary,
                  ),
                  const SizedBox(width: Space.s3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          leak.label,
                          key: ValueKey('leak-label-$i'),
                          style: text.bodyMedium,
                        ),
                        Text(
                          leak.when,
                          key: ValueKey('leak-when-$i'),
                          style: note,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Space.s3),
                  Text(
                    formatMoney(leak.missedCents),
                    key: ValueKey('leak-amount-$i'),
                    style: text.bodyMedium?.copyWith(
                      color: tokens.missed.foreground,
                    ),
                  ),
                ],
              ),
            ),
        ],

        if (data.cards.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.s12),
            child: Column(
              children: [
                Icon(Icons.show_chart, color: tokens.textSecondary),
                const SizedBox(height: Space.s3),
                Text(
                  'Once a card is added and a few windows have closed, this '
                  'screen shows what you captured against what slipped.',
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

/// The monthly bars: for each month a missed bar and a captured bar side by
/// side, on one shared scale so a tall month is tall on every card. Drawn
/// with the token colours; no chart package.
class MonthlyBarsPainter extends CustomPainter {
  const MonthlyBarsPainter({
    required this.months,
    required this.peakCents,
    required this.captured,
    required this.missed,
  });

  final List<MonthTotals> months;
  final int peakCents;
  final Color captured;
  final Color missed;

  /// A bar's height for [cents] on a chart [chartHeight] tall.
  double heightFor(int cents, double chartHeight) =>
      peakCents <= 0 ? 0 : chartHeight * cents / peakCents;

  @override
  void paint(Canvas canvas, Size size) {
    if (months.isEmpty) return;
    final column = size.width / months.length;
    final gap = column * 0.18;
    final bar = (column - gap * 3) / 2;
    final missedPaint = Paint()..color = missed;
    final capturedPaint = Paint()..color = captured;
    for (final (i, month) in months.indexed) {
      final left = column * i + gap;
      final missedHeight = heightFor(month.missedCents, size.height);
      final capturedHeight = heightFor(month.capturedCents, size.height);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, size.height - missedHeight, bar, missedHeight),
          const Radius.circular(2),
        ),
        missedPaint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            left + bar + gap,
            size.height - capturedHeight,
            bar,
            capturedHeight,
          ),
          const Radius.circular(2),
        ),
        capturedPaint,
      );
    }
  }

  @override
  bool shouldRepaint(MonthlyBarsPainter old) =>
      old.months != months ||
      old.peakCents != peakCents ||
      old.captured != captured ||
      old.missed != missed;
}

class _Total extends StatelessWidget {
  const _Total({
    super.key,
    required this.label,
    required this.cents,
    required this.color,
    required this.emphasis,
  });

  final String label;
  final int cents;
  final Color color;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(Space.s4),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: const BorderRadius.all(Radius.circular(Radii.md)),
        border: Border.all(color: tokens.surfaceLine),
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
              style: text.titleLarge?.copyWith(
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.all(Radius.circular(2)),
            ),
          ),
        ),
        const SizedBox(width: Space.s2),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
        ),
      ],
    );
  }
}

/// One card on the percentage-of-fee axis, with the break-even line at 100%.
class _Rank extends StatelessWidget {
  const _Rank({required this.summary});

  final CardSummary summary;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    final text = Theme.of(context).textTheme;
    final percent = (summary.feeProgress * 100).round();
    final id = summary.card.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                cardLabel(summary.card),
                key: ValueKey('rank-label-$id'),
                style: text.bodySmall,
              ),
            ),
            const SizedBox(width: Space.s3),
            Text(
              '$percent%',
              key: ValueKey('rank-percent-$id'),
              style: text.bodySmall?.copyWith(
                color: summary.feeProgress >= 1
                    ? tokens.accentRamp[300]
                    : tokens.neutral[500],
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.s2),
        ExcludeSemantics(
          child: SizedBox(
            height: 8,
            child: LayoutBuilder(
              builder: (context, constraints) => Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: tokens.surfaceSunken,
                      borderRadius: const BorderRadius.all(
                        Radius.circular(Radii.sm),
                      ),
                    ),
                  ),
                  Container(
                    width:
                        constraints.maxWidth *
                        summary.feeProgress.clamp(0.0, 1.0),
                    decoration: BoxDecoration(
                      color: tokens.accent,
                      borderRadius: const BorderRadius.all(
                        Radius.circular(Radii.sm),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: Container(width: 2, color: tokens.controlBorder),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
