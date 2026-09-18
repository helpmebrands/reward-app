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
}
