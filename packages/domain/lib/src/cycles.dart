/// Cycle maths: the concrete window a benefit can be used in, for each
/// cadence and anchor.
library;

import 'dates.dart';
import 'types.dart';

/// How many months one cycle of each cadence spans. [Cadence.manual] never
/// recurs.
int? monthsPerCycle(Cadence cadence) => switch (cadence) {
  Cadence.monthly => 1,
  Cadence.quarterly => 3,
  Cadence.semiannual => 6,
  Cadence.annual => 12,
  Cadence.manual => null,
};

/// The date every cycle of a benefit is measured from.
///
/// Calendar cycles anchor to January 1st, which puts quarters on Jan/Apr/Jul/Oct
/// and halves on Jan/Jul, the windows issuers actually use. Anniversary cycles
/// anchor to the day the account was opened.
IsoDate anchorDateFor(Benefit benefit, Card card) {
  if (benefit.anchor == CycleAnchor.anniversary) return card.anniversaryOn;
  final year = parseIsoDate(card.anniversaryOn).year;
  // Any January 1st serves as the origin; using the account's own year keeps
  // the arithmetic close to the dates involved.
  return '${year.toString().padLeft(4, '0')}-01-01';
}

const List<String> _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// The period label the screens show: "Sep 2026", "Q3 2026", "H2 2026", "2026".
///
/// Calendar-anchored windows get the familiar issuer shorthand. Anniversary
/// windows cannot use it (a cardmember quarter is not Q3), so they are labelled
/// by their start date instead.
String cycleLabel(Benefit benefit, IsoDate start) {
  final parts = parseIsoDate(start);
  final monthName = _monthNames[parts.month - 1];
  if (benefit.anchor == CycleAnchor.anniversary) {
    return 'from $monthName ${parts.day} ${parts.year}';
  }
  return switch (benefit.cadence) {
    Cadence.monthly => '$monthName ${parts.year}',
    Cadence.quarterly => 'Q${(parts.month - 1) ~/ 3 + 1} ${parts.year}',
    Cadence.semiannual => 'H${parts.month <= 6 ? 1 : 2} ${parts.year}',
    Cadence.annual => '${parts.year}',
    Cadence.manual => 'Untracked',
  };
}

/// The cycle containing [on], for a recurring benefit. [Cadence.manual]
/// benefits have no window and return null.
///
/// Walks from the anchor in whole cycle-lengths. Month arithmetic clamps
/// (Jan 31 + 1 month is Feb 28), so the step count is corrected by comparison
/// rather than derived from a month difference: clamping makes the naive
/// `(years * 12 + months)` formula land in the wrong window at month ends.
Cycle? cycleFor(Benefit benefit, Card card, IsoDate on) {
  final span = monthsPerCycle(benefit.cadence);
  if (span == null) return null;
  final anchor = anchorDateFor(benefit, card);

  final onParts = parseIsoDate(on);
  final anchorParts = parseIsoDate(anchor);
  final monthsApart =
      (onParts.year - anchorParts.year) * 12 +
      (onParts.month - anchorParts.month);
  var steps = (monthsApart - monthsApart % span) ~/ span;

  // At most one correction in either direction is ever needed; the loops are
  // bounded defensively rather than trusted to terminate on their own.
  for (
    var guard = 0;
    guard < 4 && compareIsoDate(addMonths(anchor, steps * span), on) > 0;
    guard++
  ) {
    steps--;
  }
  for (
    var guard = 0;
    guard < 4 && compareIsoDate(addMonths(anchor, (steps + 1) * span), on) <= 0;
    guard++
  ) {
    steps++;
  }

  final start = addMonths(anchor, steps * span);
  final end = addDays(addMonths(anchor, (steps + 1) * span), -1);
  return Cycle(
    key: start,
    start: start,
    end: end,
    label: cycleLabel(benefit, start),
  );
}

/// The cycle that follows [cycle], or null for untracked benefits.
Cycle? nextCycle(Benefit benefit, Card card, Cycle cycle) {
  if (benefit.cadence == Cadence.manual) return null;
  return cycleFor(benefit, card, addDays(cycle.end, 1));
}

/// The cycle before [cycle].
Cycle? previousCycle(Benefit benefit, Card card, Cycle cycle) {
  if (benefit.cadence == Cadence.manual) return null;
  return cycleFor(benefit, card, addDays(cycle.start, -1));
}

/// Every cycle overlapping `[from, to]`, oldest first. Used by the period
/// history and by reminder scheduling, which looks past the current window.
List<Cycle> cyclesBetween(
  Benefit benefit,
  Card card,
  IsoDate from,
  IsoDate to, {
  int maxCycles = 64,
}) {
  final cycles = <Cycle>[];
  var cycle = cycleFor(benefit, card, from);
  while (cycle != null &&
      cycles.length < maxCycles &&
      compareIsoDate(cycle.start, to) <= 0) {
    cycles.add(cycle);
    cycle = nextCycle(benefit, card, cycle);
  }
  return cycles;
}

/// The closed cycles preceding the one containing [on], newest first. This is
/// what the Missed ledger and the period-history sheet are built from.
List<Cycle> closedCyclesBefore(
  Benefit benefit,
  Card card,
  IsoDate on,
  int count,
) {
  final current = cycleFor(benefit, card, on);
  if (current == null) return const [];
  final cycles = <Cycle>[];
  var cycle = previousCycle(benefit, card, current);
  while (cycle != null && cycles.length < count) {
    cycles.add(cycle);
    cycle = previousCycle(benefit, card, cycle);
  }
  return cycles;
}

/// True when [on] falls inside the cycle window.
bool isCycleOpen(Cycle cycle, IsoDate on) =>
    isWithin(on, cycle.start, cycle.end);

/// Whole days from [on] until the cycle closes. 0 means it closes today.
int daysRemainingIn(Cycle cycle, IsoDate on) => daysBetween(on, cycle.end);

/// How far through its window a cycle is, clamped to 0..1.
double cycleProgress(Cycle cycle, IsoDate on) {
  final total = daysBetween(cycle.start, cycle.end) + 1;
  if (total <= 0) return 1;
  return (daysBetween(cycle.start, on) / total).clamp(0, 1).toDouble();
}

String cadenceLabel(Cadence cadence) => switch (cadence) {
  Cadence.monthly => 'Monthly',
  Cadence.quarterly => 'Quarterly',
  Cadence.semiannual => 'Semi-annual',
  Cadence.annual => 'Annual',
  Cadence.manual => 'Manual',
};

/// Value released per year. Untracked credits are counted once: a Global Entry
/// fee every four years is not worth a quarter of itself on the Cards screen.
int annualValueCents(Benefit benefit) {
  final span = monthsPerCycle(benefit.cadence);
  if (span == null) return benefit.valueCents;
  return benefit.valueCents * (12 ~/ span);
}
