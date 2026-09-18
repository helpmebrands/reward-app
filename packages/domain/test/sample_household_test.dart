import 'dart:convert';
import 'dart:io';

import 'package:domain/domain.dart';
import 'package:test/test.dart';

/// The sample household is the PWA's `samples/sample-household.json`, read
/// straight from the frozen app so the two implementations are held to the
/// same data. The expected ids come from the TypeScript `buildSchedule` run
/// on 16 September 2026 at 08:00 local by `apps/pwa/scripts/schedule-ids.ts`.
AppData loadSampleHousehold() {
  final json =
      jsonDecode(
            File(
              '../../apps/pwa/samples/sample-household.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  return AppData(
    version: json['version'] as int,
    cards: (json['cards'] as List)
        .cast<Map<String, dynamic>>()
        .map(_card)
        .toList(),
    benefits: (json['benefits'] as List)
        .cast<Map<String, dynamic>>()
        .map(_benefit)
        .toList(),
    claims: (json['claims'] as List)
        .cast<Map<String, dynamic>>()
        .map(_claim)
        .toList(),
    settings: _settings(json['settings'] as Map<String, dynamic>),
  );
}

Card _card(Map<String, dynamic> j) => Card(
  id: j['id'] as String,
  issuer: j['issuer'] as String,
  product: j['product'] as String,
  holder: j['holder'] as String,
  nickname: j['nickname'] as String?,
  network: CardNetwork.values.byName(j['network'] as String),
  last4: j['last4'] as String?,
  annualFeeCents: j['annualFeeCents'] as int,
  anniversaryOn: j['anniversaryOn'] as String,
  muted: j['muted'] as bool,
  archived: j['archived'] as bool,
  createdAt: j['createdAt'] as String,
  updatedAt: j['updatedAt'] as String,
);

Benefit _benefit(Map<String, dynamic> j) => Benefit(
  id: j['id'] as String,
  cardId: j['cardId'] as String,
  name: j['name'] as String,
  description: j['description'] as String?,
  category: j['category'] == 'fee_credit'
      ? BenefitCategory.feeCredit
      : BenefitCategory.values.byName(j['category'] as String),
  icon: j['icon'] as String?,
  merchant: j['merchant'] as String?,
  valueCents: j['valueCents'] as int,
  cadence: Cadence.values.byName(j['cadence'] as String),
  anchor: CycleAnchor.values.byName(j['anchor'] as String),
  enrollmentRequired: j['enrollmentRequired'] as bool,
  enrolledAt: j['enrolledAt'] as String?,
  enrollmentNote: j['enrollmentNote'] as String?,
  enrollmentUrl: j['enrollmentUrl'] as String?,
  redemptionSteps: (j['redemptionSteps'] as List).cast<String>(),
  notes: j['notes'] as String?,
  muted: j['muted'] as bool,
  lastCallOnly: j['lastCallOnly'] as bool,
  active: j['active'] as bool,
  createdAt: j['createdAt'] as String,
  updatedAt: j['updatedAt'] as String,
);

Claim _claim(Map<String, dynamic> j) => Claim(
  id: j['id'] as String,
  benefitId: j['benefitId'] as String,
  cycleKey: j['cycleKey'] as String,
  amountCents: j['amountCents'] as int,
  claimedAt: j['claimedAt'] as String,
  note: j['note'] as String?,
);

Settings _settings(Map<String, dynamic> j) {
  final n = j['notifications'] as Map<String, dynamic>;
  return Settings(
    notifications: NotificationSettings(
      // The sample ships with reminders off; the schedule is built as if the
      // user had switched them on, exactly as the TypeScript dump does.
      enabled: true,
      timeOfDay: n['timeOfDay'] as String,
      minValueCents: n['minValueCents'] as int,
      annualFeeReminder: n['annualFeeReminder'] as bool,
      enrollmentReminder: n['enrollmentReminder'] as bool,
    ),
    useSoonDays: j['useSoonDays'] as int,
    theme: ThemeSetting.values.byName(j['theme'] as String),
    holderFilter: j['holderFilter'] as String,
  );
}

// @lat: [[tests#Ladder and schedule#The sample household schedules the same ids in Dart]]
void main() {
  test(
    'the sample household schedules the same group ids as the TypeScript build',
    () {
      final expected =
          (jsonDecode(
                    File(
                      'test/fixtures/sample-schedule-ids.json',
                    ).readAsStringSync(),
                  )
                  as List)
              .cast<String>();
      final schedule = buildSchedule(
        loadSampleHousehold(),
        DateTime(2026, 9, 16, 8, 0, 0),
      );
      expect(schedule.reminders.map((r) => r.id).toList(), expected);
    },
  );
}
