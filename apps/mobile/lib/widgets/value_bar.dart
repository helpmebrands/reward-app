import 'dart:math' as math;

import 'package:domain/domain.dart' hide Tone;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme/nocturne_tokens.dart';

/// One drawn segment: its key suffix, its label and what it holds.
typedef _Segment = ({String key, String label, int cents, Color colour});

List<_Segment> _segments(ValueBreakdown b, NocturneTokens t) => [
  (key: 'earned', label: 'Earned', cents: b.earnedCents, colour: t.valueEarned),
  (
    key: 'available',
    label: 'Available',
    cents: b.availableCents,
    colour: t.valueAvailable,
  ),
  (key: 'missed', label: 'Missed', cents: b.missedCents, colour: t.valueMissed),
  (
    key: 'optOut',
    label: 'Opt out',
    cents: b.optOutCents,
    colour: t.valueOptOut,
  ),
].where((s) => s.cents > 0).toList();

/// Whole dollars, as the bar prints them.
String _dollars(int cents) => formatMoney((cents / 100).round() * 100);

/// What a screen reader hears for the bar: the non-zero segments as one
/// sentence, e.g. "$540 earned, $770 available, $180 missed, $360 opt out".
String valueBarSentence(ValueBreakdown breakdown) => [
  if (breakdown.earnedCents > 0) '${_dollars(breakdown.earnedCents)} earned',
  if (breakdown.availableCents > 0)
    '${_dollars(breakdown.availableCents)} available',
  if (breakdown.missedCents > 0) '${_dollars(breakdown.missedCents)} missed',
  if (breakdown.optOutCents > 0) '${_dollars(breakdown.optOutCents)} opt out',
].join(', ');

/// The value bar: Earned · Available · Missed · Opt out, each as wide as its
/// share, with its amount and label centred under it.
///
/// When a label is wider than its segment it slides right past its
/// neighbour, or drops to a new row if that would run off the end. The
/// labels carry the status, so it never rests on colour alone, and the bar
/// is one semantics node read as [valueBarSentence].
class ValueBar extends StatelessWidget {
  const ValueBar({super.key, required this.breakdown});

  final ValueBreakdown breakdown;

  static const double height = 8;
  static const double gap = 2;
  static const double radius = 4;

  /// The least room between two labels on one row, and between rows.
  static const double labelGap = 8;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    final text = Theme.of(context).textTheme;
    final amountStyle = text.bodySmall!.copyWith(
      color: tokens.text,
      fontWeight: FontWeight.w500,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final labelStyle = text.bodySmall!.copyWith(color: tokens.textSecondary);
    final segments = _segments(breakdown, tokens);
    final total = breakdown.totalCents;

    final bar = LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final drawn = width - gap * math.max(0, segments.length - 1);
        final widths = [for (final s in segments) s.cents / total * drawn];
        final starts = <double>[];
        var x = 0.0;
        for (final w in widths) {
          starts.add(x);
          x += w + gap;
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              key: const Key('value-bar-track'),
              borderRadius: BorderRadius.circular(radius),
              child: SizedBox(
                height: height,
                child: ColoredBox(
                  color: tokens.surfaceSunken,
                  child: Stack(
                    children: [
                      for (var i = 0; i < segments.length; i++)
                        Positioned(
                          key: Key('value-bar-segment-${segments[i].key}'),
                          left: starts[i],
                          width: widths[i],
                          top: 0,
                          bottom: 0,
                          child: ColoredBox(color: segments[i].colour),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (segments.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: _LabelRows(
                  centres: [
                    for (var i = 0; i < widths.length; i++)
                      starts[i] + widths[i] / 2,
                  ],
                  children: [
                    for (final s in segments)
                      Column(
                        key: Key('value-bar-label-${s.key}'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_dollars(s.cents), style: amountStyle),
                          Text(s.label, style: labelStyle),
                        ],
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );

    if (segments.isEmpty) return ExcludeSemantics(child: bar);
    return Semantics(
      container: true,
      label: valueBarSentence(breakdown),
      excludeSemantics: true,
      child: bar,
    );
  }
}

/// Lays each child out centred on its entry in [centres]; a child that would
/// hit its left neighbour slides right past it, and one that would then run
/// off the end drops to a new row, as the design's study does.
class _LabelRows extends MultiChildRenderObjectWidget {
  const _LabelRows({required this.centres, required super.children});

  final List<double> centres;

  @override
  _RenderLabelRows createRenderObject(BuildContext context) =>
      _RenderLabelRows(centres);

  @override
  void updateRenderObject(BuildContext context, _RenderLabelRows renderObject) {
    renderObject.centres = centres;
  }
}

class _LabelParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderLabelRows extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _LabelParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _LabelParentData> {
  _RenderLabelRows(this._centres);

  List<double> _centres;
  set centres(List<double> value) {
    _centres = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _LabelParentData) {
      child.parentData = _LabelParentData();
    }
  }

  /// Where each child goes and the size that makes, given each child's size.
  (List<Offset>, Size) _place(
    BoxConstraints constraints,
    Size Function(RenderBox child, BoxConstraints constraints) sizeOf,
  ) {
    final width = constraints.maxWidth;
    final sizes = <Size>[];
    for (var child = firstChild; child != null; child = childAfter(child)) {
      sizes.add(sizeOf(child, BoxConstraints(maxWidth: width)));
    }
    final rowHeight =
        sizes.map((s) => s.height).fold(0.0, math.max) + ValueBar.labelGap / 2;
    // The right edge of the last child placed on each row.
    final ends = <double>[];
    final offsets = <Offset>[];
    for (var i = 0; i < sizes.length; i++) {
      final w = sizes[i].width;
      final ideal = _centres[i] - w / 2;
      for (var row = 0; ; row++) {
        final end = row < ends.length ? ends[row] : null;
        final left =
            (end == null ? ideal : math.max(ideal, end + ValueBar.labelGap))
                .clamp(0.0, math.max(0.0, width - w))
                .toDouble();
        if (end != null && left < end + ValueBar.labelGap) continue;
        if (end == null) {
          ends.add(left + w);
        } else {
          ends[row] = left + w;
        }
        offsets.add(Offset(left, row * rowHeight));
        break;
      }
    }
    final height = ends.isEmpty
        ? 0.0
        : ends.length * rowHeight - ValueBar.labelGap / 2;
    return (offsets, constraints.constrain(Size(width, height)));
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _place(constraints, (child, c) => child.getDryLayout(c)).$2;

  @override
  void performLayout() {
    final (offsets, size) = _place(constraints, (child, c) {
      child.layout(c, parentUsesSize: true);
      return child.size;
    });
    var i = 0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      (child.parentData! as _LabelParentData).offset = offsets[i++];
    }
    this.size = size;
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
