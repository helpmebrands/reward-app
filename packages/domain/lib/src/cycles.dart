/// Cycle maths: the concrete window a benefit can be used in, for each
/// cadence and anchor.
library;

import 'dates.dart';
import 'types.dart';

/// How many months one cycle of each calendar cadence spans. [Cadence.manual]
/// never recurs and [Cadence.rolling] takes its span from the benefit.
int? monthsPerCycle(Cadence cadence) => switch (cadence) {
  Cadence.monthly => 1,
  Cadence.quarterly => 3,
  Cadence.semiannual => 6,
  Cadence.annual => 12,
  Cadence.rolling => null,
  Cadence.manual => null,
};

/// The end of a window that only a claim can close.
const IsoDate _openEnded = '2999-12-31';

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
    Cadence.rolling => 'Eligible now',
    Cadence.manual => 'Untracked',
  };
}

/// A rolling credit's window comes from the claim ledger, not the calendar.
///
/// The open window is keyed by the day the card was added, or the day after
/// the last closed window. The first claim recorded under that key closes it
/// to `[claim day, claim day + intervalMonths − 1]`, and a new open window
/// keys from the day after. Keys never move, so a claim always finds its
/// window and the app never offers a credit the issuer would refuse.
Cycle _rollingCycleFor(
  Benefit benefit,
  Card card,
  IsoDate on,
  List<Claim> claims,
) {
  final interval = benefit.intervalMonths ?? 0;
  var key = card.createdAt.substring(0, 10);
  final mine = claims.where((claim) => claim.benefitId == benefit.id).toList()
    ..sort((a, b) => a.claimedAt.compareTo(b.claimedAt));
  for (final claim in mine) {
    if (claim.cycleKey != key || interval <= 0) continue;
    final start = claim.claimedAt.substring(0, 10);
    final end = addDays(addMonths(start, interval), -1);
    if (compareIsoDate(on, end) <= 0) {
      final parts = parseIsoDate(end);
      return Cycle(
        key: key,
        start: start,
        end: end,
        label: 'until ${_monthNames[parts.month - 1]} ${parts.year}',
      );
    }
    key = addDays(end, 1);
  }
  return Cycle(key: key, start: key, end: _openEnded, label: 'Eligible now');
}

/// The cycle containing [on], for a recurring benefit. [Cadence.manual]
/// benefits have no window and return null; [Cadence.rolling] ones read
/// their window from [claims].
///
/// Walks from the anchor in whole cycle-lengths. Month arithmetic clamps
/// (Jan 31 + 1 month is Feb 28), so the step count is corrected by comparison
/// rather than derived from a month difference: clamping makes the naive
/// `(years * 12 + months)` formula land in the wrong window at month ends.
Cycle? cycleFor(
  Benefit benefit,
  Card card,
  IsoDate on, {
  List<Claim> claims = const [],
}) {
  if (benefit.cadence == Cadence.manual) return null;
  if (hasEnded(benefit, on)) return null;
  if (benefit.cadence == Cadence.rolling) {
    return _rollingCycleFor(benefit, card, on, claims);
  }
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
  final natural = addDays(addMonths(anchor, (steps + 1) * span), -1);
  // The final window of a credit that ends on a date closes on that date.
  final endsOn = benefit.endsOn;
  final end = endsOn != null && compareIsoDate(endsOn, natural) < 0
      ? endsOn
      : natural;
  return Cycle(
    key: start,
    start: start,
    end: end,
    label: cycleLabel(benefit, start),
  );
}

/// True once [on] is past the credit's `endsOn`; never for an open-ended
/// credit.
bool hasEnded(Benefit benefit, IsoDate on) {
  final endsOn = benefit.endsOn;
  return endsOn != null && compareIsoDate(on, endsOn) > 0;
}

/// The cycle that follows [cycle], or null for untracked benefits and for
/// rolling ones, whose next window exists only once a claim opens it.
Cycle? nextCycle(Benefit benefit, Card card, Cycle cycle) {
  if (benefit.cadence == Cadence.manual || benefit.cadence == Cadence.rolling) {
    return null;
  }
  return cycleFor(benefit, card, addDays(cycle.end, 1));
}

/// The cycle before [cycle].
Cycle? previousCycle(Benefit benefit, Card card, Cycle cycle) {
  if (benefit.cadence == Cadence.manual || benefit.cadence == Cadence.rolling) {
    return null;
  }
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
  final cycles = <Cycle>[];
  // Once a credit has ended, its final window is itself a closed one.
  final endsOn = benefit.endsOn;
  var cycle = current != null
      ? previousCycle(benefit, card, current)
      : endsOn != null && hasEnded(benefit, on)
      ? cycleFor(benefit, card, endsOn)
      : null;
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
  Cadence.rolling => 'Rolling',
  Cadence.manual => 'Manual',
};

/// Value released per year for a cadence. A rolling credit is amortised over
/// its interval: $120 every 48 months is $30 a year. Untracked credits are
/// counted once, since nothing says when they recur.
int annualValueOf(int valueCents, Cadence cadence, int? intervalMonths) {
  if (cadence == Cadence.rolling) {
    return intervalMonths != null && intervalMonths > 0
        ? (valueCents * 12 / intervalMonths).round()
        : valueCents;
  }
  final span = monthsPerCycle(cadence);
  if (span == null) return valueCents;
  return valueCents * (12 ~/ span);
}

/// Value a benefit releases per year; see [annualValueOf].
int annualValueCents(Benefit benefit) {
  return annualValueOf(
    benefit.valueCents,
    benefit.cadence,
    benefit.intervalMonths,
  );
}
