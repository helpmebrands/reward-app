import 'dart:io';

import 'package:api/change_notices.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'support/api.dart';
import 'support/database.dart';
import 'support/push.dart';
import 'support/tokens.dart';

/// Catalogue change notices and the terms-changed mark, against
/// `DATABASE_URL` in the suite's own schema; skipped without one.
///
/// Ann's household holds a linked Gold and Bob is in it; Cat's household
/// held a Gold and converted it. An admin then publishes Gold version 2,
/// raising Uber Cash to $20 from 1 January 2027.
void main() {
  final url = Platform.environment['DATABASE_URL'];

  group('change notices against DATABASE_URL', () {
    late Connection db;
    late FakePush push;
    late TestApi api;
    late String annsGold;
    late String catsGold;

    final now = DateTime.utc(2026, 12, 1, 12);

    // A published version can never be deleted, so each test gets a fresh
    // schema rather than a truncated one.
    setUp(() async {
      db = await openMigratedSchema(url!, 'change_notices');
    });

    tearDown(() => dropSchema(db, 'change_notices'));

    Map<String, dynamic> json(Reply r) => r.body! as Map<String, dynamic>;

    Future<void> device(String uid) async {
      final r = await api.as(uid).post('/v1/devices', {
        'token': '$uid-phone',
        'installationId': 'inst-$uid',
        'platform': 'android',
        'timezone': 'Europe/London',
      });
      expect(r.status, 200, reason: '${r.body}');
    }

    Future<void> remindersOn(String uid) async {
      final r = await api.as(uid).put('/v1/me/preferences', {
        'enabled': true,
        'timeOfDay': '09:00',
        'minValueCents': 100,
        'annualFeeReminder': true,
        'enrollmentReminder': true,
      });
      expect(r.status, 200, reason: '${r.body}');
    }

    Future<String> gold(String uid) async {
      final r = await api.as(uid).post('/v1/cards', {
        'templateId': 'amex-gold',
        'anniversaryOn': '2024-05-01',
      });
      expect(r.status, 201, reason: '${r.body}');
      return (json(r)['card'] as Map)['id'] as String;
    }

    /// Gold version 2: Uber Cash to $20 from 1 January 2027.
    Future<void> publishGoldV2() async {
      final admin = api.as('admin');
      final draft = json(
        await admin.post('/v1/admin/catalog/amex-gold/drafts'),
      );
      for (final c in (draft['credits'] as List).cast<Map<String, dynamic>>()) {
        if (c['id'] == 'amex-gold/uber-cash') c['valueCents'] = 2000;
      }
      final put = await admin.put(
        '/v1/admin/catalog/amex-gold/drafts/2',
        draft,
      );
      expect(put.status, 200, reason: '${put.body}');
      final published = await admin
          .post('/v1/admin/catalog/amex-gold/drafts/2/publish', {
            'effectiveFrom': '2027-01-01',
            'sourceUrl': 'https://www.americanexpress.com/gold',
          });
      expect(published.status, 200, reason: '${published.body}');
    }

    List<Object?> marks(Reply data) =>
        (json(data)['termsChanged'] as List?) ?? const [];

    setUp(() async {
      push = FakePush();
      api = TestApi(await TestKey.generate(), db, push: push);
      await db.execute(
        Sql.named('INSERT INTO admins (user_id) VALUES (@u::uuid)'),
        parameters: {'u': await api.as('admin').id()},
      );

      annsGold = await gold('ann');
      final code =
          json(
                await api.as('ann').post('/v1/household/invites', {
                  'role': 'edit',
                }),
              )['code']
              as String;
      await api.as('bob').post('/v1/invites/$code/accept', {
        'confirmLeave': false,
      });
      catsGold = await gold('cat');
      final converted = await api.as('cat').post('/v1/cards/$catsGold/convert');
      expect(converted.status, 200, reason: '${converted.body}');
      catsGold = (json(converted)['card'] as Map)['id'] as String;

      for (final uid in ['ann', 'bob', 'cat']) {
        await remindersOn(uid);
        await device(uid);
      }
    });

    // @lat: [[api-tests#Change notices#Each holder of an affected linked card hears once]]
    test(
      'publishing notifies each member holding the linked card once',
      () async {
        await publishGoldV2();
        final sent = await sendChangeNotices(db, push, now: now);
        expect(sent, 2);
        expect(push.tagsTo('ann-phone'), ['terms-$annsGold']);
        expect(push.tagsTo('bob-phone'), ['terms-$annsGold']);
        final notice = push.sent.first.message;
        expect(
          notice.body,
          contains(r'Uber Cash credit changes to $20 on Jan 1'),
        );
        expect(notice.data['url'], '/cards/$annsGold');

        expect(await sendChangeNotices(db, push, now: now), 0);
        expect(push.sent, hasLength(2));

        final data = await api.as('ann').get('/v1/household/data');
        expect(marks(data), [
          {
            'cardId': annsGold,
            'version': 2,
            'effectiveFrom': '2027-01-01',
            'changes': [r'Uber Cash credit changes to $20'],
          },
        ]);
      },
    );

    // @lat: [[api-tests#Change notices#A muted card gets the mark without the push]]
    test(
      'a member who muted the card gets no push but sees the mark',
      () async {
        expect(
          (await api.as('bob').put('/v1/me/mutes/cards/$annsGold', {})).status,
          204,
        );
        await publishGoldV2();
        await sendChangeNotices(db, push, now: now);
        expect(push.tagsTo('bob-phone'), isEmpty);
        expect(push.tagsTo('ann-phone'), ['terms-$annsGold']);
        expect(
          marks(await api.as('bob').get('/v1/household/data')),
          hasLength(1),
        );
      },
    );

    // @lat: [[api-tests#Change notices#A converted card hears nothing]]
    test('a converted card gets neither a push nor a mark', () async {
      await publishGoldV2();
      await sendChangeNotices(db, push, now: now);
      expect(push.tagsTo('cat-phone'), isEmpty);
      expect(marks(await api.as('cat').get('/v1/household/data')), isEmpty);
    });

    // @lat: [[api-tests#Change notices#Seeing the mark clears it for that member only]]
    test(
      'marking the terms seen clears the mark for the caller only',
      () async {
        await publishGoldV2();
        await sendChangeNotices(db, push, now: now);

        final seen = await api.as('ann').post('/v1/cards/$annsGold/terms-seen');
        expect(seen.status, 204);
        expect(marks(await api.as('ann').get('/v1/household/data')), isEmpty);
        expect(
          marks(await api.as('bob').get('/v1/household/data')),
          hasLength(1),
        );

        final elsewhere = await api
            .as('cat')
            .post('/v1/cards/$annsGold/terms-seen');
        expect(elsewhere.status, 404);
      },
    );
  }, skip: url == null ? 'DATABASE_URL is not set' : false);
}
