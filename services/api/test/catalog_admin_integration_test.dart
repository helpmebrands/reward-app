import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'support/api.dart';
import 'support/database.dart';
import 'support/tokens.dart';

/// The catalogue admin api: drafts, edits, publishing with provenance and
/// the published event. Against `DATABASE_URL` in the suite's own schema.
void main() {
  final url = Platform.environment['DATABASE_URL'];

  group('catalogue admin against DATABASE_URL', () {
    late Connection db;
    late TestApi api;
    late Caller admin;
    late Caller member;

    setUpAll(() async {
      db = await openMigratedSchema(url!, 'catalog_admin');
      api = TestApi(await TestKey.generate(), db);
      admin = api.as('admin');
      member = api.as('member');
      await db.execute(
        Sql.named('INSERT INTO admins (user_id) VALUES (@u::uuid)'),
        parameters: {'u': await admin.id()},
      );
    });

    tearDownAll(() => dropSchema(db, 'catalog_admin'));

    Map<String, dynamic> json(Reply r) => r.body! as Map<String, dynamic>;

    Future<int> events(String template) async =>
        (await db.execute(
              Sql.named(
                'SELECT count(*) FROM catalog_events WHERE template_id = @t',
              ),
              parameters: {'t': template},
            )).single[0]!
            as int;

    Future<List<int>> catalogVersions(String template) async {
      final reply = await member.get('/v1/catalog');
      return [
        for (final t in (reply.body! as List).cast<Map<String, dynamic>>())
          if (t['id'] == template) t['version'] as int,
      ];
    }

    // @lat: [[api-tests#Catalogue admin#Only admins reach the admin routes]]
    test('a non-admin gets 403 on every admin route', () async {
      final replies = [
        await member.post('/v1/admin/catalog', {'id': 'x'}),
        await member.post('/v1/admin/catalog/amex-gold/drafts'),
        await member.put('/v1/admin/catalog/amex-gold/drafts/2', {}),
        await member.post('/v1/admin/catalog/amex-gold/drafts/2/publish', {
          'effectiveFrom': '2026-10-01',
          'sourceUrl': 'https://example.com',
        }),
      ];
      expect(replies.map((r) => r.status), everyElement(403));
    });

    // @lat: [[api-tests#Catalogue admin#A draft is invisible until published]]
    test('a draft copies the latest version and stays hidden', () async {
      final draft = await admin.post('/v1/admin/catalog/amex-gold/drafts');
      expect(draft.status, 201);
      expect(json(draft)['version'], 2);
      expect(json(draft)['status'], 'draft');
      expect(
        (json(draft)['credits'] as List).map((c) => (c as Map)['id']),
        contains('amex-gold/uber-cash'),
      );
      // A second draft while one is open is refused.
      final again = await admin.post('/v1/admin/catalog/amex-gold/drafts');
      expect(again.status, 409);

      final edited = Map<String, dynamic>.of(json(draft))
        ..['annualFeeCents'] = 32500;
      final put = await admin.put(
        '/v1/admin/catalog/amex-gold/drafts/2',
        edited,
      );
      expect(put.status, 200, reason: '${put.body}');
      expect(json(put)['annualFeeCents'], 32500);
      expect(await catalogVersions('amex-gold'), [1]);

      final published = await admin
          .post('/v1/admin/catalog/amex-gold/drafts/2/publish', {
            'effectiveFrom': '2020-01-01',
            'sourceUrl': 'https://www.americanexpress.com/gold',
            'notes': 'Fee rise',
          });
      expect(published.status, 200, reason: '${published.body}');
      expect(json(published)['status'], 'published');
      expect(json(published)['publishedBy'], await admin.id());
      expect(
        json(published)['sourceUrl'],
        'https://www.americanexpress.com/gold',
      );
      expect(await catalogVersions('amex-gold'), [2]);
    });

    // @lat: [[api-tests#Catalogue admin#Publishing needs a date and a source]]
    test('publishing without effectiveFrom or sourceUrl is 400', () async {
      await admin.post('/v1/admin/catalog/amex-platinum/drafts');
      for (final body in [
        {'sourceUrl': 'https://example.com'},
        {'effectiveFrom': '2026-10-01'},
        {'effectiveFrom': 'soon', 'sourceUrl': 'https://example.com'},
        {'effectiveFrom': '2026-10-01', 'sourceUrl': 'not a url'},
      ]) {
        final reply = await admin.post(
          '/v1/admin/catalog/amex-platinum/drafts/2/publish',
          body,
        );
        expect(reply.status, 400, reason: '$body');
      }
    });

    // @lat: [[api-tests#Catalogue admin#A published version needs a new draft]]
    test('a published version cannot be edited; a new draft can', () async {
      await admin.post('/v1/admin/catalog/chase-sapphire-reserve/drafts');
      await admin.post(
        '/v1/admin/catalog/chase-sapphire-reserve/drafts/2/publish',
        {'effectiveFrom': '2026-10-01', 'sourceUrl': 'https://chase.com'},
      );
      final edit = await admin.put(
        '/v1/admin/catalog/chase-sapphire-reserve/drafts/2',
        {'annualFeeCents': 1},
      );
      expect(edit.status, 409);
      final republish = await admin.post(
        '/v1/admin/catalog/chase-sapphire-reserve/drafts/2/publish',
        {'effectiveFrom': '2026-10-01', 'sourceUrl': 'https://chase.com'},
      );
      expect(republish.status, 409);
      final next = await admin.post(
        '/v1/admin/catalog/chase-sapphire-reserve/drafts',
      );
      expect(json(next)['version'], 3);
    });

    // @lat: [[api-tests#Catalogue admin#Every publish writes one event]]
    test('each publish writes one catalog_events row', () async {
      expect(await events('amex-hilton-honors-aspire'), 0);
      for (var v = 2; v <= 3; v++) {
        await admin.post('/v1/admin/catalog/amex-hilton-honors-aspire/drafts');
        await admin.post(
          '/v1/admin/catalog/amex-hilton-honors-aspire/drafts/$v/publish',
          {'effectiveFrom': '2026-10-0$v', 'sourceUrl': 'https://hilton.com'},
        );
      }
      expect(await events('amex-hilton-honors-aspire'), 2);
      final row = (await db.execute(
        "SELECT kind, version FROM catalog_events "
        "WHERE template_id = 'amex-hilton-honors-aspire' ORDER BY id",
      )).first;
      expect(row, ['version published', 2]);
    });

    // @lat: [[api-tests#Catalogue admin#Edits follow the domain's rules]]
    test('a draft edit is checked by the domain rules', () async {
      final draft = json(
        await admin.post('/v1/admin/catalog/capital-one-venture-x/drafts'),
      );
      Future<Reply> withCredit(Map<String, Object?> change) {
        final credits = (draft['credits'] as List)
            .cast<Map<String, dynamic>>()
            .toList();
        credits[0] = {...credits[0], ...change};
        return admin.put(
          '/v1/admin/catalog/capital-one-venture-x/drafts/${draft['version']}',
          {...draft, 'credits': credits},
        );
      }

      final rolling = await withCredit({'cadence': 'rolling'});
      expect(rolling.status, 400);
      expect(json(rolling)['field'], 'credits[0].intervalMonths');
      expect(
        (await withCredit({'cadence': 'rolling', 'intervalMonths': 48})).status,
        200,
      );
      expect((await withCredit({'valueCents': 0})).status, 400);
      expect((await withCredit({'cadence': 'weekly'})).status, 400);
      expect(
        json(await withCredit({'id': 'other-card/credit'}))['field'],
        'credits[0].id',
      );
    });

    // @lat: [[api-tests#Catalogue admin#A new template starts as a draft]]
    test('a new template is a draft version 1 until published', () async {
      final created = await admin.post('/v1/admin/catalog', {
        'id': 'test-new-card',
        'issuer': 'Test Bank',
        'product': 'Rewards',
        'network': 'visa',
        'kind': 'personal',
        'annualFeeCents': 9500,
        'credits': [
          {
            'id': 'test-new-card/dining',
            'name': 'Dining',
            'category': 'dining',
            'icon': 'fork-knife',
            'valueCents': 1000,
            'cadence': 'monthly',
            'anchor': 'calendar',
          },
        ],
      });
      expect(created.status, 201, reason: '${created.body}');
      expect(json(created)['version'], 1);
      expect(json(created)['status'], 'draft');
      expect(await catalogVersions('test-new-card'), isEmpty);
      expect(
        (await admin.post('/v1/admin/catalog', {'id': 'amex-gold'})).status,
        409,
      );
      await admin.post('/v1/admin/catalog/test-new-card/drafts/1/publish', {
        'effectiveFrom': '2020-01-01',
        'sourceUrl': 'https://example.com/card',
      });
      expect(await catalogVersions('test-new-card'), [1]);
    });
  }, skip: url == null ? 'DATABASE_URL is not set' : false);
}
