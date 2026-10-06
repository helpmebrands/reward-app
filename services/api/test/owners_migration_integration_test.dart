import 'dart:io';

import 'package:api/migrate.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

/// The migration that replaces households with owners and shares: a
/// household's cards go to its owner, every other member gets an all-cards
/// share from them, and the claims are attributed to the card's owner. Runs
/// the migrations before it, seeds a household, then applies the rest.
void main() {
  final url = Platform.environment['DATABASE_URL'];

  group('the owners migration against DATABASE_URL', () {
    late Connection db;
    late Directory before;

    setUp(() async {
      db = await Connection.openFromUrl(url!);
      await db.execute('DROP SCHEMA IF EXISTS owners_migration CASCADE');
      await db.execute('CREATE SCHEMA owners_migration');
      await db.execute('SET search_path TO owners_migration');
      before = await Directory.systemTemp.createTemp('before-owners-');
      for (final file in Directory('migrations').listSync().whereType<File>()) {
        final name = file.uri.pathSegments.last;
        if (int.parse(name.substring(0, 4)) <= 14) {
          file.copySync('${before.path}/$name');
        }
      }
    });

    tearDown(() async {
      await db.execute('DROP SCHEMA owners_migration CASCADE');
      await db.close();
      await before.delete(recursive: true);
    });

    // @lat: [[api-tests#Owners and shares#Households migrate to owners and shares]]
    test('gives a household’s cards to its owner and shares them with the '
        'other members', () async {
      await migrate(db, before);
      Future<String> one(String sql, [Map<String, Object?>? p]) async =>
          (await db.execute(Sql.named(sql), parameters: p)).single[0]!
              as String;

      final household = await one(
        'INSERT INTO households DEFAULT VALUES RETURNING id::text',
      );
      Future<String> member(String uid, String role) async {
        final user = await one(
          'INSERT INTO users (firebase_uid) VALUES (@uid) RETURNING id::text',
          {'uid': uid},
        );
        await db.execute(
          Sql.named(
            'INSERT INTO memberships (household_id, user_id, role) '
            'VALUES (@h::uuid, @u::uuid, @r)',
          ),
          parameters: {'h': household, 'u': user, 'r': role},
        );
        return user;
      }

      final ann = await member('ann', 'owner');
      final bob = await member('bob', 'editor');
      final rex = await member('rex', 'reader');
      final card = await one(
        '''
        INSERT INTO cards (household_id, issuer, product, network,
          annual_fee_cents, anniversary_on)
        VALUES (@h::uuid, 'Chase', 'Own', 'visa', 0, '2024-01-01')
        RETURNING id::text
        ''',
        {'h': household},
      );
      final benefit = await one(
        '''
        INSERT INTO benefits (household_id, card_id, name, category,
          value_cents, cadence, anchor, enrollment_required)
        VALUES (@h::uuid, @c::uuid, 'Dining', 'dining', 1000, 'monthly',
          'calendar', false)
        RETURNING id::text
        ''',
        {'h': household, 'c': card},
      );
      for (final key in ['k-1', 'k-2']) {
        await db.execute(
          Sql.named('''
            INSERT INTO claims (household_id, benefit_id, cycle_key,
              amount_cents, claimed_at, idempotency_key, request_body)
            VALUES (@h::uuid, @b::uuid, '2026-09-01', 500,
              '2026-09-10T12:00:00.000Z', @key, '{}')
          '''),
          parameters: {'h': household, 'b': benefit, 'key': key},
        );
      }
      await db.execute(
        Sql.named('''
          INSERT INTO invites (code, household_id, role, created_by, expires_at)
          VALUES ('ABCD2345', @h::uuid, 'reader', @u::uuid,
            now() + interval '1 day')
        '''),
        parameters: {'h': household, 'u': ann},
      );

      await migrate(db, Directory('migrations'));

      expect(
        (await db.execute('SELECT owner_id::text FROM cards')).single[0],
        ann,
      );
      final shares = await db.execute(
        'SELECT owner_id::text, member_id::text, access, all_cards '
        'FROM shares',
      );
      expect(
        {for (final r in shares) (r[0], r[1], r[2], r[3])},
        {(ann, bob, 'record', true), (ann, rex, 'view', true)},
      );
      final recorders = await db.execute(
        'SELECT DISTINCT recorded_by::text FROM claims',
      );
      expect([for (final r in recorders) r[0]], [ann]);
      expect((await db.execute('SELECT count(*) FROM claims')).single[0], 2);
      expect((await db.execute('SELECT count(*) FROM invites')).single[0], 0);
      final access = await db.execute(
        Sql.named(
          'SELECT user_id::text, access FROM card_access '
          'WHERE card_id = @c::uuid',
        ),
        parameters: {'c': card},
      );
      expect(
        {for (final r in access) r[0]: r[1]},
        {ann: 'owner', bob: 'record', rex: 'view'},
      );
      final gone = await db.execute(
        "SELECT to_regclass('households'), to_regclass('memberships')",
      );
      expect(gone.single, [null, null]);
    });
  }, skip: url == null ? 'DATABASE_URL is not set' : null);
}
