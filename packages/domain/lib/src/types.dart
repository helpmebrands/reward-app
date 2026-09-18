/// Core domain types for HelpMe Reward.
///
/// The shape follows the design's premise: this is a *household* deadline
/// manager. The hard case is not two different cards with clashing offers; it
/// is the same card held twice by two people, where every credit exists twice
/// and a single booking cannot draw on both.
///
/// Dates are calendar dates (`YYYY-MM-DD`), not timestamps: "September 2026"
/// is a calendar concept and must not shift when the user crosses a timezone.
/// Instants (when a claim was recorded) use full ISO-8601 strings.
library;

/// A calendar date, `YYYY-MM-DD`.
typedef IsoDate = String;

/// An instant, ISO-8601 with timezone, e.g. `2026-09-16T14:03:00.000Z`.
typedef IsoInstant = String;

typedef Uuid = String;

/// How often a credit refreshes.
///
/// [manual] covers credits no cycle can track (Global Entry every four to four
/// and a half years), which are listed but never counted as at risk.
enum Cadence { monthly, quarterly, semiannual, annual, manual }

/// What a recurring cycle is measured from.
///
/// - [calendar]: the Gregorian calendar (Jan 1, quarter starts, month starts).
/// - [anniversary]: the card's account anniversary, the "cardmember year".
///
/// Getting this wrong is the commonest way people lose a credit, so it is
/// recorded per benefit rather than inferred from the cadence.
enum CycleAnchor { calendar, anniversary }

enum BenefitCategory {
  travel,
  dining,
  shopping,
  entertainment,
  rideshare,
  wellness,
  lodging,
  airline,
  streaming,
  feeCredit,
  other,
}

enum CardNetwork { amex, visa, mastercard, discover, other }

/// The status ladder, taken from the design.
///
/// [locked] and [manual] are deliberately *not* variants of "unclaimed":
/// Today's headline excludes both, because money behind an unticked enrolment
/// box is not money you are failing to spend.
enum BenefitStatus {
  /// Enrolment required and not yet confirmed. Nothing is spendable.
  locked,

  /// No cycle tracks it; the user reviews it by hand.
  manual,

  /// Open, and the window closes within [useSoonDays].
  useSoon,

  /// Open, with more than a month of runway.
  available,

  /// Fully used this cycle.
  captured,

  /// The window closed with value left on the table.
  missed,
}

/// The boundary between "Use soon" and "Available", in days.
const int useSoonDays = 30;

/// How hard a reminder rung pushes. [permissive] is a "you can use me" with
/// no urgency; [urgent] is the last call.
enum Tone { permissive, notice, urgent }

enum ThemeSetting { system, light, dark }

class Card {
  const Card({
    required this.id,
    required this.issuer,
    required this.product,
    required this.holder,
    this.nickname,
    required this.network,
    this.last4,
    required this.annualFeeCents,
    required this.anniversaryOn,
    required this.muted,
    required this.archived,
    required this.createdAt,
    required this.updatedAt,
  });

  final Uuid id;

  /// e.g. "American Express".
  final String issuer;

  /// e.g. "Platinum".
  final String product;

  /// Who in the household holds this card. Two people holding the same product
  /// is the case the app exists for, so this is what distinguishes them.
  final String holder;

  /// User-supplied label that wins over `issuer product` in the UI.
  final String? nickname;
  final CardNetwork network;

  /// Display only; never a full PAN.
  final String? last4;
  final int annualFeeCents;

  /// Account open / renewal date. Anchors [CycleAnchor.anniversary] cycles and
  /// the annual fee countdown. Only the month and day matter for recurrence.
  final IsoDate anniversaryOn;

  /// Silences every credit on this card without losing their state.
  final bool muted;
  final bool archived;
  final IsoInstant createdAt;
  final IsoInstant updatedAt;
}

class Benefit {
  const Benefit({
    required this.id,
    required this.cardId,
    required this.name,
    this.description,
    required this.category,
    this.icon,
    this.merchant,
    required this.valueCents,
    required this.cadence,
    required this.anchor,
    required this.enrollmentRequired,
    this.enrolledAt,
    this.enrollmentNote,
    this.enrollmentUrl,
    required this.redemptionSteps,
    this.notes,
    required this.muted,
    required this.lastCallOnly,
    required this.active,
    required this.createdAt,
    required this.updatedAt,
  });

  final Uuid id;
  final Uuid cardId;
  final String name;
  final String? description;
  final BenefitCategory category;

  /// Icon name, e.g. `car-profile`.
  final String? icon;

  /// Where it must be spent, e.g. "Uber", "Resy". Used to detect overlaps.
  final String? merchant;

  /// Value released per cycle, in cents.
  final int valueCents;
  final Cadence cadence;
  final CycleAnchor anchor;

  /// True when the credit must be activated on the issuer's benefits page
  /// before a cent of it can be spent. Until [enrolledAt] is set the credit is
  /// [BenefitStatus.locked]: visible, counted separately, and never dunned as
  /// if it were merely unspent.
  final bool enrollmentRequired;
  final IsoInstant? enrolledAt;

  /// Why it is blocked, shown on the locked rows.
  final String? enrollmentNote;
  final String? enrollmentUrl;

  /// Numbered "How to redeem" steps shown in the detail sheet.
  final List<String> redemptionSteps;
  final String? notes;

  /// Silences this credit's reminders; the bell on every row toggles it.
  final bool muted;

  /// Opts this credit out of its cadence's default reminder ladder in favour
  /// of a single alert on the last day.
  final bool lastCallOnly;

  /// Set false to keep history but stop tracking.
  final bool active;
  final IsoInstant createdAt;
  final IsoInstant updatedAt;
}

/// A concrete window during which a [Benefit] can be used. Derived, never
/// stored.
class Cycle {
  const Cycle({
    required this.key,
    required this.start,
    required this.end,
    required this.label,
  });

  /// Stable per-benefit identity for the window; equal to [start].
  final IsoDate key;

  /// First day the credit is usable, inclusive.
  final IsoDate start;

  /// Last day the credit is usable, inclusive.
  final IsoDate end;

  /// Human label for the period, e.g. "Sep 2026", "Q3 2026", "H2 2026".
  final String label;

  @override
  bool operator ==(Object other) =>
      other is Cycle &&
      other.key == key &&
      other.start == start &&
      other.end == end &&
      other.label == label;

  @override
  int get hashCode => Object.hash(key, start, end, label);

  @override
  String toString() => 'Cycle($key, $start..$end, $label)';
}

/// A recorded use of a credit within one cycle. Partial claims are normal.
class Claim {
  const Claim({
    required this.id,
    required this.benefitId,
    required this.cycleKey,
    required this.amountCents,
    required this.claimedAt,
    this.note,
  });

  final Uuid id;
  final Uuid benefitId;

  /// The [Cycle.key] this claim belongs to.
  final IsoDate cycleKey;
  final int amountCents;
  final IsoInstant claimedAt;
  final String? note;
}

/// A benefit resolved against a specific date: the window it is in, what has
/// been claimed, and where it sits on the ladder. This is what every screen
/// renders.
class BenefitInstance {
  const BenefitInstance({
    required this.benefit,
    required this.card,
    required this.cycle,
    required this.status,
    required this.claimedCents,
    required this.remainingCents,
    required this.daysRemaining,
    required this.cycleProgress,
    required this.muted,
  });

  final Benefit benefit;
  final Card card;
  final Cycle cycle;
  final BenefitStatus status;

  /// Cents already claimed in this cycle.
  final int claimedCents;

  /// Cents still available in this cycle; zero when locked is irrelevant.
  final int remainingCents;

  /// Whole days until the cycle closes; 0 means it closes today.
  final int daysRemaining;

  /// 0..1 progress through the cycle window, for the period bars.
  final double cycleProgress;

  /// True when reminders are silenced, by the credit or by its card.
  final bool muted;
}

/// One rung of a cadence's reminder ladder.
class LadderRung {
  const LadderRung({
    required this.daysBefore,
    required this.label,
    required this.tone,
  });

  /// Days before the window closes that this rung fires.
  final int daysBefore;

  /// Shown in the detail sheet, e.g. "One week left".
  final String label;
  final Tone tone;
}

class NotificationSettings {
  const NotificationSettings({
    required this.enabled,
    required this.timeOfDay,
    required this.minValueCents,
    required this.annualFeeReminder,
    required this.enrollmentReminder,
  });

  final bool enabled;

  /// Local time of day for reminders, `HH:MM` (24h).
  final String timeOfDay;

  /// Suppress reminders for cycles worth less than this.
  final int minValueCents;

  /// Remind before the annual fee posts.
  final bool annualFeeReminder;

  /// Remind about credits that are locked behind enrolment.
  final bool enrollmentReminder;
}

class Settings {
  const Settings({
    required this.notifications,
    required this.useSoonDays,
    required this.theme,
    required this.holderFilter,
  });

  final NotificationSettings notifications;

  /// Horizon in days for Today's "Use soon" band.
  final int useSoonDays;
  final ThemeSetting theme;

  /// Filters Today and Credits to one household member; empty means everyone.
  final String holderFilter;
}

/// The entire persisted state.
class AppData {
  const AppData({
    required this.version,
    required this.cards,
    required this.benefits,
    required this.claims,
    required this.settings,
  });

  final int version;
  final List<Card> cards;
  final List<Benefit> benefits;
  final List<Claim> claims;
  final Settings settings;
}
