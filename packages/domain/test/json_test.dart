import 'dart:convert';
import 'dart:io';

import 'package:domain/domain.dart';
import 'package:test/test.dart';

void main() {
  // @lat: [[tests#Snapshot JSON#The sample household round-trips unchanged]]
  test('the sample household round-trips through the codec unchanged', () {
    final raw = File(
      '../../apps/pwa/samples/sample-household.json',
    ).readAsStringSync();
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final data = appDataFromJson(json);
    expect(data.cards, hasLength(2));
    expect(data.benefits, hasLength(24));
    expect(data.claims, hasLength(20));
    expect(data.benefits.first.merchant, 'Uber');
    expect(jsonDecode(jsonEncode(appDataToJson(data))), json);
  });

  // @lat: [[tests#Snapshot JSON#Enums use the PWA's spellings]]
  test('writes fee_credit and use_soon the way the PWA spells them', () {
    final benefit = benefitFromJson({
      'id': 'b',
      'cardId': 'c',
      'name': 'Fee',
      'category': 'fee_credit',
      'valueCents': 100,
      'cadence': 'annual',
      'anchor': 'anniversary',
      'enrollmentRequired': false,
      'muted': false,
      'lastCallOnly': false,
      'active': true,
      'createdAt': 't',
      'updatedAt': 't',
    });
    expect(benefit.category, BenefitCategory.feeCredit);
    expect(benefit.redemptionSteps, isEmpty);
    expect(benefitToJson(benefit)['category'], 'fee_credit');
    expect(benefitToJson(benefit).containsKey('merchant'), isFalse);
    expect(statusToJson(BenefitStatus.useSoon), 'use_soon');
    expect(statusFromJson('use_soon'), BenefitStatus.useSoon);
  });

  // @lat: [[tests#Snapshot JSON#An end date round-trips and is omitted when absent]]
  test('round-trips endsOn and omits it when the credit has no end', () {
    final benefit = benefitFromJson({
      'id': 'b',
      'cardId': 'c',
      'name': 'Grubhub',
      'category': 'dining',
      'valueCents': 1000,
      'cadence': 'monthly',
      'anchor': 'calendar',
      'enrollmentRequired': false,
      'endsOn': '2026-12-31',
      'muted': false,
      'lastCallOnly': false,
      'active': true,
      'createdAt': 't',
      'updatedAt': 't',
    });
    expect(benefit.endsOn, '2026-12-31');
    expect(benefitToJson(benefit)['endsOn'], '2026-12-31');
    final open = benefit.copyWith(endsOn: null);
    expect(open.endsOn, isNull);
    expect(benefitToJson(open).containsKey('endsOn'), isFalse);
  });

  // @lat: [[tests#Snapshot JSON#A spend threshold round-trips with its met stamp]]
  test(
    'round-trips spendThresholdCents and spendMetAt, omitted when unset',
    () {
      final benefit = benefitFromJson({
        'id': 'b',
        'cardId': 'c',
        'name': 'Dell Bonus',
        'category': 'shopping',
        'valueCents': 100000,
        'cadence': 'annual',
        'anchor': 'calendar',
        'enrollmentRequired': false,
        'spendThresholdCents': 500000,
        'spendMetAt': '2026-03-01T00:00:00.000Z',
        'muted': false,
        'lastCallOnly': false,
        'active': true,
        'createdAt': 't',
        'updatedAt': 't',
      });
      expect(benefit.spendThresholdCents, 500000);
      expect(benefit.spendMetAt, '2026-03-01T00:00:00.000Z');
      final json = benefitToJson(benefit);
      expect(json['spendThresholdCents'], 500000);
      expect(json['spendMetAt'], '2026-03-01T00:00:00.000Z');
      final cleared = benefitToJson(
        benefit.copyWith(spendThresholdCents: null, spendMetAt: null),
      );
      expect(cleared.containsKey('spendThresholdCents'), isFalse);
      expect(cleared.containsKey('spendMetAt'), isFalse);
    },
  );
}
