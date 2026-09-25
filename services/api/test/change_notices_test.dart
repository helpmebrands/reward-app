import 'dart:convert';

import 'package:api/change_notices.dart';
import 'package:domain/domain.dart';
import 'package:test/test.dart';

void main() {
  final gold = cardTemplates.firstWhere((t) => t.id == 'amex-gold');
  final v1 = TemplateVersion(
    version: 1,
    effectiveFrom: '2000-01-01',
    template: gold,
  );

  /// Version 2 of the Gold: v1's JSON with [edit] applied.
  TemplateVersion v2(void Function(Map<String, dynamic> json) edit) {
    final json =
        jsonDecode(jsonEncode(templateVersionToJson(v1)))
            as Map<String, dynamic>;
    json['version'] = 2;
    json['effectiveFrom'] = '2027-01-01';
    edit(json);
    return templateVersionFromJson(json);
  }

  List<Map<String, dynamic>> credits(Map<String, dynamic> json) =>
      (json['credits'] as List).cast<Map<String, dynamic>>();

  // @lat: [[api-tests#Change notices#Each change is worded from the two versions]]
  test('each change between two versions is worded for a notice', () {
    expect(
      termChanges(
        v1,
        v2(
          (j) => credits(j).firstWhere(
            (c) => c['id'] == 'amex-gold/uber-cash',
          )['valueCents'] = 2000,
        ),
      ),
      [r'Uber Cash credit changes to $20'],
    );
    expect(termChanges(v1, v2((j) => j['annualFeeCents'] = 35000)), [
      r'annual fee changes to $350',
    ]);
    expect(
      termChanges(
        v1,
        v2(
          (j) =>
              credits(j).removeWhere((c) => c['id'] == 'amex-gold/uber-cash'),
        ),
      ),
      ['Uber Cash credit ends'],
    );
    expect(
      termChanges(
        v1,
        v2(
          (j) => (j['credits'] as List).add({
            ...credits(j).first,
            'id': 'amex-gold/lounge',
            'name': 'Lounge',
            'valueCents': 5000,
          }),
        ),
      ),
      [r'new $50 Lounge credit starts'],
    );
    expect(termChanges(v1, v2((j) => j['issuer'] = 'Amex')), ['terms change']);
  });

  // @lat: [[api-tests#Change notices#A notice leads with the first change]]
  test('a notice names the card, the first change and the date', () {
    final notice = changeNotice(
      cardName: 'Gold',
      cardId: 'c-1',
      version: 2,
      changes: [
        r'Uber Cash credit changes to $20',
        r'annual fee changes to $350',
      ],
      effectiveFrom: '2027-01-01',
      today: '2026-12-01',
    );
    expect(notice.title, 'Gold terms are changing');
    expect(
      notice.body,
      r"Your Gold's Uber Cash credit changes to $20 on Jan 1, 2027, "
      'and 1 other change.',
    );
    expect(notice.tag, 'terms-c-1');
    expect(notice.data, {'noticeId': 'terms|c-1|2', 'url': '/cards/c-1'});
  });
}
