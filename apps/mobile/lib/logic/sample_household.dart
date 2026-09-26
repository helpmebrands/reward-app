import 'package:domain/domain.dart';

/// The day the sample household is seen on.
const sampleToday = '2026-09-16';

Card _card(String id, String label, {CardKind kind = CardKind.personal}) =>
    Card(
      id: id,
      issuer: 'American Express',
      product: 'Platinum',
      label: label,
      network: CardNetwork.amex,
      kind: kind,
      annualFeeCents: 89500,
      anniversaryOn: '2021-03-14',
      archived: false,
      createdAt: '2026-01-01T00:00:00.000Z',
      updatedAt: '2026-01-01T00:00:00.000Z',
    );

Benefit _benefit(
  String id,
  String cardId,
  String name,
  int valueCents, {
  Cadence cadence = Cadence.monthly,
  int? intervalMonths,
  bool enrollmentRequired = false,
  String? merchant,
  int? spendThresholdCents,
  IsoDate? endsOn,
  IsoInstant? optedOutAt,
}) => Benefit(
  id: id,
  cardId: cardId,
  name: name,
  category: BenefitCategory.other,
  merchant: merchant,
  valueCents: valueCents,
  cadence: cadence,
  anchor: CycleAnchor.calendar,
  intervalMonths: intervalMonths,
  enrollmentRequired: enrollmentRequired,
  spendThresholdCents: spendThresholdCents,
  endsOn: endsOn,
  redemptionSteps: const [],
  lastCallOnly: false,
  active: true,
  optedOutAt: optedOutAt,
  createdAt: '2026-01-01T00:00:00.000Z',
  updatedAt: '2026-01-01T00:00:00.000Z',
);

/// Two Platinums with a credit in every tone, as the previews and the
/// welcome slides show them.
AppData sampleHousehold() => AppData(
  version: 1,
  // Kathy's is a business card, so the Cards screen and the card editor
  // previews show the kind.
  cards: [
    _card('jim', 'Jim’s Platinum'),
    _card('kathy', 'Kathy’s Platinum', kind: CardKind.business),
  ],
  benefits: [
    _benefit('u1', 'jim', 'Uber Cash', 1500, merchant: 'Uber'),
    _benefit('u2', 'kathy', 'Uber Cash', 1500, merchant: 'Uber'),
    _benefit(
      'r1',
      'kathy',
      'Resy Dining Credit',
      10000,
      cadence: Cadence.quarterly,
      endsOn: '2026-12-31',
    ),
    _benefit(
      'e1',
      'kathy',
      'Equinox Credit',
      30000,
      cadence: Cadence.annual,
      enrollmentRequired: true,
    ),
    _benefit(
      'd1',
      'kathy',
      'Dell Bonus',
      100000,
      cadence: Cadence.annual,
      spendThresholdCents: 500000,
    ),
    // Opted out, so the card editor shows its "Opted out" group.
    _benefit(
      'o1',
      'kathy',
      'Oura Ring Credit',
      20000,
      cadence: Cadence.annual,
      optedOutAt: '2026-05-01T09:00:00.000Z',
    ),
    _benefit(
      'g1',
      'jim',
      'Global Entry',
      12000,
      cadence: Cadence.rolling,
      intervalMonths: 48,
    ),
  ],
  claims: const [
    Claim(
      id: 'c1',
      benefitId: 'u1',
      cycleKey: '2026-09-01',
      amountCents: 1500,
      claimedAt: '2026-09-10T12:00:00.000Z',
    ),
    Claim(
      id: 'c2',
      benefitId: 'r1',
      cycleKey: '2026-07-01',
      amountCents: 1000,
      claimedAt: '2026-09-02T12:00:00.000Z',
      note: 'Lunch',
    ),
    Claim(
      id: 'c3',
      benefitId: 'r1',
      cycleKey: '2026-07-01',
      amountCents: 2000,
      claimedAt: '2026-09-10T12:00:00.000Z',
    ),
  ],
  settings: const Settings(useSoonDays: 30, theme: ThemeSetting.system),
);
