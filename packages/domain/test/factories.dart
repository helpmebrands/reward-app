import 'package:domain/domain.dart';

/// Test fixtures, so each test states only what it is actually about. The
/// values mirror the PWA's `apps/pwa/tests/factories.ts`.

Card makeCard({
  String id = 'card-1',
  String holder = 'Jim',
  int annualFeeCents = 89500,
  IsoDate anniversaryOn = '2020-03-14',
  bool muted = false,
  bool archived = false,
  IsoInstant createdAt = '2020-03-14T00:00:00.000Z',
}) {
  return Card(
    id: id,
    issuer: 'American Express',
    product: 'Platinum',
    holder: holder,
    network: CardNetwork.amex,
    annualFeeCents: annualFeeCents,
    anniversaryOn: anniversaryOn,
    muted: muted,
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
  bool enrollmentRequired = false,
  IsoInstant? enrolledAt,
  bool muted = false,
  bool lastCallOnly = false,
  bool active = true,
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
    enrollmentRequired: enrollmentRequired,
    enrolledAt: enrolledAt,
    redemptionSteps: const [],
    muted: muted,
    lastCallOnly: lastCallOnly,
    active: active,
    createdAt: '2020-03-14T00:00:00.000Z',
    updatedAt: '2020-03-14T00:00:00.000Z',
  );
}
