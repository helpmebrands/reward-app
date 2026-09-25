import 'dart:convert';
import 'dart:io';

import 'package:domain/domain.dart';
import 'package:test/test.dart';

void main() {
  // @lat: [[tests#Snapshot JSON#The sample household round-trips unchanged]]
  test('the sample household round-trips through the codec unchanged', () {
    final raw = File('test/fixtures/sample-household.json').readAsStringSync();
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final data = appDataFromJson(json);
    expect(data.cards, hasLength(2));
    expect(data.benefits, hasLength(24));
    expect(data.claims, hasLength(20));
    expect(data.benefits.first.merchant, 'Uber');
    // The frozen PWA still writes `holder`, `holderFilter`, the mutes and the
    // notification block; Dart drops them, since reminders are a member's.
    final expected = jsonDecode(raw) as Map<String, dynamic>;
    for (final card in expected['cards'] as List) {
      (card as Map).remove('holder');
      card.remove('muted');
    }
    for (final benefit in expected['benefits'] as List) {
      (benefit as Map).remove('muted');
    }
    final settings = expected['settings'] as Map;
    settings.remove('holderFilter');
    settings.remove('notifications');
    expect(jsonDecode(jsonEncode(appDataToJson(data))), expected);
  });

  // @lat: [[tests#Member preferences#Member preferences round-trip]]
  test('member preferences round-trip, mutes as sorted lists', () {
    final prefs = defaultMemberPreferences.copyWith(
      enabled: true,
      timeOfDay: '07:30',
      minValueCents: 500,
      annualFeeReminder: false,
      mutedCardIds: {'c2', 'c1'},
      mutedBenefitIds: {'b1'},
    );
    final json = memberPreferencesToJson(prefs);
    expect(json['mutedCardIds'], ['c1', 'c2']);
    final back = memberPreferencesFromJson(
      jsonDecode(jsonEncode(json)) as Map<String, dynamic>,
    );
    expect(memberPreferencesToJson(back), json);
    expect(back.mutedCardIds, {'c1', 'c2'});
    expect(back.enrollmentReminder, isTrue);
  });

  // @lat: [[tests#Card labels#A label round-trips and is omitted when absent]]
  test('a card label round-trips and is left out when there is none', () {
    final card = cardFromJson({
      'id': 'c',
      'issuer': 'Chase',
      'product': 'Ink',
      'label': 'Office',
      'network': 'visa',
      'annualFeeCents': 0,
      'anniversaryOn': '2021-03-14',
      'muted': false,
      'archived': false,
      'createdAt': 't',
      'updatedAt': 't',
    });
    expect(card.label, 'Office');
    expect(cardToJson(card)['label'], 'Office');
    expect(
      cardToJson(card.copyWith(label: null)).containsKey('label'),
      isFalse,
    );
  });

  // @lat: [[tests#Snapshot JSON#The sample household rolls its Global Entry credits]]
  test('the sample household carries Global Entry as a rolling credit', () {
    final raw = File('test/fixtures/sample-household.json').readAsStringSync();
    final data = appDataFromJson(jsonDecode(raw) as Map<String, dynamic>);
    final globalEntry = data.benefits
        .where((b) => b.name.startsWith('Global Entry'))
        .toList();
    expect(globalEntry, hasLength(2));
    for (final benefit in globalEntry) {
      expect(benefit.cadence, Cadence.rolling);
      expect(benefit.intervalMonths, 48);
    }
    expect(data.benefits.any((b) => b.cadence == Cadence.manual), isFalse);
  });

  // @lat: [[tests#Snapshot JSON#A card without a kind loads as personal]]
  test('reads a card saved before kinds existed as personal', () {
    final legacy = {
      'id': 'c',
      'issuer': 'Chase',
      'product': 'Ink',
      'network': 'visa',
      'annualFeeCents': 0,
      'anniversaryOn': '2021-03-14',
      'muted': false,
      'archived': false,
      'createdAt': 't',
      'updatedAt': 't',
    };
    expect(cardFromJson(legacy).kind, CardKind.personal);
    expect(cardToJson(cardFromJson(legacy))['kind'], 'personal');
    final business = cardFromJson({...legacy, 'kind': 'business'});
    expect(business.kind, CardKind.business);
    expect(cardToJson(business)['kind'], 'business');
    expect(business.copyWith(kind: CardKind.personal).kind, CardKind.personal);
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

  // @lat: [[tests#Snapshot JSON#A rolling cadence round-trips with its interval]]
  test('round-trips cadence rolling and intervalMonths', () {
    final benefit = benefitFromJson({
      'id': 'b',
      'cardId': 'c',
      'name': 'Global Entry',
      'category': 'travel',
      'valueCents': 12000,
      'cadence': 'rolling',
      'anchor': 'anniversary',
      'intervalMonths': 48,
      'enrollmentRequired': false,
      'muted': false,
      'lastCallOnly': false,
      'active': true,
      'createdAt': 't',
      'updatedAt': 't',
    });
    expect(benefit.cadence, Cadence.rolling);
    expect(benefit.intervalMonths, 48);
    final json = benefitToJson(benefit);
    expect(json['cadence'], 'rolling');
    expect(json['intervalMonths'], 48);
    expect(
      benefitToJson(
        benefit.copyWith(intervalMonths: null),
      ).containsKey('intervalMonths'),
      isFalse,
    );
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
