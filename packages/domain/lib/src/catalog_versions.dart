/// The versioned catalogue: a card template as it stood from a date, and how
/// a card linked to a template gets today's `Benefit` from it.
///
/// A version is a whole card template with the date it takes effect. A
/// linked card stores only the household's state (enrolment, spend, claims
/// through the benefit id, its anniversary); the terms come from the version
/// in force when each cycle starts, so a change reaches every linked card
/// without touching it, and a cycle already running keeps the terms it
/// started on.
library;

import 'catalog.dart';
import 'cycles.dart';
import 'dates.dart';
import 'types.dart';

/// One published version of a card template.
class TemplateVersion {
  const TemplateVersion({
    required this.version,
    required this.effectiveFrom,
    required this.template,
  });

  /// 1, 2, 3… per template.
  final int version;

  /// The first day these terms apply.
  final IsoDate effectiveFrom;

  /// The whole template as of this version, credits included.
  final CardTemplate template;

  String get templateId => template.id;
}

/// The version that applies on [date]: the latest whose [effectiveFrom] has
/// passed, the higher version winning a tie. Null before the first one.
TemplateVersion? versionInForce(List<TemplateVersion> versions, IsoDate date) {
  TemplateVersion? best;
  for (final v in versions) {
    if (compareIsoDate(v.effectiveFrom, date) > 0) continue;
    if (best == null ||
        compareIsoDate(v.effectiveFrom, best.effectiveFrom) > 0 ||
        (v.effectiveFrom == best.effectiveFrom && v.version > best.version)) {
      best = v;
    }
  }
  return best;
}

/// Who keeps a card's terms up to date. Derived from the template link, never
/// stored: a linked card follows the catalogue, anything else is the
/// household's own.
enum MaintainedBy { system, user }

MaintainedBy maintainedBy(Card card) =>
    card.templateId == null ? MaintainedBy.user : MaintainedBy.system;

/// What the household holds for one linked credit: its own id (which claims
/// point at), the card, the stable credit id, and the state no catalogue
/// change can touch.
class LinkedBenefitState {
  const LinkedBenefitState({
    required this.id,
    required this.cardId,
    required this.templateBenefitId,
    this.enrolledAt,
    this.enrollmentNote,
    this.enrollmentUrl,
    this.spendMetAt,
    this.lastCallOnly = false,
    this.active = true,
    this.optedOutAt,
    this.trackedFrom,
    required this.createdAt,
    required this.updatedAt,
  });

  final Uuid id;
  final Uuid cardId;
  final String templateBenefitId;
  final IsoInstant? enrolledAt;
  final String? enrollmentNote;
  final String? enrollmentUrl;
  final IsoInstant? spendMetAt;
  final bool lastCallOnly;
  final bool active;
  final IsoInstant? optedOutAt;
  final IsoDate? trackedFrom;
  final IsoInstant createdAt;
  final IsoInstant updatedAt;
}

/// Today's `Benefit` shape from one version's credit and the household's
/// state, so selectors, the schedule and the screens need no change.
/// [endsOn] overrides the credit's own end, earlier only.
Benefit benefitFromCredit(
  BenefitTemplate credit,
  LinkedBenefitState state, {
  IsoDate? endsOn,
}) {
  final creditEnd = credit.endsOn;
  final end = endsOn == null
      ? creditEnd
      : creditEnd == null || compareIsoDate(endsOn, creditEnd) < 0
      ? endsOn
      : creditEnd;
  return Benefit(
    id: state.id,
    cardId: state.cardId,
    templateBenefitId: credit.id,
    name: credit.name,
    description: credit.description,
    category: credit.category,
    icon: credit.icon,
    merchant: credit.merchant,
    valueCents: credit.valueCents,
    cadence: credit.cadence,
    anchor: credit.anchor,
    intervalMonths: credit.intervalMonths,
    enrollmentRequired: credit.enrollmentRequired,
    enrolledAt: state.enrolledAt,
    enrollmentNote: state.enrollmentNote,
    enrollmentUrl: state.enrollmentUrl,
    spendThresholdCents: credit.spendThresholdCents,
    spendMetAt: state.spendMetAt,
    endsOn: end,
    redemptionSteps: credit.redemptionSteps,
    notes: credit.notes,
    lastCallOnly: state.lastCallOnly,
    active: state.active,
    optedOutAt: state.optedOutAt,
    trackedFrom: state.trackedFrom,
    createdAt: state.createdAt,
    updatedAt: state.updatedAt,
  );
}

/// The linked credit as it applies on [on], or null when no version in
/// force by then has it.
///
/// - The version in force at the start of the current cycle supplies the
///   terms, so a cycle already running keeps them when a new version lands.
/// - A credit added in a version appears from its `effectiveFrom`, with that
///   version's terms, locked if it needs enrolment.
/// - A credit dropped from a version stops the day before that version's
///   `effectiveFrom`.
Benefit? resolveLinkedBenefit(
  List<TemplateVersion> versions,
  LinkedBenefitState state,
  Card card,
  IsoDate on, {
  List<Claim> claims = const [],
}) {
  final current = versionInForce(versions, on);
  if (current == null) return null;
  final credit = current.template.credit(state.templateBenefitId);

  if (credit == null) {
    // Dropped: the last earlier version that had it, ended by this one.
    final earlier = [
      for (final v in versions)
        if (compareIsoDate(v.effectiveFrom, current.effectiveFrom) < 0 &&
            v.template.credit(state.templateBenefitId) != null)
          v,
    ];
    final last = versionInForce(earlier, on);
    if (last == null) return null;
    return benefitFromCredit(
      last.template.credit(state.templateBenefitId)!,
      state,
      endsOn: addDays(current.effectiveFrom, -1),
    );
  }

  final benefit = benefitFromCredit(credit, state);
  final cycle = cycleFor(benefit, card, on, claims: claims);
  if (cycle == null ||
      compareIsoDate(cycle.start, current.effectiveFrom) >= 0) {
    return benefit;
  }
  // The cycle began under an earlier version: its terms hold until the next
  // cycle. A credit that version lacked is new, and takes the new terms.
  final older = versionInForce(
    versions,
    cycle.start,
  )?.template.credit(state.templateBenefitId);
  return older == null ? benefit : benefitFromCredit(older, state);
}
