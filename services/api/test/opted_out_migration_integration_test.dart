import 'dart:io';

import 'package:api/migrate.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

/// The migration that brings opting out to the server: credits paused before
/// it existed become opted out, unless they had already ended. Runs the
/// migrations before it, seeds paused rows, then applies the rest.
void main() {
  final url = Platform.environment['DATABASE_URL'];

  group('the opted-out migration against DATABASE_URL', () {
    late Connection db;
    late Directory before;

    setUp(() async {
      db = await Connection.openFromUrl(url!);
      await db.execute('DROP SCHEMA IF EXISTS opted_out_migration CASCADE');
      await db.execute('CREATE SCHEMA opted_out_migration');
      await db.execute('SET search_path TO opted_out_migration');
      before = await Directory.systemTemp.createTemp('before-opted-out-');
      for (final file in Directory('migrations').listSync().whereType<File>()) {
        final name = file.uri.pathSegments.last;
        if (int.parse(name.substring(0, 4)) <= 11) {
          file.copySync('${before.path}/$name');
        }
      }
    });

    tearDown(() async {
      await db.execute('DROP SCHEMA opted_out_migration CASCADE');
      await db.close();
      await before.delete(recursive: true);
    });

    // @lat: [[api-tests#Household data#Paused credits migrate to opted out]]
    test('moves paused credits that had not ended to opted out', () async {
      await migrate(db, before);
      final household =
          (await db.execute(
                'INSERT INTO households DEFAULT VALUES RETURNING id::text',
              )).single[0]!
              as String;
      Future<String> card(String? templateId) async =>
          (await db.execute(
                Sql.named('''
              INSERT INTO cards (household_id, template_id, issuer, product,
                network, annual_fee_cents, anniversary_on)
              VALUES (@h::uuid, @t, 'Chase', 'Own', 'visa', 0, '2024-01-01')
              RETURNING id::text
            '''),
                parameters: {'h': household, 't': templateId},
              )).single[0]!
              as String;
      final own = await card(null);
      final linked = await card('chase-sapphire-reserve');

      Future<String> benefit(
        String cardId, {
        String? credit,
        String? endsOn,
        required bool active,
        required String updatedAt,
      }) async =>
          (await db.execute(
                Sql.named('''
              INSERT INTO benefits (household_id, card_id, template_credit_id,
                name, category, value_cents, cadence, anchor,
                enrollment_required, ends_on, active, updated_at)
              VALUES (@h::uuid, @c::uuid, @credit,
                CASE WHEN @credit::text IS NULL THEN 'Own credit' END,
                'dining', 1000, 'monthly', 'calendar', false, @ends::date,
                @active, @at::timestamptz)
              RETURNING id::text
            '''),
                parameters: {
                  'h': household,
                  'c': cardId,
                  'credit': credit,
                  'ends': endsOn,
                  'active': active,
                  'at': updatedAt,
                },
              )).single[0]!
              as String;

      const pausedAt = '2026-05-01T09:00:00.000Z';
      final paused = await benefit(own, active: false, updatedAt: pausedAt);
      final endingLater = await benefit(
        own,
        endsOn: '2026-12-31',
        active: false,
        updatedAt: pausedAt,
      );
      final ended = await benefit(
        own,
        endsOn: '2026-03-31',
        active: false,
        updatedAt: pausedAt,
      );
      final tracked = await benefit(own, active: true, updatedAt: pausedAt);
      final linkedPaused = await benefit(
        linked,
        credit: 'chase-sapphire-reserve/stubhub-viagogo-credit',
        active: false,
        updatedAt: pausedAt,
      );
      final linkedEnded = await benefit(
        linked,
        credit: 'chase-sapphire-reserve/doordash-restaurant-promo',
        active: false,
        updatedAt: '2028-01-15T09:00:00.000Z',
      );

      await migrate(db, Directory('migrations'));

      Future<(bool, String?, Object?)> row(String id) async {
        final r = (await db.execute(
          Sql.named(
            'SELECT active, opted_out_at, tracked_from FROM benefits '
            'WHERE id = @id::uuid',
          ),
          parameters: {'id': id},
        )).single;
        return (r[0]! as bool, r[1] as String?, r[2]);
      }

      expect(await row(paused), (true, pausedAt, null));
      expect(await row(endingLater), (true, pausedAt, null));
      expect(await row(ended), (false, null, null));
      expect(await row(tracked), (true, null, null));
      expect(await row(linkedPaused), (true, pausedAt, null));
      expect(await row(linkedEnded), (false, null, null));
    });
  }, skip: url == null ? 'DATABASE_URL is not set' : null);
}
