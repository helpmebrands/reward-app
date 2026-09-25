import 'package:domain/domain.dart';

/// Test fixtures, so each test states only what it is actually about. The
/// values mirror the retired PWA's `factories.ts`.

/// The PWA's default settings: a 30-day use-soon horizon. Reminders are a
/// member's, in [defaultMemberPreferences].
const Settings defaultSettings = Settings(
  useSoonDays: 30,
  theme: ThemeSetting.system,
);

Card makeCard({
  String id = 'card-1',
  String issuer = 'American Express',
  String product = 'Platinum',
  String? label,
  CardKind kind = CardKind.personal,
  int annualFeeCents = 89500,
  IsoDate anniversaryOn = '2020-03-14',
  bool archived = false,
  IsoInstant createdAt = '2020-03-14T00:00:00.000Z',
}) {
  return Card(
    id: id,
    issuer: issuer,
    product: product,
    label: label,
    network: CardNetwork.amex,
    kind: kind,
    annualFeeCents: annualFeeCents,
    anniversaryOn: anniversaryOn,
    archived: archived,
    createdAt: createdAt,
    updatedAt: '2020-03-14T00:00:00.000Z',
  );
}

Benefit makeBenefit(
  Cadence cadence, {
  String id = 'benefit-1',
  String cardId = 'card-1',
  String name = 'Test credit',
  String? merchant,
  int valueCents = 2500,
  CycleAnchor anchor = CycleAnchor.calendar,
  int? intervalMonths,
  bool enrollmentRequired = false,
  IsoInstant? enrolledAt,
  int? spendThresholdCents,
  IsoInstant? spendMetAt,
  IsoDate? endsOn,
  bool lastCallOnly = false,
  bool active = true,
  IsoInstant? optedOutAt,
  IsoDate? trackedFrom,
}) {
  return Benefit(
    id: id,
    cardId: cardId,
    name: name,
    category: BenefitCategory.other,
    merchant: merchant,
    valueCents: valueCents,
    cadence: cadence,
    anchor: anchor,
    intervalMonths: intervalMonths,
    enrollmentRequired: enrollmentRequired,
    enrolledAt: enrolledAt,
    spendThresholdCents: spendThresholdCents,
    spendMetAt: spendMetAt,
    endsOn: endsOn,
    redemptionSteps: const [],
    lastCallOnly: lastCallOnly,
    active: active,
    optedOutAt: optedOutAt,
    trackedFrom: trackedFrom,
    createdAt: '2020-03-14T00:00:00.000Z',
    updatedAt: '2020-03-14T00:00:00.000Z',
  );
}

Claim makeClaim({
  String id = 'claim-1',
  String benefitId = 'benefit-1',
  IsoDate cycleKey = '2026-09-01',
  int amountCents = 2500,
  IsoInstant claimedAt = '2026-09-10T12:00:00.000Z',
}) {
  return Claim(
    id: id,
    benefitId: benefitId,
    cycleKey: cycleKey,
    amountCents: amountCents,
    claimedAt: claimedAt,
  );
}

AppData makeData({
  List<Card>? cards,
  List<Benefit>? benefits,
  List<Claim> claims = const [],
  Settings settings = defaultSettings,
}) {
  return AppData(
    version: 1,
    cards: cards ?? [makeCard()],
    benefits: benefits ?? [makeBenefit(Cadence.monthly)],
    claims: claims,
    settings: settings,
  );
}
