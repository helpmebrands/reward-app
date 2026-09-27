/// The value bar's four segments: what a credit, a card or the household has
/// earned, still has available, missed and opted out of.
library;

import 'cycles.dart';
import 'dates.dart';
import 'selectors.dart';
import 'types.dart';

/// Earned · Available · Missed · Opt out, in cents.
class ValueBreakdown {
  const ValueBreakdown({
    this.earnedCents = 0,
    this.availableCents = 0,
    this.missedCents = 0,
    this.optOutCents = 0,
  });

  static const ValueBreakdown zero = ValueBreakdown();

  /// Claimed in the windows counted.
  final int earnedCents;

  /// Still unclaimed in a window that is open.
  final int availableCents;

  /// Left unclaimed in a window that has closed.
  final int missedCents;

  /// The full window value of credits the household opted out of or never
  /// enrolled in.
  final int optOutCents;

  int get totalCents =>
      earnedCents + availableCents + missedCents + optOutCents;

  ValueBreakdown operator +(ValueBreakdown other) => ValueBreakdown(
    earnedCents: earnedCents + other.earnedCents,
    availableCents: availableCents + other.availableCents,
    missedCents: missedCents + other.missedCents,
    optOutCents: optOutCents + other.optOutCents,
  );

  @override
  bool operator ==(Object other) =>
      other is ValueBreakdown &&
      other.earnedCents == earnedCents &&
      other.availableCents == availableCents &&
      other.missedCents == missedCents &&
      other.optOutCents == optOutCents;

  @override
  int get hashCode =>
      Object.hash(earnedCents, availableCents, missedCents, optOutCents);

  @override
  String toString() =>
      'ValueBreakdown(earned: $earnedCents, available: $availableCents, '
      'missed: $missedCents, optOut: $optOutCents)';
}

bool _isOptOut(Benefit benefit) =>
    benefit.optedOutAt != null ||
    (benefit.enrollmentRequired && benefit.enrolledAt == null);

/// One credit's current window. Missed is always 0: the window is still
/// open. Manual credits have no window and spend-gated ones are not the
/// card's to give yet, so both are all zero.
ValueBreakdown creditBreakdown(BenefitInstance instance) {
  final benefit = instance.benefit;
  if (benefit.cadence == Cadence.manual) return ValueBreakdown.zero;
  if (_isOptOut(benefit)) {
    return ValueBreakdown(optOutCents: benefit.valueCents);
  }
  if (instance.status == BenefitStatus.locked) return ValueBreakdown.zero;
  return ValueBreakdown(
    earnedCents: instance.claimedCents,
    availableCents: instance.remainingCents,
  );
}

/// A card's calendar year to date: every window that includes [on], plus
/// every window that closed since 1 January of [on]'s year. A window that
/// includes [on] counts whole even if it opened in an earlier year.
///
/// Closed windows follow [missedCycles]: none that opened before the card
/// was added or closed before tracking resumed, and none for opted-out or
/// un-enrolled credits, which count only their current window as opt out.
ValueBreakdown cardYearToDateBreakdown(Card card, AppData data, IsoDate on) {
  final claims = indexClaims(data.claims);
  final yearStart = '${on.substring(0, 4)}-01-01';
  final trackedFrom = card.createdAt.substring(0, 10);
  var total = ValueBreakdown.zero;

  for (final benefit in data.benefits) {
    if (benefit.cardId != card.id || !benefit.active) continue;
    if (benefit.cadence == Cadence.manual) continue;
    if (lockReason(benefit, card, on) == LockReason.spend) continue;

    final current = cycleFor(benefit, card, on, claims: data.claims);
    if (current != null) {
      total += creditBreakdown(
        resolveInstance(benefit, card, current, claims, on),
      );
    }
    if (_isOptOut(benefit)) continue;

    final resumedOn = benefit.trackedFrom;
    for (final cycle in closedCyclesBefore(benefit, card, on, 12)) {
      if (compareIsoDate(cycle.end, yearStart) < 0) break;
      if (compareIsoDate(cycle.start, trackedFrom) < 0) break;
      if (resumedOn != null && compareIsoDate(cycle.end, resumedOn) < 0) break;
      final claimed = claimedIn(claims, benefit.id, cycle.key);
      final shortfall = benefit.valueCents - claimed;
      total += ValueBreakdown(
        earnedCents: claimed,
        missedCents: shortfall > 0 ? shortfall : 0,
      );
    }
  }
  return total;
}

/// The sum of every unarchived card's [cardYearToDateBreakdown].
ValueBreakdown householdBreakdown(AppData data, IsoDate on) {
  return data.cards
      .where((card) => !card.archived)
      .fold(
        ValueBreakdown.zero,
        (sum, card) => sum + cardYearToDateBreakdown(card, data, on),
      );
}
