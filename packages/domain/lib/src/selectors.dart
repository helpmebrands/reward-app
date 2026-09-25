/// Selectors: statuses, the five totals, overlaps, the missed ledger and card
/// value, resolved from [AppData] for a given day.
library;

import 'cycles.dart';
import 'dates.dart';
import 'types.dart';

/// Claims indexed by benefit + cycle, so resolving every credit stays O(n).
typedef ClaimIndex = Map<String, int>;

String _keyOf(String benefitId, String cycleKey) {
  // Ids are UUIDs and cycle keys are ISO dates, so neither can contain '::'.
  return '$benefitId::$cycleKey';
}

ClaimIndex indexClaims(List<Claim> claims) {
  final index = <String, int>{};
  for (final claim in claims) {
    final key = _keyOf(claim.benefitId, claim.cycleKey);
    index[key] = (index[key] ?? 0) + claim.amountCents;
  }
  return index;
}

int claimedIn(ClaimIndex claims, String benefitId, String cycleKey) {
  return claims[_keyOf(benefitId, cycleKey)] ?? 0;
}

/// Why a credit cannot be spent yet. Enrolment outranks spend.
enum LockReason { enrollment, spend }

/// What stands between the user and the credit, or null when nothing does:
/// an unticked enrolment box, or a spend threshold not yet met this year.
LockReason? lockReason(Benefit benefit, Card card, IsoDate on) {
  if (benefit.enrollmentRequired && benefit.enrolledAt == null) {
    return LockReason.enrollment;
  }
  if (benefit.spendThresholdCents != null &&
      !_spendMetThisYear(benefit, card, on)) {
    return LockReason.spend;
  }
  return null;
}

/// True when a credit cannot be spent until a box is ticked or a spend
/// reached.
bool isLocked(Benefit benefit, Card card, IsoDate on) {
  return lockReason(benefit, card, on) != null;
}

/// Whether the spend was met in the credit's current year: the calendar year
/// for a calendar-anchored credit, the cardmember year for an anniversary one.
bool _spendMetThisYear(Benefit benefit, Card card, IsoDate on) {
  final metAt = benefit.spendMetAt;
  if (metAt == null) return false;
  final year = cycleFor(benefit.copyWith(cadence: Cadence.annual), card, on);
  return year != null && isWithin(metAt.substring(0, 10), year.start, year.end);
}

BenefitStatus _statusFor(
  Benefit benefit,
  int claimedCents,
  int daysRemaining,
  bool locked,
  int useSoonHorizon,
) {
  if (benefit.optedOutAt != null) return BenefitStatus.optedOut;
  if (claimedCents >= benefit.valueCents) return BenefitStatus.captured;
  if (benefit.cadence == Cadence.manual) return BenefitStatus.manual;
  if (locked) return BenefitStatus.locked;
  // A rolling window has no deadline the user can miss: it is open until
  // claimed, then closed until the interval runs out.
  if (benefit.cadence == Cadence.rolling) return BenefitStatus.available;
  if (daysRemaining < 0) return BenefitStatus.missed;
  return daysRemaining <= useSoonHorizon
      ? BenefitStatus.useSoon
      : BenefitStatus.available;
}

/// Resolves one benefit against one cycle.
///
/// `locked` outranks `use_soon` deliberately: a credit stuck behind an
/// unticked box is not something the user is failing to spend, and dunning
/// them to spend it would be telling them to do something they cannot do.
BenefitInstance resolveInstance(
  Benefit benefit,
  Card card,
  Cycle cycle,
  ClaimIndex claims,
  IsoDate on, {
  int useSoonHorizon = useSoonDays,
  MemberPreferences? prefs,
}) {
  final claimedCents = claimedIn(claims, benefit.id, cycle.key);
  final daysRemaining = daysRemainingIn(cycle, on);
  final remaining = benefit.valueCents - claimedCents;
  return BenefitInstance(
    benefit: benefit,
    card: card,
    cycle: cycle,
    claimedCents: claimedCents,
    remainingCents: remaining > 0 ? remaining : 0,
    status: _statusFor(
      benefit,
      claimedCents,
      daysRemaining,
      isLocked(benefit, card, on),
      useSoonHorizon,
    ),
    daysRemaining: daysRemaining,
    cycleProgress: cycleProgress(cycle, on),
    muted: prefs?.isMuted(benefit) ?? false,
  );
}

/// A stand-in window for [Cadence.manual] credits, which have no real cycle.
Cycle _untrackedCycle(IsoDate on) {
  return Cycle(key: on, start: on, end: '2999-12-31', label: 'Untracked');
}

/// A stable sort, matching the JavaScript reference: equal elements keep
/// their input order, which [List.sort] does not promise.
List<T> _stableSorted<T>(Iterable<T> items, int Function(T a, T b) compare) {
  final indexed = items.toList().asMap().entries.toList()
    ..sort((a, b) {
      final order = compare(a.value, b.value);
      return order != 0 ? order : a.key - b.key;
    });
  return indexed.map((entry) => entry.value).toList();
}

/// Every active benefit resolved against its current cycle, ordered by what
/// the user is closest to losing. [prefs] are the reading member's, which
/// decide [BenefitInstance.muted]; without them nothing is muted.
List<BenefitInstance> currentInstances(
  AppData data, [
  IsoDate? on,
  MemberPreferences? prefs,
]) {
  final day = on ?? todayIso();
  final claims = indexClaims(data.claims);
  final cardsById = {for (final card in data.cards) card.id: card};
  final instances = <BenefitInstance>[];

  for (final benefit in data.benefits) {
    if (!benefit.active || hasEnded(benefit, day)) continue;
    final card = cardsById[benefit.cardId];
    if (card == null || card.archived) continue;
    final cycle =
        cycleFor(benefit, card, day, claims: data.claims) ??
        _untrackedCycle(day);
    instances.add(
      resolveInstance(
        benefit,
        card,
        cycle,
        claims,
        day,
        useSoonHorizon: data.settings.useSoonDays,
        prefs: prefs,
      ),
    );
  }

  return _stableSorted(instances, compareByUrgency);
}

const Map<BenefitStatus, int> _statusOrder = {
  BenefitStatus.useSoon: 0,
  BenefitStatus.available: 1,
  BenefitStatus.locked: 2,
  BenefitStatus.manual: 3,
  BenefitStatus.captured: 4,
  BenefitStatus.missed: 5,
  BenefitStatus.optedOut: 6,
};

/// Ladder position first, then soonest deadline, then biggest amount at stake.
int compareByUrgency(BenefitInstance a, BenefitInstance b) {
  final byStatus = _statusOrder[a.status]! - _statusOrder[b.status]!;
  if (byStatus != 0) return byStatus;
  if (a.daysRemaining != b.daysRemaining) {
    return a.daysRemaining - b.daysRemaining;
  }
  return b.remainingCents - a.remainingCents;
}

/// Spendable right now: open, unlocked, and on a real cycle.
bool isClaimable(BenefitInstance instance) {
  return instance.status == BenefitStatus.useSoon ||
      instance.status == BenefitStatus.available;
}

List<BenefitInstance> byStatus(
  List<BenefitInstance> instances,
  BenefitStatus status,
) {
  return instances.where((i) => i.status == status).toList();
}

int sumRemaining(Iterable<BenefitInstance> instances) {
  return instances.fold(0, (sum, i) => sum + i.remainingCents);
}

int sumClaimed(Iterable<BenefitInstance> instances) {
  return instances.fold(0, (sum, i) => sum + i.claimedCents);
}

/// The five figures the Credits screen insists on keeping apart. Adding money
/// you can still get to money you have already lost would be meaningless, so
/// they are never summed into one total.
class Totals {
  const Totals({
    required this.claimableCents,
    required this.lockedCents,
    required this.capturedCents,
    required this.missedCents,
    this.optedOutCents = 0,
  });

  /// Open and spendable. Today's headline number.
  final int claimableCents;

  /// Behind an enrolment box; excluded from claimable on purpose.
  final int lockedCents;

  /// Already used this cycle.
  final int capturedCents;

  /// Windows that closed unused, this calendar year.
  final int missedCents;

  /// A year's value of the credits the household opted out of.
  final int optedOutCents;

  @override
  bool operator ==(Object other) =>
      other is Totals &&
      other.claimableCents == claimableCents &&
      other.lockedCents == lockedCents &&
      other.capturedCents == capturedCents &&
      other.missedCents == missedCents &&
      other.optedOutCents == optedOutCents;

  @override
  int get hashCode => Object.hash(
    claimableCents,
    lockedCents,
    capturedCents,
    missedCents,
    optedOutCents,
  );

  @override
  String toString() =>
      'Totals(claimable: $claimableCents, locked: $lockedCents, '
      'captured: $capturedCents, missed: $missedCents, '
      'optedOut: $optedOutCents)';
}

Totals totalsFor(List<BenefitInstance> instances, int missedCents) {
  final optedOut = byStatus(instances, BenefitStatus.optedOut);
  return Totals(
    claimableCents: sumRemaining(instances.where(isClaimable)),
    lockedCents: sumRemaining(byStatus(instances, BenefitStatus.locked)),
    capturedCents: sumClaimed(
      instances.where((i) => i.status != BenefitStatus.optedOut),
    ),
    missedCents: missedCents,
    optedOutCents: optedOut.fold(
      0,
      (sum, i) => sum + annualValueCents(i.benefit),
    ),
  );
}

/// Open credits whose window closes within the "Use soon" horizon.
List<BenefitInstance> useSoon(List<BenefitInstance> instances) {
  return byStatus(instances, BenefitStatus.useSoon);
}

/// The date the nearest open window closes, which Today headlines.
IsoDate? nextReset(List<BenefitInstance> instances) {
  final open = instances.where(isClaimable).toList();
  if (open.isEmpty) return null;
  return open.fold<IsoDate>(
    open.first.cycle.end,
    (soonest, i) =>
        compareIsoDate(i.cycle.end, soonest) < 0 ? i.cycle.end : soonest,
  );
}

class OverlapGroup {
  const OverlapGroup({
    required this.label,
    required this.instances,
    required this.remainingCents,
    required this.sameProduct,
  });

  /// The credit both cards carry, e.g. "Resy Dining Credit".
  final String label;
  final List<BenefitInstance> instances;

  /// Combined value still unclaimed across the group this cycle.
  final int remainingCents;

  /// True when the same product is held by two people in the household.
  final bool sameProduct;
}

/// Credits that exist twice.
///
/// The design's premise: the household holds the same Platinum twice, so every
/// credit on it exists twice and one booking cannot draw on both. Matching is
/// by merchant when set, otherwise by credit name; name alone would collide
/// across issuers that happen to use the same wording.
List<OverlapGroup> findOverlaps(List<BenefitInstance> instances) {
  final groups = <String, List<BenefitInstance>>{};

  for (final instance in instances) {
    if (!isClaimable(instance) && instance.status != BenefitStatus.locked) {
      continue;
    }
    final merchant = instance.benefit.merchant?.trim().toLowerCase();
    final key = merchant != null && merchant.isNotEmpty
        ? 'm:$merchant'
        : 'n:${instance.benefit.name.trim().toLowerCase()}';
    groups.putIfAbsent(key, () => []).add(instance);
  }

  final overlaps = <OverlapGroup>[];
  for (final group in groups.values) {
    final first = group.first;
    // Two rows on the *same* card are not an overlap, they are two credits.
    if (group.map((i) => i.card.id).toSet().length < 2) continue;
    overlaps.add(
      OverlapGroup(
        label: first.benefit.name,
        instances: _stableSorted(
          group,
          (a, b) => cardLabel(a.card).compareTo(cardLabel(b.card)),
        ),
        remainingCents: sumRemaining(group),
        sameProduct:
            group
                .map((i) => '${i.card.issuer} ${i.card.product}')
                .toSet()
                .length ==
            1,
      ),
    );
  }

  return _stableSorted(overlaps, (a, b) => b.remainingCents - a.remainingCents);
}

class MissedCycle {
  const MissedCycle({
    required this.benefit,
    required this.card,
    required this.cycle,
    required this.missedCents,
  });

  final Benefit benefit;
  final Card card;
  final Cycle cycle;
  final int missedCents;
}

/// Windows that closed with money left in them, newest first.
///
/// This is computed rather than stored: a closed cycle with no claim against
/// it is a miss, and deriving it means the ledger is always consistent with
/// the claims the user actually logged.
List<MissedCycle> missedCycles(
  AppData data, [
  IsoDate? on,
  int lookbackCycles = 24,
]) {
  final day = on ?? todayIso();
  final claims = indexClaims(data.claims);
  final cardsById = {for (final card in data.cards) card.id: card};
  final missed = <MissedCycle>[];
  // Only count windows that opened after the card was added: the app cannot
  // know whether a credit was used before it started tracking.
  for (final benefit in data.benefits) {
    // Manual credits have no window to miss; rolling ones close only by claim.
    if (!benefit.active ||
        benefit.optedOutAt != null ||
        benefit.cadence == Cadence.manual ||
        benefit.cadence == Cadence.rolling) {
      continue;
    }
    final card = cardsById[benefit.cardId];
    if (card == null || card.archived) continue;
    final trackedFrom = card.createdAt.substring(0, 10);
    // A credit reactivated after an opt-out is not blamed for the windows
    // that closed while it was opted out.
    final resumedOn = benefit.trackedFrom;

    for (final cycle in closedCyclesBefore(
      benefit,
      card,
      day,
      lookbackCycles,
    )) {
      if (compareIsoDate(cycle.start, trackedFrom) < 0) break;
      if (resumedOn != null && compareIsoDate(cycle.end, resumedOn) < 0) break;
      final claimed = claimedIn(claims, benefit.id, cycle.key);
      final shortfall = benefit.valueCents - claimed;
      if (shortfall > 0) {
        missed.add(
          MissedCycle(
            benefit: benefit,
            card: card,
            cycle: cycle,
            missedCents: shortfall,
          ),
        );
      }
    }
  }

  return _stableSorted(
    missed,
    (a, b) => compareIsoDate(b.cycle.end, a.cycle.end),
  );
}

class Leak {
  const Leak({
    required this.label,
    required this.when,
    required this.missedCents,
    required this.occurrences,
    this.icon,
  });

  final String label;

  /// e.g. "Jan – Aug 2026".
  final String when;
  final int missedCents;
  final int occurrences;
  final String? icon;
}

/// Recurring credits that keep expiring unclaimed, worst first.
///
/// Grouped by credit rather than listed per cycle, because "Uber Cash, eight
/// months, $240" is a fixable habit while eight separate $15 rows are noise.
List<Leak> biggestLeaks(List<MissedCycle> missed, {int limit = 5}) {
  final groups = <String, List<MissedCycle>>{};
  for (final entry in missed) {
    groups
        .putIfAbsent('${entry.benefit.name}::${entry.card.id}', () => [])
        .add(entry);
  }

  final leaks = <Leak>[];
  for (final group in groups.values) {
    final first = group.first;
    final last = group.last;
    leaks.add(
      Leak(
        label: group.length > 1
            ? '${first.benefit.name} × ${group.length}'
            : first.benefit.name,
        when: group.length > 1
            ? '${last.cycle.label} – ${first.cycle.label}'
            : first.cycle.label,
        missedCents: group.fold(0, (sum, entry) => sum + entry.missedCents),
        occurrences: group.length,
        icon: first.benefit.icon,
      ),
    );
  }

  final ranked = _stableSorted(leaks, (a, b) => b.missedCents - a.missedCents);
  return ranked.length > limit ? ranked.sublist(0, limit) : ranked;
}

class MonthTotals {
  MonthTotals({
    required this.month,
    required this.label,
    this.capturedCents = 0,
    this.missedCents = 0,
  });

  /// `YYYY-MM`.
  final String month;
  final String label;
  int capturedCents;
  int missedCents;
}

const List<String> _monthLabels = [
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

/// Captured against missed, by month: the Value tab's chart.
List<MonthTotals> monthlyTotals(
  AppData data,
  List<MissedCycle> missed, {
  IsoDate? on,
  int months = 9,
}) {
  final day = on ?? todayIso();
  final buckets = <String, MonthTotals>{};
  final year = int.parse(day.substring(0, 4));
  final month = int.parse(day.substring(5, 7));

  for (var back = months - 1; back >= 0; back--) {
    final zeroBased = year * 12 + (month - 1) - back;
    final bucketYear = (zeroBased - zeroBased % 12) ~/ 12;
    final key =
        '$bucketYear-${(zeroBased % 12 + 1).toString().padLeft(2, '0')}';
    buckets[key] = MonthTotals(month: key, label: _monthLabels[zeroBased % 12]);
  }

  for (final claim in data.claims) {
    final bucket = buckets[claim.claimedAt.substring(0, 7)];
    if (bucket != null) bucket.capturedCents += claim.amountCents;
  }
  for (final entry in missed) {
    // A miss lands in the month its window closed, which is when the money
    // actually went away.
    final bucket = buckets[entry.cycle.end.substring(0, 7)];
    if (bucket != null) bucket.missedCents += entry.missedCents;
  }

  return buckets.values.toList();
}

class CardSummary {
  const CardSummary({
    required this.card,
    required this.instances,
    required this.potentialValueCents,
    required this.annualValueCents,
    required this.optedOutCents,
    required this.capturedCents,
    required this.claimableCents,
    required this.lockedCents,
    required this.missedCents,
    required this.annualFeeCents,
    required this.netCents,
    required this.feeProgress,
    required this.daysUntilRenewal,
  });

  final Card card;
  final List<BenefitInstance> instances;

  /// Value this card could release over a full year, opted-out credits
  /// included and spend-gated ones left out.
  final int potentialValueCents;

  /// Value the household will use over a full year: [potentialValueCents]
  /// without the opted-out credits. The card's verdict is judged on this.
  final int annualValueCents;

  /// A year's value of this card's opted-out credits.
  final int optedOutCents;

  /// Claimed so far this cardmember year.
  final int capturedCents;

  /// Still claimable in the current windows.
  final int claimableCents;
  final int lockedCents;
  final int missedCents;
  final int annualFeeCents;

  /// Captured minus the fee. Negative means the card is not paying for itself.
  final int netCents;

  /// Captured as a share of the fee, 0..1+: the break-even bar.
  final double feeProgress;
  final int daysUntilRenewal;
}

CardSummary summarizeCard(
  Card card,
  AppData data,
  List<BenefitInstance> instances,
  List<MissedCycle> missed, [
  IsoDate? on,
]) {
  final day = on ?? todayIso();
  final mine = instances.where((i) => i.card.id == card.id).toList();
  final benefits = data.benefits.where((b) => b.cardId == card.id && b.active);
  final capturedCents = claimedThisCardYear(card, data, day);
  // A spend-gated credit is not the card's to give until the spend is met.
  int valueOf(Iterable<Benefit> benefits) => benefits.fold(
    0,
    (sum, b) =>
        sum +
        (lockReason(b, card, day) == LockReason.spend
            ? 0
            : annualValueCents(b)),
  );
  final potential = valueOf(benefits);
  final optedOut = valueOf(benefits.where((b) => b.optedOutAt != null));
  return CardSummary(
    card: card,
    instances: mine,
    potentialValueCents: potential,
    annualValueCents: potential - optedOut,
    optedOutCents: optedOut,
    capturedCents: capturedCents,
    claimableCents: sumRemaining(mine.where(isClaimable)),
    lockedCents: sumRemaining(
      mine.where((i) => i.status == BenefitStatus.locked),
    ),
    missedCents: missed
        .where((m) => m.card.id == card.id)
        .fold(0, (sum, m) => sum + m.missedCents),
    annualFeeCents: card.annualFeeCents,
    netCents: capturedCents - card.annualFeeCents,
    feeProgress: card.annualFeeCents > 0
        ? capturedCents / card.annualFeeCents
        : 1,
    daysUntilRenewal: daysUntilRenewal(card, day),
  );
}

/// A stand-in benefit used to reuse the cycle maths for card-level windows.
Benefit _cardYearBenefit(Card card) {
  return Benefit(
    id: '${card.id}-year',
    cardId: card.id,
    name: 'Cardmember year',
    category: BenefitCategory.feeCredit,
    valueCents: card.annualFeeCents,
    cadence: Cadence.annual,
    anchor: CycleAnchor.anniversary,
    enrollmentRequired: false,
    redemptionSteps: const [],
    lastCallOnly: false,
    active: true,
    createdAt: card.createdAt,
    updatedAt: card.updatedAt,
  );
}

/// The start of the cardmember year containing [on].
IsoDate cardYearStart(Card card, [IsoDate? on]) {
  final day = on ?? todayIso();
  return cycleFor(_cardYearBenefit(card), card, day)?.start ?? day;
}

/// Cents claimed since the card's most recent anniversary.
int claimedThisCardYear(Card card, AppData data, [IsoDate? on]) {
  final day = on ?? todayIso();
  final benefitIds = data.benefits
      .where((b) => b.cardId == card.id)
      .map((b) => b.id)
      .toSet();
  final yearStart = cardYearStart(card, day);
  return data.claims
      .where(
        (claim) =>
            benefitIds.contains(claim.benefitId) &&
            claim.claimedAt.substring(0, 10).compareTo(yearStart) >= 0,
      )
      .fold(0, (sum, claim) => sum + claim.amountCents);
}

/// Days until the annual fee posts again.
int daysUntilRenewal(Card card, [IsoDate? on]) {
  final day = on ?? todayIso();
  final cycle = cycleFor(_cardYearBenefit(card), card, day);
  return cycle != null ? daysBetween(day, cycle.end) + 1 : 0;
}

/// A card's display name: its label, or its product name when it has none.
/// Unique within the household ([labelError]).
String cardLabel(Card card) {
  final label = card.label?.trim();
  if (label != null && label.isNotEmpty) return label;
  return productName(card.issuer, card.product);
}

/// `issuer product`, the name a card has before anyone labels it.
String productName(String issuer, String product) {
  final joined = [issuer, product].where((s) => s.isNotEmpty).join(' ').trim();
  return joined.isEmpty ? 'Card' : joined;
}

/// The label to propose for a new card of this product: null while its
/// product name is free, otherwise the first free `<product> (n)` from 1.
/// The proposal is stored as the card's label, so deleting a card later
/// renames nothing.
String? defaultLabel(List<Card> cards, String issuer, String product) {
  final taken = {for (final card in cards) _nameKey(cardLabel(card))};
  final name = productName(issuer, product);
  if (!taken.contains(_nameKey(name))) return null;
  for (var n = 1; ; n++) {
    final candidate = '$name ($n)';
    if (!taken.contains(_nameKey(candidate))) return candidate;
  }
}

String _nameKey(String name) => name.trim().toLowerCase();

String categoryLabel(BenefitCategory category) => switch (category) {
  BenefitCategory.travel => 'Travel',
  BenefitCategory.dining => 'Dining',
  BenefitCategory.shopping => 'Shopping',
  BenefitCategory.entertainment => 'Entertainment',
  BenefitCategory.rideshare => 'Rideshare / Food',
  BenefitCategory.wellness => 'Health / Fitness',
  BenefitCategory.lodging => 'Lodging',
  BenefitCategory.airline => 'Airline',
  BenefitCategory.streaming => 'Streaming',
  BenefitCategory.feeCredit => 'Fee credit',
  BenefitCategory.other => 'Other',
};

String statusLabel(BenefitStatus status) => switch (status) {
  BenefitStatus.useSoon => 'Use soon',
  BenefitStatus.available => 'Available',
  BenefitStatus.locked => 'Locked',
  BenefitStatus.captured => 'Captured',
  BenefitStatus.manual => 'Manual',
  BenefitStatus.missed => 'Missed',
  BenefitStatus.optedOut => 'Opted out',
};
