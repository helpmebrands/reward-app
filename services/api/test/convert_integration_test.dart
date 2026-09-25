import 'dart:convert';
import 'dart:io';

import 'package:domain/domain.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'support/api.dart';
import 'support/database.dart';
import 'support/tokens.dart';

/// Converting a system-maintained card into one the household maintains,
/// against `DATABASE_URL` in the suite's own schema; skipped without one.
void main() {
  final url = Platform.environment['DATABASE_URL'];

  group('conversion against DATABASE_URL', () {
    late Connection db;
    late TestApi api;

    setUpAll(() async {
      db = await openMigratedSchema(url!, 'convert');
      api = TestApi(await TestKey.generate(), db);
    });

    tearDownAll(() => dropSchema(db, 'convert'));

    setUp(() => db.execute('TRUNCATE users, households CASCADE'));

    Map<String, dynamic> json(Reply r) => r.body! as Map<String, dynamic>;

    Future<AppData> data(String uid) async =>
        appDataFromJson(json(await api.as(uid).get('/v1/household/data')));

    /// Ann's Gold with a claim on its first credit, Bob in the household
    /// as an editor, and both muting the card and the credit.
    Future<
      ({
        String card,
        String benefit,
        AppData before,
        Map<String, dynamic> converted,
      })
    >
    convertedGold() async {
      final added = json(
        await api.as('ann').post('/v1/cards', {
          'templateId': 'amex-gold',
          'anniversaryOn': '2024-05-01',
          'label': 'Ann’s Gold',
          'last4': '1005',
        }),
      );
      final card = (added['card'] as Map)['id'] as String;
      final benefit =
          ((added['benefits'] as List).first as Map)['id'] as String;
      await api.as('ann').put('/v1/benefits/$benefit/state', {
        'enrolledAt': '2026-01-02T00:00:00.000Z',
      });
      for (final (key, cycle) in [('a', '2026-08-01'), ('b', '2026-09-01')]) {
        await api
            .as('ann')
            .send(
              'POST',
              '/v1/claims',
              body: {
                'benefitId': benefit,
                'cycleKey': cycle,
                'amountCents': 700,
                'claimedAt': '${cycle}T12:00:00.000Z',
              },
              headers: {'idempotency-key': key},
            );
      }
      final code =
          json(
                await api.as('ann').post('/v1/household/invites', {
                  'role': 'edit',
                }),
              )['code']
              as String;
      await api.as('bob').post('/v1/invites/$code/accept');
      for (final uid in ['ann', 'bob']) {
        await api.as(uid).put('/v1/me/mutes/cards/$card', {});
        await api.as(uid).put('/v1/me/mutes/benefits/$benefit', {});
      }
      final before = await data('ann');
      final converted = await api.as('bob').post('/v1/cards/$card/convert');
      expect(converted.status, 200, reason: '${converted.body}');
      return (
        card: card,
        benefit: benefit,
        before: before,
        converted: json(converted),
      );
    }

    // @lat: [[api-tests#Conversion#Conversion keeps totals and history]]
    test('the household’s captured totals and claims are unchanged', () async {
      final ids = await convertedGold();
      final before = ids.before;
      final after = await data('ann');
      final card = after.cards.single;
      expect(card.id, isNot(ids.card));
      expect(maintainedBy(card), MaintainedBy.user);
      expect(card.label, 'Ann’s Gold');
      expect(card.last4, '1005');
      expect(card.anniversaryOn, '2024-05-01');

      List<(String, String, int)> history(AppData d) => [
        for (final c in d.claims)
          (
            d.benefits.firstWhere((b) => b.id == c.benefitId).name,
            c.cycleKey,
            c.amountCents,
          ),
      ];
      expect(history(after), hasLength(2));
      expect(history(after), history(before));
      final today = todayIso();
      Totals totals(AppData d) => totalsFor(
        currentInstances(d, today),
        missedCycles(d, today).fold(0, (sum, m) => sum + m.missedCents),
      );
      expect(totals(after).capturedCents, totals(before).capturedCents);
      expect(totals(after).claimableCents, totals(before).claimableCents);
      expect(totals(after).missedCents, totals(before).missedCents);
      final benefitId = (ids.converted['benefitIds'] as Map)[ids.benefit];
      expect(after.claims.map((c) => c.benefitId).toSet(), {benefitId});
    });

    // @lat: [[api-tests#Conversion#The converted credits are the terms at conversion]]
    test('the converted card copies the resolved terms and state', () async {
      final before = await api.as('ann').post('/v1/cards', {
        'templateId': 'amex-gold',
        'anniversaryOn': '2024-05-01',
      });
      final resolved = [
        for (final b
            in (json(before)['benefits'] as List).cast<Map<String, dynamic>>())
          benefitFromJson(b),
      ];
      final id = (json(before)['card'] as Map)['id'];
      final converted = json(await api.as('ann').post('/v1/cards/$id/convert'));
      final benefits = [
        for (final b
            in (converted['benefits'] as List).cast<Map<String, dynamic>>())
          benefitFromJson(b),
      ];
      Map<String, Object?> terms(Benefit b) =>
          {...benefitToJson(b)}..removeWhere(
            (k, _) => const {
              'id',
              'cardId',
              'templateBenefitId',
              'createdAt',
              'updatedAt',
            }.contains(k),
          );
      // Copies keep their creation time but get new ids, so the order in
      // which they are listed is not the originals'.
      List<String> sorted(List<Benefit> list) =>
          [for (final b in list) jsonEncode(terms(b))]..sort();
      expect(sorted(benefits), sorted(resolved));
      expect(benefits.every((b) => b.templateBenefitId == null), isTrue);
    });

    // @lat: [[api-tests#Conversion#A new version leaves a converted card alone]]
    test('a version published after conversion changes nothing', () async {
      await convertedGold();
      final before = await data('ann');
      await db.execute('''
          INSERT INTO template_versions (template_id, version, effective_from,
            status, issuer, product, network, kind, annual_fee_cents)
          SELECT template_id, 2, '2000-01-02', 'draft', issuer, 'Gold Plus',
            network, kind, 1
          FROM template_versions WHERE template_id = 'amex-gold' AND version = 1
        ''');
      await db.execute('''
          INSERT INTO template_credits (template_id, version, credit_id,
            position, name, category, icon, value_cents, cadence, anchor)
          VALUES ('amex-gold', 2, 'amex-gold/only', 0, 'Only', 'dining',
            'fork-knife', 1, 'monthly', 'calendar')
        ''');
      await db.execute(
        "UPDATE template_versions SET status = 'published', "
        "published_by = 'test', published_at = now() "
        "WHERE template_id = 'amex-gold' AND version = 2",
      );
      final after = await data('ann');
      expect(appDataToJson(after), appDataToJson(before));
    });

    // @lat: [[api-tests#Conversion#Every member's mutes follow the card]]
    test('every member’s mutes point at the new ids', () async {
      final ids = await convertedGold();
      final newCard = (ids.converted['card'] as Map)['id'];
      final newBenefit = (ids.converted['benefitIds'] as Map)[ids.benefit];
      for (final uid in ['ann', 'bob']) {
        final prefs = memberPreferencesFromJson(
          json(await api.as(uid).get('/v1/me/preferences')),
        );
        expect(prefs.mutedCardIds, {newCard}, reason: uid);
        expect(prefs.mutedBenefitIds, {newBenefit}, reason: uid);
      }
    });

    // @lat: [[api-tests#Conversion#Only a linked card converts]]
    test(
      'adding a credit to a linked card is 409; converting twice too',
      () async {
        final added = json(
          await api.as('ann').post('/v1/cards', {
            'templateId': 'amex-gold',
            'anniversaryOn': '2024-05-01',
          }),
        );
        final id = (added['card'] as Map)['id'];
        expect(
          (await api.as('ann').post('/v1/cards/$id/benefits', {
            'name': 'Extra',
            'category': 'dining',
            'valueCents': 100,
            'cadence': 'monthly',
            'anchor': 'calendar',
          })).status,
          409,
        );
        final converted = json(
          await api.as('ann').post('/v1/cards/$id/convert'),
        );
        final newId = (converted['card'] as Map)['id'];
        final again = await api.as('ann').post('/v1/cards/$newId/convert');
        expect(again.status, 409);
        expect(json(again)['error'], 'user maintained');
        expect((await api.as('ann').post('/v1/cards/$id/convert')).status, 404);
      },
    );
  }, skip: url == null ? 'DATABASE_URL is not set' : false);
}
