import 'dart:io';

import 'package:domain/domain.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'support/api.dart';
import 'support/database.dart';
import 'support/tokens.dart';

/// Cards owned by the person who added them, shared person to person by
/// invite, through the handler as several signed-in users, against
/// `DATABASE_URL` in the suite's own schema; skipped without one.
void main() {
  final url = Platform.environment['DATABASE_URL'];

  group('owners and shares against DATABASE_URL', () {
    late Connection db;
    late TestApi api;

    setUpAll(() async {
      db = await openMigratedSchema(url!, 'shares');
      api = TestApi(await TestKey.generate(), db);
    });

    tearDownAll(() => dropSchema(db, 'shares'));

    setUp(() => db.execute('TRUNCATE users CASCADE'));

    Map<String, dynamic> json(Reply r) => r.body! as Map<String, dynamic>;
    List<Map<String, dynamic>> list(Object? l) =>
        (l! as List).cast<Map<String, dynamic>>();

    const goldBody = {'templateId': 'amex-gold', 'anniversaryOn': '2024-05-01'};

    /// [uid]'s new Gold, labelled [label] when given.
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
        benefit: list(json(reply)['benefits']).first['id'] as String,
      );
    }

    /// An invite from [owner] to all their cards, or to [cardIds].
    Future<String> invite(
      String owner,
      String access, {
      List<String>? cardIds,
    }) async {
      final reply = await api.as(owner).post('/v1/invites', {
        'access': access,
        if (cardIds == null) 'allCards': true else 'cardIds': cardIds,
      });
      expect(reply.status, 201, reason: '${reply.body}');
      return json(reply)['code'] as String;
    }

    /// [owner] shares with [member], who accepts the invite.
    Future<void> share(
      String owner,
      String member,
      String access, {
      List<String>? cardIds,
    }) async {
      final code = await invite(owner, access, cardIds: cardIds);
      final reply = await api.as(member).post('/v1/invites/$code/accept');
      expect(reply.status, 200, reason: '${reply.body}');
    }

    Future<Map<String, dynamic>> snapshot(String uid) async {
      final reply = await api.as(uid).get('/v1/household/data');
      expect(reply.status, 200, reason: '${reply.body}');
      return json(reply);
    }

    Set<String> cardsIn(Map<String, dynamic> snapshot) => {
      for (final card in appDataFromJson(snapshot).cards) card.id,
    };

    Future<Reply> claim(String uid, String benefit, String key) => api
        .as(uid)
        .send(
          'POST',
          '/v1/claims',
          body: {
            'benefitId': benefit,
            'cycleKey': '2026-09-01',
            'amountCents': 500,
          },
          headers: {'idempotency-key': key},
        );

    const terms = {
      'name': 'Dining',
      'category': 'dining',
      'valueCents': 1000,
      'cadence': 'monthly',
      'anchor': 'calendar',
    };

    // @lat: [[api-tests#Owners and shares#A view share reads the owner's card and changes nothing]]
    test(
      'a view share shows the owner’s card and refuses its writes',
      () async {
        final gold = await addGold('ann');
        await share('ann', 'bob', 'view');
        final annId = await api.as('ann').id();

        final seen = await snapshot('bob');
        final card = appDataFromJson(seen).cards.single;
        expect(card.id, gold.card);
        expect(card.ownerId, annId);
        expect(seen['access'], {gold.card: 'view'});
        expect(seen['people'], [
          {'id': annId, 'name': 'Ann', 'email': 'ann@x.test'},
        ]);

        final refused = [
          await claim('bob', gold.benefit, 'v-1'),
          await api.as('bob').put('/v1/benefits/${gold.benefit}/state', {
            'enrolledAt': '2026-09-01T00:00:00.000Z',
          }),
          await api.as('bob').patch('/v1/cards/${gold.card}', {
            'label': 'Mine',
          }),
        ];
        expect(refused.map((r) => r.status), everyElement(403));

        final own = await snapshot('ann');
        expect(own['access'], {gold.card: 'owner'});
        expect(own['people'], isEmpty);
        expect(appDataFromJson(own).cards.single.ownerId, annId);
      },
    );

    // @lat: [[api-tests#Owners and shares#A record share logs usage and changes nothing else]]
    test('a record share claims and sets state, and nothing else', () async {
      final gold = await addGold('ann');
      final freedom = await api.as('ann').post('/v1/cards', {
        'issuer': 'Chase',
        'product': 'Freedom',
        'network': 'visa',
        'annualFeeCents': 0,
        'anniversaryOn': '2023-01-15',
      });
      final own = (json(freedom)['card'] as Map)['id'] as String;
      final credit = json(
        await api.as('ann').post('/v1/cards/$own/benefits', terms),
      );
      await share('ann', 'bob', 'record');

      final claimed = await claim('bob', gold.benefit, 'r-1');
      expect(claimed.status, 201, reason: '${claimed.body}');
      final state = await api.as('bob').put(
        '/v1/benefits/${gold.benefit}/state',
        {'enrolledAt': '2026-09-01T00:00:00.000Z'},
      );
      expect(state.status, 200, reason: '${state.body}');
      final annSees = appDataFromJson(await snapshot('ann'));
      expect(annSees.claims.single.id, json(claimed)['id']);
      expect(
        annSees.benefits.firstWhere((b) => b.id == gold.benefit).enrolledAt,
        '2026-09-01T00:00:00.000Z',
      );
      expect(
        (await api.as('bob').delete('/v1/claims/${json(claimed)['id']}'))
            .status,
        204,
      );

      final refused = [
        await api.as('bob').patch('/v1/cards/${gold.card}', {'label': 'Mine'}),
        await api.as('bob').put('/v1/benefits/${credit['id']}', {
          ...terms,
          'valueCents': 1,
        }),
        await api.as('bob').post('/v1/cards/$own/benefits', terms),
        await api.as('bob').delete('/v1/benefits/${credit['id']}'),
        await api.as('bob').delete('/v1/cards/${gold.card}'),
        await api.as('bob').post('/v1/cards/${gold.card}/convert'),
      ];
      expect(refused.map((r) => r.status), everyElement(403));
      expect((await snapshot('bob'))['access'], {
        gold.card: 'record',
        own: 'record',
      });
    });

    // @lat: [[api-tests#Owners and shares#Without a share a card is not found]]
    test('someone with no share gets 404 for the card, its credits and '
        'claims', () async {
      final gold = await addGold('ann');
      final claimed = await claim('ann', gold.benefit, 'a-1');
      expect(claimed.status, 201, reason: '${claimed.body}');
      await share('ann', 'bob', 'record');

      final cat = api.as('cat');
      final replies = [
        await cat.patch('/v1/cards/${gold.card}', {'label': 'x'}),
        await cat.delete('/v1/cards/${gold.card}'),
        await cat.put('/v1/benefits/${gold.benefit}/state', {}),
        await claim('cat', gold.benefit, 'c-1'),
        await cat.delete('/v1/claims/${json(claimed)['id']}'),
        await cat.put('/v1/me/mutes/cards/${gold.card}', {}),
        await cat.put('/v1/me/mutes/benefits/${gold.benefit}', {}),
        await cat.put('/v1/me/benefits/${gold.benefit}/level', {
          'level': 'silenced',
        }),
        await cat.post('/v1/cards/${gold.card}/terms-seen'),
      ];
      expect(replies.map((r) => r.status), everyElement(404));
      final catSees = await snapshot('cat');
      expect(cardsIn(catSees), isEmpty);
      expect(catSees['people'], isEmpty);
    });

    // @lat: [[api-tests#Owners and shares#A chosen-cards share shows only those cards]]
    test('a chosen-cards share shows only its cards, and an all-cards share '
        'also shows cards added later', () async {
      final first = await addGold('ann');
      final second = await addGold('ann');
      await claim('ann', second.benefit, 's-1');
      await share('ann', 'bob', 'view');
      await share('ann', 'cat', 'view', cardIds: [first.card]);
      final later = await addGold('ann');

      expect(cardsIn(await snapshot('bob')), {
        first.card,
        second.card,
        later.card,
      });
      final catSees = await snapshot('cat');
      expect(cardsIn(catSees), {first.card});
      expect(catSees['access'], {first.card: 'view'});
      final catData = appDataFromJson(catSees);
      expect(catData.benefits.map((b) => b.cardId).toSet(), {first.card});
      expect(catData.claims, isEmpty);
    });

    // @lat: [[api-tests#Owners and shares#Labels are unique per owner]]
    test('two people may each own a Gold or a Platinum; one person cannot '
        'own two', () async {
      await addGold('ann');
      await share('ann', 'bob', 'record');
      final bobsFirst = json(await api.as('bob').post('/v1/cards', goldBody));
      expect((bobsFirst['card'] as Map).containsKey('label'), isFalse);
      final bobsSecond = json(await api.as('bob').post('/v1/cards', goldBody));
      expect((bobsSecond['card'] as Map)['label'], 'American Express Gold (1)');

      await addGold('ann', label: 'Platinum');
      final bobsPlatinum = await api.as('bob').post('/v1/cards', {
        ...goldBody,
        'label': 'Platinum',
      });
      expect(bobsPlatinum.status, 201, reason: '${bobsPlatinum.body}');
      final annsSecond = await api.as('ann').post('/v1/cards', {
        ...goldBody,
        'label': ' platinum ',
      });
      expect(annsSecond.status, 409);
      expect(json(annsSecond)['error'], 'label taken');
    });

    // @lat: [[api-tests#Owners and shares#Accepting an invite creates a share and deletes nothing]]
    test('accepting an invite creates the share and keeps the caller’s '
        'cards', () async {
      final bobs = await addGold('bob');
      final anns = await addGold('ann');
      final annId = await api.as('ann').id();
      final code = await invite('ann', 'view');

      final accepted = await api.as('bob').post('/v1/invites/$code/accept');
      expect(accepted.status, 200, reason: '${accepted.body}');
      expect(json(accepted), {
        'id': annId,
        'name': 'Ann',
        'email': 'ann@x.test',
        'access': 'view',
        'allCards': true,
      });
      expect((await snapshot('bob'))['access'], {
        bobs.card: 'owner',
        anns.card: 'view',
      });

      final used = await api.as('bob').post('/v1/invites/$code/accept');
      expect(used.status, 410);
      expect(json(used)['error'], 'invite used');
      final again = await api
          .as('bob')
          .post('/v1/invites/${await invite('ann', 'record')}/accept');
      expect(again.status, 409);
      expect(json(again)['error'], 'already shared');
      final own = await api
          .as('ann')
          .post('/v1/invites/${await invite('ann', 'view')}/accept');
      expect(own.status, 409);
      expect(json(own)['error'], 'own invite');

      // A share the other way is a different share.
      await share('bob', 'ann', 'view');
      expect(cardsIn(await snapshot('ann')), {anns.card, bobs.card});

      final old = await invite('ann', 'view');
      await db.execute(
        Sql.named(
          "UPDATE invites SET expires_at = now() - interval '1 second' "
          'WHERE code = @c',
        ),
        parameters: {'c': old},
      );
      final expired = await api.as('cat').post('/v1/invites/$old/accept');
      expect(expired.status, 410);
      expect(json(expired)['error'], 'invite expired');
      expect(
        (await api.as('cat').post('/v1/invites/NOSUCH/accept')).status,
        404,
      );
    });

    // @lat: [[api-tests#Owners and shares#An invite says who shares what]]
    test('reading an invite names its owner, its access and its cards', () async {
      final first = await addGold('ann');
      final second = await addGold('ann');
      final annId = await api.as('ann').id();

      final all = await api
          .as('bob')
          .get('/v1/invites/${await invite('ann', 'view')}');
      expect(all.status, 200, reason: '${all.body}');
      expect(json(all), {
        'owner': {'id': annId, 'name': 'Ann', 'email': 'ann@x.test'},
        'access': 'view',
        'allCards': true,
        'expiresAt': isA<String>(),
      });
      final chosen = json(
        await api
            .as('bob')
            .get(
              '/v1/invites/${await invite('ann', 'record', cardIds: [first.card, second.card])}',
            ),
      );
      expect(chosen['access'], 'record');
      expect(chosen['allCards'], isFalse);
      expect(chosen['cardCount'], 2);

      expect((await api.as('bob').get('/v1/invites/NOSUCH')).status, 404);
      final used = await invite('ann', 'view');
      await api.as('cat').post('/v1/invites/$used/accept');
      final usedReply = await api.as('bob').get('/v1/invites/$used');
      expect(usedReply.status, 410);
      expect(json(usedReply)['error'], 'invite used');
    });

    // @lat: [[api-tests#Owners and shares#An invite shares the inviter's own cards]]
    test('an invite needs an access and the inviter’s own cards', () async {
      final bobs = await addGold('bob');
      final anns = await addGold('ann');

      final badAccess = await api.as('ann').post('/v1/invites', {
        'access': 'edit',
        'allCards': true,
      });
      expect(badAccess.status, 400);
      expect(json(badAccess), {'error': 'invalid', 'field': 'access'});
      for (final body in [
        {'access': 'view'},
        {'access': 'view', 'cardIds': <String>[]},
        {
          'access': 'view',
          'allCards': true,
          'cardIds': [anns.card],
        },
      ]) {
        final reply = await api.as('ann').post('/v1/invites', body);
        expect(reply.status, 400, reason: '$body');
        expect(json(reply)['field'], 'cardIds', reason: '$body');
      }
      final others = await api.as('ann').post('/v1/invites', {
        'access': 'view',
        'cardIds': [anns.card, bobs.card],
      });
      expect(others.status, 404);

      final created = await api.as('ann').post('/v1/invites', {
        'access': 'record',
        'cardIds': [anns.card],
      });
      expect(created.status, 201, reason: '${created.body}');
      expect(
        json(created)['link'],
        endsWith('/invite/${json(created)['code']}'),
      );
      expect(json(created)['access'], 'record');
      expect(json(created)['allCards'], isFalse);
      expect(json(created)['cardIds'], [anns.card]);
    });
  }, skip: url == null ? 'DATABASE_URL is not set' : false);
}
