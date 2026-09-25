/// The snapshot's JSON shape, shared with the PWA's export and IndexedDB
/// record so a household moves between the two apps unchanged.
///
/// Enums serialise to the PWA's `snake_case` strings, and absent optional
/// fields are omitted rather than written as null, as the PWA writes them.
library;

import 'catalog.dart';
import 'catalog_versions.dart';
import 'dates.dart';
import 'types.dart';

const Map<BenefitCategory, String> _categoryNames = {
  BenefitCategory.feeCredit: 'fee_credit',
};

String _categoryToJson(BenefitCategory category) =>
    _categoryNames[category] ?? category.name;

BenefitCategory _categoryFromJson(String name) => name == 'fee_credit'
    ? BenefitCategory.feeCredit
    : BenefitCategory.values.byName(name);

String _statusToJson(BenefitStatus status) => switch (status) {
  BenefitStatus.useSoon => 'use_soon',
  BenefitStatus.optedOut => 'opted_out',
  _ => status.name,
};

BenefitStatus statusFromJson(String name) => switch (name) {
  'use_soon' => BenefitStatus.useSoon,
  'opted_out' => BenefitStatus.optedOut,
  _ => BenefitStatus.values.byName(name),
};

String statusToJson(BenefitStatus status) => _statusToJson(status);

Map<String, Object?> _withoutNulls(Map<String, Object?> json) =>
    Map.fromEntries(json.entries.where((entry) => entry.value != null));

Card cardFromJson(Map<String, dynamic> json) => Card(
  id: json['id'] as String,
  issuer: json['issuer'] as String,
  product: json['product'] as String,
  label: json['label'] as String?,
  templateId: json['templateId'] as String?,
  network: CardNetwork.values.byName(json['network'] as String),
  // Cards saved before version 2 have no kind; a card is personal unless the
  // user says otherwise.
  kind: CardKind.values.byName((json['kind'] as String?) ?? 'personal'),
  last4: json['last4'] as String?,
  annualFeeCents: json['annualFeeCents'] as int,
  anniversaryOn: json['anniversaryOn'] as String,
  archived: json['archived'] as bool,
  createdAt: json['createdAt'] as String,
  updatedAt: json['updatedAt'] as String,
);

Map<String, Object?> cardToJson(Card card) => _withoutNulls({
  'id': card.id,
  'issuer': card.issuer,
  'product': card.product,
  'label': card.label,
  'templateId': card.templateId,
  'network': card.network.name,
  'kind': card.kind.name,
  'last4': card.last4,
  'annualFeeCents': card.annualFeeCents,
  'anniversaryOn': card.anniversaryOn,
  'archived': card.archived,
  'createdAt': card.createdAt,
  'updatedAt': card.updatedAt,
});

/// A credit saved before opting out existed was paused with `active: false`.
/// Unless it had already ended by the time it was last saved, which is how
/// the catalogue marks a credit that ended before the card was added, the
/// pause meant "I won't use this": it loads opted out as of that save.
Benefit benefitFromJson(Map<String, dynamic> json) {
  final benefit = _benefitFromJson(json);
  if (benefit.active || benefit.optedOutAt != null) return benefit;
  final endsOn = benefit.endsOn;
  final ended =
      endsOn != null &&
      compareIsoDate(endsOn, benefit.updatedAt.substring(0, 10)) < 0;
  return ended
      ? benefit
      : benefit.copyWith(active: true, optedOutAt: benefit.updatedAt);
}

Benefit _benefitFromJson(Map<String, dynamic> json) => Benefit(
  id: json['id'] as String,
  cardId: json['cardId'] as String,
  templateBenefitId: json['templateBenefitId'] as String?,
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
  lastCallOnly: json['lastCallOnly'] as bool,
  active: json['active'] as bool,
  optedOutAt: json['optedOutAt'] as String?,
  trackedFrom: json['trackedFrom'] as String?,
  createdAt: json['createdAt'] as String,
  updatedAt: json['updatedAt'] as String,
);

Map<String, Object?> benefitToJson(Benefit benefit) => _withoutNulls({
  'id': benefit.id,
  'cardId': benefit.cardId,
  'templateBenefitId': benefit.templateBenefitId,
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
  'lastCallOnly': benefit.lastCallOnly,
  'active': benefit.active,
  'optedOutAt': benefit.optedOutAt,
  'trackedFrom': benefit.trackedFrom,
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

Settings settingsFromJson(Map<String, dynamic> json) => Settings(
  useSoonDays: json['useSoonDays'] as int,
  theme: ThemeSetting.values.byName(json['theme'] as String),
);

Map<String, Object?> settingsToJson(Settings settings) => {
  'useSoonDays': settings.useSoonDays,
  'theme': settings.theme.name,
};

/// One member's preferences. The mutes are sorted lists, so the same
/// preferences always encode to the same JSON.
MemberPreferences memberPreferencesFromJson(Map<String, dynamic> json) =>
    MemberPreferences(
      enabled: json['enabled'] as bool,
      timeOfDay: json['timeOfDay'] as String,
      minValueCents: json['minValueCents'] as int,
      annualFeeReminder: json['annualFeeReminder'] as bool,
      enrollmentReminder: json['enrollmentReminder'] as bool,
      mutedCardIds: {...(json['mutedCardIds'] as List? ?? const []).cast()},
      mutedBenefitIds: {
        ...(json['mutedBenefitIds'] as List? ?? const []).cast(),
      },
    );

Map<String, Object?> memberPreferencesToJson(MemberPreferences prefs) => {
  'enabled': prefs.enabled,
  'timeOfDay': prefs.timeOfDay,
  'minValueCents': prefs.minValueCents,
  'annualFeeReminder': prefs.annualFeeReminder,
  'enrollmentReminder': prefs.enrollmentReminder,
  'mutedCardIds': prefs.mutedCardIds.toList()..sort(),
  'mutedBenefitIds': prefs.mutedBenefitIds.toList()..sort(),
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

/// One catalogue credit, as the service tier's catalogue serves it.
BenefitTemplate benefitTemplateFromJson(Map<String, dynamic> json) =>
    BenefitTemplate(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      category: _categoryFromJson(json['category'] as String),
      icon: json['icon'] as String,
      merchant: json['merchant'] as String?,
      valueCents: json['valueCents'] as int,
      cadence: Cadence.values.byName(json['cadence'] as String),
      anchor: CycleAnchor.values.byName(json['anchor'] as String),
      intervalMonths: json['intervalMonths'] as int?,
      enrollmentRequired: json['enrollmentRequired'] as bool? ?? false,
      spendThresholdCents: json['spendThresholdCents'] as int?,
      endsOn: json['endsOn'] as String?,
      redemptionSteps: ((json['redemptionSteps'] as List?) ?? const [])
          .cast<String>(),
      notes: json['notes'] as String?,
    );

Map<String, Object?> benefitTemplateToJson(BenefitTemplate credit) =>
    _withoutNulls({
      'id': credit.id,
      'name': credit.name,
      'description': credit.description,
      'category': _categoryToJson(credit.category),
      'icon': credit.icon,
      'merchant': credit.merchant,
      'valueCents': credit.valueCents,
      'cadence': credit.cadence.name,
      'anchor': credit.anchor.name,
      'intervalMonths': credit.intervalMonths,
      'enrollmentRequired': credit.enrollmentRequired,
      'spendThresholdCents': credit.spendThresholdCents,
      'endsOn': credit.endsOn,
      'redemptionSteps': credit.redemptionSteps,
      'notes': credit.notes,
    });

/// A whole template as of one version: the template's own fields, the
/// version and its date, and every credit.
TemplateVersion templateVersionFromJson(Map<String, dynamic> json) =>
    TemplateVersion(
      version: json['version'] as int,
      effectiveFrom: json['effectiveFrom'] as String,
      template: CardTemplate(
        id: json['id'] as String,
        issuer: json['issuer'] as String,
        product: json['product'] as String,
        network: CardNetwork.values.byName(json['network'] as String),
        kind: CardKind.values.byName(json['kind'] as String),
        annualFeeCents: json['annualFeeCents'] as int,
        benefits: (json['credits'] as List)
            .cast<Map<String, dynamic>>()
            .map(benefitTemplateFromJson)
            .toList(),
      ),
    );

Map<String, Object?> templateVersionToJson(TemplateVersion version) => {
  'id': version.template.id,
  'version': version.version,
  'effectiveFrom': version.effectiveFrom,
  'issuer': version.template.issuer,
  'product': version.template.product,
  'network': version.template.network.name,
  'kind': version.template.kind.name,
  'annualFeeCents': version.template.annualFeeCents,
  'credits': version.template.benefits.map(benefitTemplateToJson).toList(),
};
