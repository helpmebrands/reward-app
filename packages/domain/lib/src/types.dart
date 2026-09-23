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
/// [rolling] restarts from the last claim rather than the calendar (Global
/// Entry every four years), with the gap in [Benefit.intervalMonths].
/// [manual] covers credits no cycle can track at all, which are listed but
/// never counted as at risk.
enum Cadence { monthly, quarterly, semiannual, annual, rolling, manual }

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

/// Whether the card is a personal or a business product. Classification only:
/// the Cards screen marks business cards, and filtering by kind is left to a
/// later epic.
enum CardKind { personal, business }

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
    required this.kind,
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
  final CardKind kind;

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

  /// A copy with the given fields replaced. Pass [nickname] or [last4] as
  /// null to clear them; leave them out to keep them.
  Card copyWith({
    String? issuer,
    String? product,
    String? holder,
    Object? nickname = _unset,
    CardNetwork? network,
    CardKind? kind,
    Object? last4 = _unset,
    int? annualFeeCents,
    IsoDate? anniversaryOn,
    bool? muted,
    bool? archived,
    IsoInstant? updatedAt,
  }) => Card(
    id: id,
    issuer: issuer ?? this.issuer,
    product: product ?? this.product,
    holder: holder ?? this.holder,
    nickname: identical(nickname, _unset) ? this.nickname : nickname as String?,
    network: network ?? this.network,
    kind: kind ?? this.kind,
    last4: identical(last4, _unset) ? this.last4 : last4 as String?,
    annualFeeCents: annualFeeCents ?? this.annualFeeCents,
    anniversaryOn: anniversaryOn ?? this.anniversaryOn,
    muted: muted ?? this.muted,
    archived: archived ?? this.archived,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
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
    this.intervalMonths,
    required this.enrollmentRequired,
    this.enrolledAt,
    this.enrollmentNote,
    this.enrollmentUrl,
    this.spendThresholdCents,
    this.spendMetAt,
    this.endsOn,
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

  /// Months between claims for a [Cadence.rolling] credit, which ignores the
  /// anchor. Required when rolling; the editors refuse to save without it.
  final int? intervalMonths;

  /// True when the credit must be activated on the issuer's benefits page
  /// before a cent of it can be spent. Until [enrolledAt] is set the credit is
  /// [BenefitStatus.locked]: visible, counted separately, and never dunned as
  /// if it were merely unspent.
  final bool enrollmentRequired;
  final IsoInstant? enrolledAt;

  /// Why it is blocked, shown on the locked rows.
  final String? enrollmentNote;
  final String? enrollmentUrl;

  /// Spend the issuer asks for in a year before the credit opens, in cents.
  /// Until [spendMetAt] falls inside the current year the credit is
  /// [BenefitStatus.locked] for spend, excluded from value totals and never
  /// reminded about.
  final int? spendThresholdCents;

  /// When the user said the threshold was reached; cleared by revoking.
  final IsoInstant? spendMetAt;

  /// The last day the credit can be used, for credits the issuer has
  /// announced an end to. The final window is clamped to this day and nothing
  /// follows it; afterwards the credit is skipped the way an inactive one is.
  final IsoDate? endsOn;

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

  /// A copy with the given fields replaced. The nullable fields
  /// ([description], [icon], [merchant], [intervalMonths], [enrolledAt],
  /// [enrollmentNote], [enrollmentUrl], [spendThresholdCents], [spendMetAt],
  /// [endsOn], [notes]) are cleared by passing null and kept by leaving them
  /// out.
  Benefit copyWith({
    String? cardId,
    String? name,
    Object? description = _unset,
    BenefitCategory? category,
    Object? icon = _unset,
    Object? merchant = _unset,
    int? valueCents,
    Cadence? cadence,
    CycleAnchor? anchor,
    Object? intervalMonths = _unset,
    bool? enrollmentRequired,
    Object? enrolledAt = _unset,
    Object? enrollmentNote = _unset,
    Object? enrollmentUrl = _unset,
    Object? spendThresholdCents = _unset,
    Object? spendMetAt = _unset,
    Object? endsOn = _unset,
    List<String>? redemptionSteps,
    Object? notes = _unset,
    bool? muted,
    bool? lastCallOnly,
    bool? active,
    IsoInstant? updatedAt,
  }) => Benefit(
    id: id,
    cardId: cardId ?? this.cardId,
    name: name ?? this.name,
    description: identical(description, _unset)
        ? this.description
        : description as String?,
    category: category ?? this.category,
    icon: identical(icon, _unset) ? this.icon : icon as String?,
    merchant: identical(merchant, _unset) ? this.merchant : merchant as String?,
    valueCents: valueCents ?? this.valueCents,
    cadence: cadence ?? this.cadence,
    anchor: anchor ?? this.anchor,
    intervalMonths: identical(intervalMonths, _unset)
        ? this.intervalMonths
        : intervalMonths as int?,
    enrollmentRequired: enrollmentRequired ?? this.enrollmentRequired,
    enrolledAt: identical(enrolledAt, _unset)
        ? this.enrolledAt
        : enrolledAt as IsoInstant?,
    enrollmentNote: identical(enrollmentNote, _unset)
        ? this.enrollmentNote
        : enrollmentNote as String?,
    enrollmentUrl: identical(enrollmentUrl, _unset)
        ? this.enrollmentUrl
        : enrollmentUrl as String?,
    spendThresholdCents: identical(spendThresholdCents, _unset)
        ? this.spendThresholdCents
        : spendThresholdCents as int?,
    spendMetAt: identical(spendMetAt, _unset)
        ? this.spendMetAt
        : spendMetAt as IsoInstant?,
    endsOn: identical(endsOn, _unset) ? this.endsOn : endsOn as IsoDate?,
    redemptionSteps: redemptionSteps ?? this.redemptionSteps,
    notes: identical(notes, _unset) ? this.notes : notes as String?,
    muted: muted ?? this.muted,
    lastCallOnly: lastCallOnly ?? this.lastCallOnly,
    active: active ?? this.active,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
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

  NotificationSettings copyWith({
    bool? enabled,
    String? timeOfDay,
    int? minValueCents,
    bool? annualFeeReminder,
    bool? enrollmentReminder,
  }) => NotificationSettings(
    enabled: enabled ?? this.enabled,
    timeOfDay: timeOfDay ?? this.timeOfDay,
    minValueCents: minValueCents ?? this.minValueCents,
    annualFeeReminder: annualFeeReminder ?? this.annualFeeReminder,
    enrollmentReminder: enrollmentReminder ?? this.enrollmentReminder,
  );
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

  Settings copyWith({
    NotificationSettings? notifications,
    int? useSoonDays,
    ThemeSetting? theme,
    String? holderFilter,
  }) => Settings(
    notifications: notifications ?? this.notifications,
    useSoonDays: useSoonDays ?? this.useSoonDays,
    theme: theme ?? this.theme,
    holderFilter: holderFilter ?? this.holderFilter,
  );
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

  AppData copyWith({
    List<Card>? cards,
    List<Benefit>? benefits,
    List<Claim>? claims,
    Settings? settings,
  }) => AppData(
    version: version,
    cards: cards ?? this.cards,
    benefits: benefits ?? this.benefits,
    claims: claims ?? this.claims,
    settings: settings ?? this.settings,
  );
}

/// Marks a nullable `copyWith` argument as not passed, so null can mean
/// "clear it".
const Object _unset = Object();
