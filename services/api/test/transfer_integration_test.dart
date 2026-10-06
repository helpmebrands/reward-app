import 'dart:io';

import 'package:domain/domain.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'support/api.dart';
import 'support/database.dart';
import 'support/tokens.dart';

/// Handing a card to someone it is shared with, through the handler as
/// several signed-in users, against `DATABASE_URL` in the suite's own
/// schema; skipped without one.
void main() {
  final url = Platform.environment['DATABASE_URL'];

  group('card transfer against DATABASE_URL', () {
    late Connection db;
    late TestApi api;

    setUpAll(() async {
      db = await openMigratedSchema(url!, 'transfer');
      api = TestApi(await TestKey.generate(), db);
    });

    tearDownAll(() => dropSchema(db, 'transfer'));

    setUp(() => db.execute('TRUNCATE users CASCADE'));

    Map<String, dynamic> json(Reply r) => r.body! as Map<String, dynamic>;

    const goldBody = {'templateId': 'amex-gold', 'anniversaryOn': '2024-05-01'};

    Future<({String card, String benefit})> addGold(
      String uid, {
      String? label,
    }) async {
      final reply = await api.as(uid).post('/v1/cards', {
        ...goldBody,
        'label': ?label,
      });
      expect(reply.status, 201, reason: '${reply.body}');
      return (
        card: (json(reply)['card'] as Map)['id'] as String,
        benefit:
            ((json(reply)['benefits'] as List).first as Map)['id'] as String,
      );
    }

    Future<void> share(
      String owner,
      String member,
      String access, {
      List<String>? cardIds,
    }) async {
      final created = await api.as(owner).post('/v1/invites', {
        'access': access,
        if (cardIds == null) 'allCards': true else 'cardIds': cardIds,
      });
      expect(created.status, 201, reason: '${created.body}');
      final accepted = await api
          .as(member)
          .post('/v1/invites/${json(created)['code']}/accept');
      expect(accepted.status, 200, reason: '${accepted.body}');
    }

    Future<Map<String, dynamic>> snapshot(String uid) async {
      final reply = await api.as(uid).get('/v1/household/data');
      expect(reply.status, 200, reason: '${reply.body}');
      return json(reply);
    }

    Future<Reply> transfer(String uid, String card, String to) =>
        api.as(uid).post('/v1/cards/$card/transfer', {'userId': to});

    // @lat: [[api-tests#Card transfer#The new owner owns the card and the previous owner keeps it]]
    test(
      'the new owner owns the card and the previous owner records on it',
      () async {
        final gold = await addGold('ann');
        await share('ann', 'bob', 'view');
        final annId = await api.as('ann').id();
        final bobId = await api.as('bob').id();

        final moved = await transfer('ann', gold.card, bobId);
        expect(moved.status, 204, reason: '${moved.body}');

        final bobs = await snapshot('bob');
        expect(bobs['access'], {gold.card: 'owner'});
        expect(appDataFromJson(bobs).cards.single.ownerId, bobId);
        final anns = await snapshot('ann');
        expect(anns['access'], {gold.card: 'record'});
        expect(anns['people'], [
          {'id': bobId, 'name': 'Bob', 'email': 'bob@x.test'},
        ]);
        // Bob shares it back with Ann as a chosen card of a new share.
        final given = json(await api.as('bob').get('/v1/shares'))['given'];
        expect(given, [
          {
            'id': annId,
            'name': 'Ann',
            'email': 'ann@x.test',
            'access': 'record',
            'allCards': false,
            'cardIds': [gold.card],
          },
        ]);
      },
    );

    // @lat: [[api-tests#Card transfer#A share the new owner already gives takes the card]]
    test('a share the new owner already gives takes the card in', () async {
      final gold = await addGold('ann');
      final bobs = await addGold('bob', label: 'Bob’s Gold');
      await share('ann', 'bob', 'view');
      await share('bob', 'ann', 'view', cardIds: [bobs.card]);
      final bobId = await api.as('bob').id();

      expect((await transfer('ann', gold.card, bobId)).status, 204);
      final anns = await snapshot('ann');
      expect(anns['access'], {gold.card: 'view', bobs.card: 'view'});
    });

    // @lat: [[api-tests#Card transfer#Claims, state and mutes stay]]
    test('claims, credit state and everyone’s mutes stay', () async {
      final gold = await addGold('ann');
      await share('ann', 'bob', 'record');
      final bobId = await api.as('bob').id();
      final claimed = await api
          .as('bob')
          .send(
            'POST',
            '/v1/claims',
            body: {
              'benefitId': gold.benefit,
              'cycleKey': '2026-09-01',
              'amountCents': 500,
            },
            headers: {'idempotency-key': 't-1'},
          );
      expect(claimed.status, 201, reason: '${claimed.body}');
      await api.as('ann').put('/v1/benefits/${gold.benefit}/state', {
        'enrolledAt': '2026-09-01T00:00:00.000Z',
      });
      await api.as('ann').put('/v1/me/mutes/cards/${gold.card}', {});
      await api.as('bob').put('/v1/me/mutes/benefits/${gold.benefit}', {});
      final before = appDataFromJson(await snapshot('ann'));

      expect((await transfer('ann', gold.card, bobId)).status, 204);
      final after = appDataFromJson(await snapshot('bob'));
      expect(after.claims.map(claimToJson), before.claims.map(claimToJson));
      expect(
        after.benefits.firstWhere((b) => b.id == gold.benefit).enrolledAt,
        '2026-09-01T00:00:00.000Z',
      );
      Future<MemberPreferences> prefs(String uid) async =>
          memberPreferencesFromJson(
            json(await api.as(uid).get('/v1/me/preferences')),
          );
      expect((await prefs('ann')).mutedCardIds, {gold.card});
      expect((await prefs('bob')).mutedBenefitIds, {gold.benefit});
    });

    // @lat: [[api-tests#Card transfer#The previous owner's other shares stop covering it]]
    test('someone who saw it only through the previous owner no longer '
        'does', () async {
      final gold = await addGold('ann');
      final kept = await addGold('ann');
      await share('ann', 'bob', 'view');
      await share('ann', 'cat', 'view', cardIds: [gold.card, kept.card]);
      final bobId = await api.as('bob').id();

      expect((await transfer('ann', gold.card, bobId)).status, 204);
      final cats = appDataFromJson(await snapshot('cat'));
      expect(cats.cards.map((c) => c.id), [kept.card]);
    });

    // @lat: [[api-tests#Card transfer#Only the owner hands a card to someone who sees it]]
    test('only the owner transfers, to someone who sees the card and has no '
        'card of its name', () async {
      final gold = await addGold('ann', label: 'Travel');
      await share('ann', 'bob', 'record');
      final annId = await api.as('ann').id();
      final bobId = await api.as('bob').id();
      final catId = await api.as('cat').id();

      expect((await transfer('bob', gold.card, annId)).status, 403);
      expect((await transfer('cat', gold.card, bobId)).status, 404);
      expect((await transfer('ann', gold.card, catId)).status, 404);
      final bad = await api.as('ann').post('/v1/cards/${gold.card}/transfer', {
        'userId': 5,
      });
      expect(bad.status, 400);
      expect(json(bad), {'error': 'invalid', 'field': 'userId'});

      await addGold('bob', label: ' travel ');
      final taken = await transfer('ann', gold.card, bobId);
      expect(taken.status, 409);
      expect(json(taken)['error'], 'label taken');
      expect(
        (await snapshot('ann'))['access'],
        containsPair(gold.card, 'owner'),
      );
    });
  }, skip: url == null ? 'DATABASE_URL is not set' : false);
}
