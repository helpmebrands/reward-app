/// The card catalogue behind "Add a card".
///
/// Issuers change these terms constantly, so this is a starting point for
/// onboarding, not a source of truth: everything it creates is an ordinary
/// editable credit, and the add-card flow says so. `enrollmentRequired` is
/// the field worth getting right: it is the difference between a credit the
/// user is failing to spend and one they cannot spend at all.
///
/// The templates are generated from the PWA's `src/domain/catalog.ts` by
/// `apps/pwa/scripts/emit-catalog.ts`; edit there and regenerate.
library;

import 'types.dart';

class BenefitTemplate {
  const BenefitTemplate({
    required this.name,
    this.description,
    required this.category,
    required this.icon,
    this.merchant,
    required this.valueCents,
    required this.cadence,
    required this.anchor,
    this.enrollmentRequired = false,
    this.redemptionSteps = const [],
    this.notes,
  });

  final String name;
  final String? description;
  final BenefitCategory category;

  /// Icon name.
  final String icon;
  final String? merchant;
  final int valueCents;
  final Cadence cadence;
  final CycleAnchor anchor;
  final bool enrollmentRequired;
  final List<String> redemptionSteps;
  final String? notes;
}

class CardTemplate {
  const CardTemplate({
    required this.id,
    required this.issuer,
    required this.product,
    required this.network,
    required this.annualFeeCents,
    required this.benefits,
  });

  final String id;
  final String issuer;
  final String product;
  final CardNetwork network;
  final int annualFeeCents;
  final List<BenefitTemplate> benefits;
}

const List<CardTemplate> cardTemplates = [
  CardTemplate(
    id: 'amex-platinum',
    issuer: 'American Express',
    product: 'Platinum',
    network: CardNetwork.amex,
    annualFeeCents: 89500,
    benefits: [
      BenefitTemplate(
        name: 'Uber Cash',
        category: BenefitCategory.rideshare,
        icon: 'car-profile',
        merchant: 'Uber',
        valueCents: 1500,
        cadence: Cadence.monthly,
        anchor: CycleAnchor.calendar,
        redemptionSteps: [
          'Open the Uber app and make sure this card is the selected payment method.',
          'Spend it on a ride or an Uber Eats order before the month closes.',
          'It never rolls over — and December is \$35, not \$15.',
        ],
      ),
      BenefitTemplate(
        name: 'Digital Entertainment Credit',
        category: BenefitCategory.streaming,
        icon: 'monitor-play',
        valueCents: 2500,
        cadence: Cadence.monthly,
        anchor: CycleAnchor.calendar,
        enrollmentRequired: true,
        redemptionSteps: [
          'Enrolment is required once, on the issuer benefits page.',
          'Pay a participating subscription with the card — Disney+, Hulu, ESPN+, Peacock, NYT, WSJ, YouTube Premium, Paramount+.',
          'Up to \$25 a month; the balance does not carry forward.',
        ],
      ),
      BenefitTemplate(
        name: 'Walmart+ Membership Credit',
        category: BenefitCategory.shopping,
        icon: 'shopping-bag',
        merchant: 'Walmart',
        valueCents: 1295,
        cadence: Cadence.monthly,
        anchor: CycleAnchor.calendar,
        redemptionSteps: [
          'Pay the monthly Walmart+ membership with this card — not the annual plan.',
          '\$12.95 plus tax is reimbursed each month.',
          'Plus Ups are excluded.',
        ],
      ),
      BenefitTemplate(
        name: 'Resy Dining Credit',
        category: BenefitCategory.dining,
        icon: 'fork-knife',
        merchant: 'Resy',
        valueCents: 10000,
        cadence: Cadence.quarterly,
        anchor: CycleAnchor.calendar,
        enrollmentRequired: true,
        redemptionSteps: [
          'Enrol once, and link the Resy profile to the card.',
          'Spend at an eligible US Resy restaurant and pay with the card.',
          'Up to \$100 per quarter.',
        ],
      ),
      BenefitTemplate(
        name: 'lululemon Credit',
        category: BenefitCategory.shopping,
        icon: 'shopping-bag',
        merchant: 'lululemon',
        valueCents: 7500,
        cadence: Cadence.quarterly,
        anchor: CycleAnchor.calendar,
        enrollmentRequired: true,
        redemptionSteps: [
          'Enrolment required on the benefits page.',
          'Spend at a US lululemon store or lululemon.com with the card.',
          'Up to \$75 per quarter.',
        ],
      ),
      BenefitTemplate(
        name: 'Hotel Credit (FHR / THC)',
        category: BenefitCategory.lodging,
        icon: 'bed',
        valueCents: 30000,
        cadence: Cadence.semiannual,
        anchor: CycleAnchor.calendar,
        redemptionSteps: [
          'Book prepaid through the issuer travel portal — not direct with the hotel.',
          'Fine Hotels + Resorts, or The Hotel Collection with a two-night minimum.',
          '\$300 per half-year. One booking cannot draw on two cards.',
        ],
      ),
      BenefitTemplate(
        name: 'Airline Fee Credit',
        category: BenefitCategory.airline,
        icon: 'airplane-tilt',
        valueCents: 20000,
        cadence: Cadence.annual,
        anchor: CycleAnchor.calendar,
        redemptionSteps: [
          'Select one qualifying airline for the calendar year — the selection is per card.',
          'Charge incidental fees: checked bags, seat selection, lounge day passes.',
          'Airfare itself is not eligible.',
        ],
      ),
      BenefitTemplate(
        name: 'CLEAR+ Credit',
        category: BenefitCategory.travel,
        icon: 'fingerprint',
        merchant: 'CLEAR',
        valueCents: 21900,
        cadence: Cadence.annual,
        anchor: CycleAnchor.calendar,
        redemptionSteps: [
          'Pay the CLEAR+ membership with the card.',
          'Covers the membership in full.',
        ],
      ),
      BenefitTemplate(
        name: 'Uber One Membership Credit',
        category: BenefitCategory.rideshare,
        icon: 'moped',
        merchant: 'Uber',
        valueCents: 12000,
        cadence: Cadence.annual,
        anchor: CycleAnchor.calendar,
        redemptionSteps: [
          'Set the auto-renewing Uber One membership to bill this card.',
          'Up to \$120 a year, credited as it bills.',
        ],
      ),
      BenefitTemplate(
        name: 'Oura Ring Credit',
        category: BenefitCategory.wellness,
        icon: 'heartbeat',
        merchant: 'Oura',
        valueCents: 20000,
        cadence: Cadence.annual,
        anchor: CycleAnchor.calendar,
        enrollmentRequired: true,
        redemptionSteps: [
          'Enrol on the benefits page first.',
          'Buy the ring directly from Oura with the card.',
        ],
      ),
      BenefitTemplate(
        name: 'Equinox Credit',
        category: BenefitCategory.wellness,
        icon: 'barbell',
        merchant: 'Equinox',
        valueCents: 30000,
        cadence: Cadence.annual,
        anchor: CycleAnchor.calendar,
        enrollmentRequired: true,
        redemptionSteps: [
          'Enrol on the benefits page — this is the blocker, not the spend.',
          'Charge an Equinox club membership or Equinox+ to the card.',
        ],
      ),
      BenefitTemplate(
        name: 'Global Entry / TSA PreCheck',
        category: BenefitCategory.travel,
        icon: 'identification-card',
        valueCents: 12000,
        cadence: Cadence.manual,
        anchor: CycleAnchor.calendar,
        redemptionSteps: [
          'Pay the application fee with the card when you next become eligible.',
          'Global Entry \$120 every four years, or PreCheck up to \$85 every four and a half.',
        ],
        notes:
            'No cycle tracks this — review it by hand when the membership nears expiry.',
      ),
    ],
  ),
  CardTemplate(
    id: 'amex-gold',
    issuer: 'American Express',
    product: 'Gold',
    network: CardNetwork.amex,
    annualFeeCents: 32500,
    benefits: [
      BenefitTemplate(
        name: 'Dining Credit',
        category: BenefitCategory.dining,
        icon: 'fork-knife',
        valueCents: 1000,
        cadence: Cadence.monthly,
        anchor: CycleAnchor.calendar,
        enrollmentRequired: true,
      ),
      BenefitTemplate(
        name: 'Uber Cash',
        category: BenefitCategory.rideshare,
        icon: 'car-profile',
        merchant: 'Uber',
        valueCents: 1000,
        cadence: Cadence.monthly,
        anchor: CycleAnchor.calendar,
        enrollmentRequired: true,
      ),
      BenefitTemplate(
        name: 'Resy Credit',
        category: BenefitCategory.dining,
        icon: 'wine',
        merchant: 'Resy',
        valueCents: 10000,
        cadence: Cadence.semiannual,
        anchor: CycleAnchor.calendar,
        enrollmentRequired: true,
      ),
      BenefitTemplate(
        name: 'Dunkin’ Credit',
        category: BenefitCategory.dining,
        icon: 'coffee',
        merchant: 'Dunkin',
        valueCents: 700,
        cadence: Cadence.monthly,
        anchor: CycleAnchor.calendar,
        enrollmentRequired: true,
      ),
    ],
  ),
  CardTemplate(
    id: 'amex-business-platinum',
    issuer: 'American Express',
    product: 'Business Platinum',
    network: CardNetwork.amex,
    annualFeeCents: 89500,
    benefits: [
      BenefitTemplate(
        name: 'Dell Credit',
        category: BenefitCategory.shopping,
        icon: 'desktop',
        merchant: 'Dell',
        valueCents: 20000,
        cadence: Cadence.semiannual,
        anchor: CycleAnchor.calendar,
        enrollmentRequired: true,
      ),
      BenefitTemplate(
        name: 'Adobe Credit',
        category: BenefitCategory.shopping,
        icon: 'pen-nib',
        merchant: 'Adobe',
        valueCents: 15000,
        cadence: Cadence.annual,
        anchor: CycleAnchor.calendar,
        enrollmentRequired: true,
      ),
      BenefitTemplate(
        name: 'Indeed Credit',
        category: BenefitCategory.shopping,
        icon: 'briefcase',
        merchant: 'Indeed',
        valueCents: 9000,
        cadence: Cadence.quarterly,
        anchor: CycleAnchor.calendar,
        enrollmentRequired: true,
      ),
      BenefitTemplate(
        name: 'Wireless Credit',
        category: BenefitCategory.shopping,
        icon: 'wifi-high',
        valueCents: 1000,
        cadence: Cadence.monthly,
        anchor: CycleAnchor.calendar,
        enrollmentRequired: true,
      ),
      BenefitTemplate(
        name: 'Airline Fee Credit',
        category: BenefitCategory.airline,
        icon: 'airplane-tilt',
        valueCents: 20000,
        cadence: Cadence.annual,
        anchor: CycleAnchor.calendar,
      ),
      BenefitTemplate(
        name: 'CLEAR+ Credit',
        category: BenefitCategory.travel,
        icon: 'fingerprint',
        merchant: 'CLEAR',
        valueCents: 20900,
        cadence: Cadence.annual,
        anchor: CycleAnchor.calendar,
      ),
      BenefitTemplate(
        name: 'Hilton Credit',
        category: BenefitCategory.lodging,
        icon: 'bed',
        merchant: 'Hilton',
        valueCents: 20000,
        cadence: Cadence.semiannual,
        anchor: CycleAnchor.calendar,
        enrollmentRequired: true,
      ),
    ],
  ),
  CardTemplate(
    id: 'chase-sapphire-reserve',
    issuer: 'Chase',
    product: 'Sapphire Reserve',
    network: CardNetwork.visa,
    annualFeeCents: 55000,
    benefits: [
      BenefitTemplate(
        name: 'Travel Credit',
        category: BenefitCategory.travel,
        icon: 'airplane-tilt',
        valueCents: 30000,
        cadence: Cadence.annual,
        anchor: CycleAnchor.anniversary,
        redemptionSteps: [
          'Applies automatically to the first travel purchases of the cardmember year.',
          'Runs on the cardmember year, not the calendar year.',
        ],
      ),
      BenefitTemplate(
        name: 'DashPass Membership',
        category: BenefitCategory.dining,
        icon: 'moped',
        merchant: 'DoorDash',
        valueCents: 12000,
        cadence: Cadence.annual,
        anchor: CycleAnchor.anniversary,
        enrollmentRequired: true,
      ),
      BenefitTemplate(
        name: 'DoorDash Promo Credits',
        category: BenefitCategory.dining,
        icon: 'bowl-food',
        merchant: 'DoorDash',
        valueCents: 1000,
        cadence: Cadence.monthly,
        anchor: CycleAnchor.calendar,
        enrollmentRequired: true,
      ),
      BenefitTemplate(
        name: 'Lyft Credit',
        category: BenefitCategory.rideshare,
        icon: 'car-profile',
        merchant: 'Lyft',
        valueCents: 1000,
        cadence: Cadence.monthly,
        anchor: CycleAnchor.calendar,
        enrollmentRequired: true,
      ),
      BenefitTemplate(
        name: 'Peloton Credit',
        category: BenefitCategory.wellness,
        icon: 'barbell',
        merchant: 'Peloton',
        valueCents: 12000,
        cadence: Cadence.annual,
        anchor: CycleAnchor.anniversary,
        enrollmentRequired: true,
      ),
      BenefitTemplate(
        name: 'Global Entry / TSA PreCheck',
        category: BenefitCategory.travel,
        icon: 'identification-card',
        valueCents: 12000,
        cadence: Cadence.manual,
        anchor: CycleAnchor.calendar,
      ),
    ],
  ),
  CardTemplate(
    id: 'capital-one-venture-x',
    issuer: 'Capital One',
    product: 'Venture X',
    network: CardNetwork.visa,
    annualFeeCents: 39500,
    benefits: [
      BenefitTemplate(
        name: 'Travel Credit',
        category: BenefitCategory.travel,
        icon: 'airplane-tilt',
        valueCents: 30000,
        cadence: Cadence.annual,
        anchor: CycleAnchor.anniversary,
        redemptionSteps: ['Must be booked through the issuer travel portal.'],
      ),
      BenefitTemplate(
        name: 'Global Entry / TSA PreCheck',
        category: BenefitCategory.travel,
        icon: 'identification-card',
        valueCents: 12000,
        cadence: Cadence.manual,
        anchor: CycleAnchor.calendar,
      ),
    ],
  ),
  CardTemplate(
    id: 'hilton-aspire',
    issuer: 'Hilton',
    product: 'Honors Aspire',
    network: CardNetwork.amex,
    annualFeeCents: 55000,
    benefits: [
      BenefitTemplate(
        name: 'Hilton Resort Credit',
        category: BenefitCategory.lodging,
        icon: 'umbrella',
        merchant: 'Hilton',
        valueCents: 20000,
        cadence: Cadence.semiannual,
        anchor: CycleAnchor.calendar,
        enrollmentRequired: true,
      ),
      BenefitTemplate(
        name: 'Airline Flight Credit',
        category: BenefitCategory.airline,
        icon: 'airplane-tilt',
        valueCents: 5000,
        cadence: Cadence.quarterly,
        anchor: CycleAnchor.calendar,
      ),
      BenefitTemplate(
        name: 'CLEAR+ Credit',
        category: BenefitCategory.travel,
        icon: 'fingerprint',
        merchant: 'CLEAR',
        valueCents: 20900,
        cadence: Cadence.annual,
        anchor: CycleAnchor.calendar,
        enrollmentRequired: true,
      ),
      BenefitTemplate(
        name: 'Free Night Award',
        category: BenefitCategory.lodging,
        icon: 'bed',
        valueCents: 25000,
        cadence: Cadence.annual,
        anchor: CycleAnchor.anniversary,
      ),
    ],
  ),
  CardTemplate(
    id: 'delta-reserve',
    issuer: 'Delta',
    product: 'Reserve',
    network: CardNetwork.amex,
    annualFeeCents: 65000,
    benefits: [
      BenefitTemplate(
        name: 'Resy Credit',
        category: BenefitCategory.dining,
        icon: 'fork-knife',
        merchant: 'Resy',
        valueCents: 2000,
        cadence: Cadence.monthly,
        anchor: CycleAnchor.calendar,
        enrollmentRequired: true,
      ),
      BenefitTemplate(
        name: 'Rideshare Credit',
        category: BenefitCategory.rideshare,
        icon: 'car-profile',
        valueCents: 1000,
        cadence: Cadence.monthly,
        anchor: CycleAnchor.calendar,
        enrollmentRequired: true,
      ),
      BenefitTemplate(
        name: 'Delta Stays Credit',
        category: BenefitCategory.lodging,
        icon: 'bed',
        valueCents: 20000,
        cadence: Cadence.annual,
        anchor: CycleAnchor.anniversary,
      ),
    ],
  ),
  CardTemplate(
    id: 'blank',
    issuer: '',
    product: '',
    network: CardNetwork.other,
    annualFeeCents: 0,
    benefits: [],
  ),
];

CardTemplate? findTemplate(String id) {
  for (final template in cardTemplates) {
    if (template.id == id) return template;
  }
  return null;
}

/// Total value a template releases in a year, for the catalogue rows.
int templateAnnualValueCents(CardTemplate template) {
  return template.benefits.fold(
    0,
    (sum, b) => sum + b.valueCents * _perYear(b.cadence),
  );
}

int _perYear(Cadence cadence) => switch (cadence) {
  Cadence.monthly => 12,
  Cadence.quarterly => 4,
  Cadence.semiannual => 2,
  Cadence.annual => 1,
  Cadence.manual => 1,
};

/// Credits in a template that are stuck behind an enrolment box.
List<String> templateEnrollmentNames(CardTemplate template) {
  return template.benefits
      .where((b) => b.enrollmentRequired)
      .map((b) => b.name)
      .toList();
}

/// Turns a template into real benefits attached to a newly created card.
List<Benefit> benefitsFromTemplate(
  CardTemplate template,
  String cardId,
  IsoInstant now,
  String Function() newId,
) {
  return template.benefits
      .map(
        (entry) => Benefit(
          id: newId(),
          cardId: cardId,
          name: entry.name,
          description: entry.description,
          category: entry.category,
          icon: entry.icon,
          merchant: entry.merchant,
          valueCents: entry.valueCents,
          cadence: entry.cadence,
          anchor: entry.anchor,
          enrollmentRequired: entry.enrollmentRequired,
          redemptionSteps: entry.redemptionSteps,
          notes: entry.notes,
          muted: false,
          lastCallOnly: false,
          active: true,
          createdAt: now,
          updatedAt: now,
        ),
      )
      .toList();
}
