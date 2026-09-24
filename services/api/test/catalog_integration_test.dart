import 'dart:io';

import 'package:api/catalog.dart';
import 'package:domain/domain.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'support/api.dart';
import 'support/database.dart';
import 'support/tokens.dart';

/// The catalogue in Postgres: the seed, published versions staying put, and
/// the two read routes. Against `DATABASE_URL` in the suite's own schema.
void main() {
  final url = Platform.environment['DATABASE_URL'];

  group(
    'catalogue against DATABASE_URL',
    () {
      late Connection db;
      late TestApi api;

      setUpAll(() async {
        db = await openMigratedSchema(url!, 'catalog');
        api = TestApi(await TestKey.generate(), db);
      });

      tearDownAll(() => dropSchema(db, 'catalog'));

      // Published versions cannot be deleted, so each test adds its own
      // templates under ids no other test uses, all starting `test-`.

      /// A copy of the Platinum as template [id], published as [version]
      /// from [from] with the Uber credit at [uberCents].
      Future<void> addVersion(
        String id,
        int version,
        String from, {
        int uberCents = 2000,
        String status = 'published',
      }) async {
        await db.execute(
          Sql.named(
            'INSERT INTO card_templates (id) VALUES (@id) '
            'ON CONFLICT DO NOTHING',
          ),
          parameters: {'id': id},
        );
        await db.execute(
          Sql.named('''
            INSERT INTO template_versions
              (template_id, version, effective_from, status, issuer, product,
               network, kind, annual_fee_cents)
            VALUES (@id, @v, @from::date, 'draft', 'Test', 'Card', 'amex',
                    'personal', 0)
          '''),
          parameters: {'id': id, 'v': version, 'from': from},
        );
        await db.execute(
          Sql.named('''
            INSERT INTO template_credits
              (template_id, version, credit_id, position, name, category,
               icon, value_cents, cadence, anchor)
            VALUES (@id, @v, @id || '/uber', 0, 'Uber', 'rideshare', 'car',
                    @cents, 'monthly', 'calendar')
          '''),
          parameters: {'id': id, 'v': version, 'cents': uberCents},
        );
        if (status == 'published') {
          await db.execute(
            Sql.named(
              "UPDATE template_versions SET status = 'published', "
              "published_by = 'test', published_at = now() "
              'WHERE template_id = @id AND version = @v',
            ),
            parameters: {'id': id, 'v': version},
          );
        }
      }

      // @lat: [[api-tests#Catalogue#The seed is version 1 of every template]]
      test(
        'every catalogue template is published version 1, as written',
        () async {
          final versions = await publishedVersions(db);
          final seeded = {
            for (final v in versions)
              if (!v.templateId.startsWith('test-')) v.templateId: v,
          };
          final expected = cardTemplates.where((t) => t.id != 'blank');
          expect(seeded.keys.toSet(), expected.map((t) => t.id).toSet());
          for (final template in expected) {
            final v = seeded[template.id]!;
            expect(v.version, 1);
            expect(
              templateVersionToJson(v),
              templateVersionToJson(
                TemplateVersion(
                  version: 1,
                  effectiveFrom: v.effectiveFrom,
                  template: template,
                ),
              ),
              reason: template.id,
            );
          }
        },
      );

      // @lat: [[api-tests#Catalogue#A published version cannot change]]
      test('the database refuses to change a published version', () async {
        Future<void> refused(String sql) => expectLater(
          db.execute(sql),
          throwsA(isA<ServerException>()),
          reason: sql,
        );
        await refused(
          "UPDATE template_credits SET value_cents = 1 "
          "WHERE template_id = 'amex-platinum'",
        );
        await refused(
          "DELETE FROM template_credits WHERE template_id = 'amex-gold'",
        );
        await refused(
          "UPDATE template_versions SET annual_fee_cents = 1 "
          "WHERE template_id = 'amex-gold'",
        );
        await refused(
          "INSERT INTO template_credits (template_id, version, credit_id, "
          "position, name, category, icon, value_cents, cadence, anchor) "
          "VALUES ('amex-gold', 1, 'amex-gold/new', 99, 'New', 'dining', "
          "'fork-knife', 100, 'monthly', 'calendar')",
        );
        // A draft stays editable until it is published.
        await addVersion('test-draft', 1, '2020-01-01', status: 'draft');
        await db.execute(
          "UPDATE template_credits SET value_cents = 5 "
          "WHERE template_id = 'test-draft'",
        );
      });

      // @lat: [[api-tests#Catalogue#The catalogue serves each template's version in force]]
      test(
        'GET /v1/catalog serves the latest version already in force',
        () async {
          await addVersion('test-in-force', 1, '2000-01-01', uberCents: 1500);
          await addVersion('test-in-force', 2, '2020-01-01', uberCents: 2000);
          await addVersion('test-in-force', 3, '2999-01-01', uberCents: 9900);
          await addVersion('test-hidden', 1, '2000-01-01', status: 'draft');

          final reply = await api.as('ann').get('/v1/catalog');
          expect(reply.status, 200);
          final templates = (reply.body! as List).cast<Map<String, dynamic>>();
          final plat = templates.firstWhere((t) => t['id'] == 'test-in-force');
          expect(plat['version'], 2);
          expect((plat['credits'] as List).single['valueCents'], 2000);
          expect(templates.any((t) => t['id'] == 'test-hidden'), isFalse);
          expect(
            templates.map((t) => t['id']),
            containsAll(['amex-platinum', 'chase-sapphire-reserve']),
          );
        },
      );

      // @lat: [[api-tests#Catalogue#One template's published versions]]
      test('GET /v1/catalog/{id} lists every published version', () async {
        await addVersion('test-plat', 1, '2000-01-01');
        await addVersion('test-plat', 2, '2999-01-01');
        await addVersion('test-plat', 3, '2999-06-01', status: 'draft');

        final reply = await api.as('ann').get('/v1/catalog/test-plat');
        expect(reply.status, 200);
        final body = reply.body! as Map<String, dynamic>;
        expect(body['id'], 'test-plat');
        expect((body['versions'] as List).map((v) => (v as Map)['version']), [
          1,
          2,
        ]);
        expect((await api.as('ann').get('/v1/catalog/nope')).status, 404);
      });
    },
    skip: url == null ? 'DATABASE_URL is not set' : false,
  );
}
