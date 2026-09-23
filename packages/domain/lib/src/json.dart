/// The snapshot's JSON shape, shared with the PWA's export and IndexedDB
/// record so a household moves between the two apps unchanged.
///
/// Enums serialise to the PWA's `snake_case` strings, and absent optional
/// fields are omitted rather than written as null, as the PWA writes them.
library;

import 'types.dart';

const Map<BenefitCategory, String> _categoryNames = {
  BenefitCategory.feeCredit: 'fee_credit',
};

String _categoryToJson(BenefitCategory category) =>
    _categoryNames[category] ?? category.name;

BenefitCategory _categoryFromJson(String name) => name == 'fee_credit'
    ? BenefitCategory.feeCredit
    : BenefitCategory.values.byName(name);

String _statusToJson(BenefitStatus status) =>
    status == BenefitStatus.useSoon ? 'use_soon' : status.name;

BenefitStatus statusFromJson(String name) => name == 'use_soon'
    ? BenefitStatus.useSoon
    : BenefitStatus.values.byName(name);

String statusToJson(BenefitStatus status) => _statusToJson(status);

Map<String, Object?> _withoutNulls(Map<String, Object?> json) =>
    Map.fromEntries(json.entries.where((entry) => entry.value != null));

Card cardFromJson(Map<String, dynamic> json) => Card(
  id: json['id'] as String,
  issuer: json['issuer'] as String,
  product: json['product'] as String,
  holder: json['holder'] as String,
  nickname: json['nickname'] as String?,
  network: CardNetwork.values.byName(json['network'] as String),
  last4: json['last4'] as String?,
  annualFeeCents: json['annualFeeCents'] as int,
  anniversaryOn: json['anniversaryOn'] as String,
  muted: json['muted'] as bool,
  archived: json['archived'] as bool,
  createdAt: json['createdAt'] as String,
  updatedAt: json['updatedAt'] as String,
);

Map<String, Object?> cardToJson(Card card) => _withoutNulls({
  'id': card.id,
  'issuer': card.issuer,
  'product': card.product,
  'holder': card.holder,
  'nickname': card.nickname,
  'network': card.network.name,
  'last4': card.last4,
  'annualFeeCents': card.annualFeeCents,
  'anniversaryOn': card.anniversaryOn,
  'muted': card.muted,
  'archived': card.archived,
  'createdAt': card.createdAt,
  'updatedAt': card.updatedAt,
});

Benefit benefitFromJson(Map<String, dynamic> json) => Benefit(
  id: json['id'] as String,
  cardId: json['cardId'] as String,
  name: json['name'] as String,
  description: json['description'] as String?,
  category: _categoryFromJson(json['category'] as String),
  icon: json['icon'] as String?,
  merchant: json['merchant'] as String?,
  valueCents: json['valueCents'] as int,
  cadence: Cadence.values.byName(json['cadence'] as String),
  anchor: CycleAnchor.values.byName(json['anchor'] as String),
  intervalMonths: json['intervalMonths'] as int?,
  enrollmentRequired: json['enrollmentRequired'] as bool,
  enrolledAt: json['enrolledAt'] as String?,
  enrollmentNote: json['enrollmentNote'] as String?,
  enrollmentUrl: json['enrollmentUrl'] as String?,
  spendThresholdCents: json['spendThresholdCents'] as int?,
  spendMetAt: json['spendMetAt'] as String?,
  endsOn: json['endsOn'] as String?,
  redemptionSteps: ((json['redemptionSteps'] as List?) ?? const [])
      .cast<String>(),
  notes: json['notes'] as String?,
  muted: json['muted'] as bool,
  lastCallOnly: json['lastCallOnly'] as bool,
  active: json['active'] as bool,
  createdAt: json['createdAt'] as String,
  updatedAt: json['updatedAt'] as String,
);

Map<String, Object?> benefitToJson(Benefit benefit) => _withoutNulls({
  'id': benefit.id,
  'cardId': benefit.cardId,
  'name': benefit.name,
  'description': benefit.description,
  'category': _categoryToJson(benefit.category),
  'icon': benefit.icon,
  'merchant': benefit.merchant,
  'valueCents': benefit.valueCents,
  'cadence': benefit.cadence.name,
  'anchor': benefit.anchor.name,
  'intervalMonths': benefit.intervalMonths,
  'enrollmentRequired': benefit.enrollmentRequired,
  'enrolledAt': benefit.enrolledAt,
  'enrollmentNote': benefit.enrollmentNote,
  'enrollmentUrl': benefit.enrollmentUrl,
  'spendThresholdCents': benefit.spendThresholdCents,
  'spendMetAt': benefit.spendMetAt,
  'endsOn': benefit.endsOn,
  'redemptionSteps': benefit.redemptionSteps,
  'notes': benefit.notes,
  'muted': benefit.muted,
  'lastCallOnly': benefit.lastCallOnly,
  'active': benefit.active,
  'createdAt': benefit.createdAt,
  'updatedAt': benefit.updatedAt,
});

Claim claimFromJson(Map<String, dynamic> json) => Claim(
  id: json['id'] as String,
  benefitId: json['benefitId'] as String,
  cycleKey: json['cycleKey'] as String,
  amountCents: json['amountCents'] as int,
  claimedAt: json['claimedAt'] as String,
  note: json['note'] as String?,
);

Map<String, Object?> claimToJson(Claim claim) => _withoutNulls({
  'id': claim.id,
  'benefitId': claim.benefitId,
  'cycleKey': claim.cycleKey,
  'amountCents': claim.amountCents,
  'claimedAt': claim.claimedAt,
  'note': claim.note,
});

Settings settingsFromJson(Map<String, dynamic> json) {
  final n = json['notifications'] as Map<String, dynamic>;
  return Settings(
    notifications: NotificationSettings(
      enabled: n['enabled'] as bool,
      timeOfDay: n['timeOfDay'] as String,
      minValueCents: n['minValueCents'] as int,
      annualFeeReminder: n['annualFeeReminder'] as bool,
      enrollmentReminder: n['enrollmentReminder'] as bool,
    ),
    useSoonDays: json['useSoonDays'] as int,
    theme: ThemeSetting.values.byName(json['theme'] as String),
    holderFilter: json['holderFilter'] as String,
  );
}

Map<String, Object?> settingsToJson(Settings settings) => {
  'notifications': {
    'enabled': settings.notifications.enabled,
    'timeOfDay': settings.notifications.timeOfDay,
    'minValueCents': settings.notifications.minValueCents,
    'annualFeeReminder': settings.notifications.annualFeeReminder,
    'enrollmentReminder': settings.notifications.enrollmentReminder,
  },
  'useSoonDays': settings.useSoonDays,
  'theme': settings.theme.name,
  'holderFilter': settings.holderFilter,
};

AppData appDataFromJson(Map<String, dynamic> json) => AppData(
  version: json['version'] as int,
  cards: (json['cards'] as List)
      .cast<Map<String, dynamic>>()
      .map(cardFromJson)
      .toList(),
  benefits: (json['benefits'] as List)
      .cast<Map<String, dynamic>>()
      .map(benefitFromJson)
      .toList(),
  claims: (json['claims'] as List)
      .cast<Map<String, dynamic>>()
      .map(claimFromJson)
      .toList(),
  settings: settingsFromJson(json['settings'] as Map<String, dynamic>),
);

Map<String, Object?> appDataToJson(AppData data) => {
  'version': data.version,
  'cards': data.cards.map(cardToJson).toList(),
  'benefits': data.benefits.map(benefitToJson).toList(),
  'claims': data.claims.map(claimToJson).toList(),
  'settings': settingsToJson(data.settings),
};
