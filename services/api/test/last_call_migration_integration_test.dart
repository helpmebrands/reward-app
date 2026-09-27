import 'dart:io';

import 'package:api/migrate.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

/// The migration that moves last call from the household's credit to each
/// member: a `last_call_only` credit becomes a last-call row for every
/// current member of its household. Runs the migrations before it, seeds
/// rows, then applies the rest.
void main() {
  final url = Platform.environment['DATABASE_URL'];

  group('the last-call migration against DATABASE_URL', () {
    late Connection db;
    late Directory before;

    setUp(() async {
      db = await Connection.openFromUrl(url!);
      await db.execute('DROP SCHEMA IF EXISTS last_call_migration CASCADE');
      await db.execute('CREATE SCHEMA last_call_migration');
      await db.execute('SET search_path TO last_call_migration');
      before = await Directory.systemTemp.createTemp('before-last-call-');
      for (final file in Directory('migrations').listSync().whereType<File>()) {
        final name = file.uri.pathSegments.last;
        if (int.parse(name.substring(0, 4)) <= 12) {
          file.copySync('${before.path}/$name');
        }
      }
    });

    tearDown(() async {
      await db.execute('DROP SCHEMA last_call_migration CASCADE');
      await db.close();
      await before.delete(recursive: true);
    });

    // @lat: [[api-tests#Member preferences#Last call only migrates to every member]]
    test(
      'gives every member a last-call row for a last_call_only credit',
      () async {
        await migrate(db, before);
        Future<String> one(String sql, [Map<String, Object?>? p]) async =>
            (await db.execute(Sql.named(sql), parameters: p)).single[0]!
                as String;

        final household = await one(
          'INSERT INTO households DEFAULT VALUES RETURNING id::text',
        );
        final elsewhere = await one(
          'INSERT INTO households DEFAULT VALUES RETURNING id::text',
        );
        Future<String> member(String uid, String h, String role) async {
          final user = await one(
            'INSERT INTO users (firebase_uid) VALUES (@uid) RETURNING id::text',
            {'uid': uid},
          );
          await db.execute(
            Sql.named(
              'INSERT INTO memberships (household_id, user_id, role) '
              'VALUES (@h::uuid, @u::uuid, @r)',
            ),
            parameters: {'h': h, 'u': user, 'r': role},
          );
          return user;
        }

        final ann = await member('ann', household, 'owner');
        final bob = await member('bob', household, 'reader');
        await member('cat', elsewhere, 'owner');
        final card = await one(
          '''
        INSERT INTO cards (household_id, issuer, product, network,
          annual_fee_cents, anniversary_on)
        VALUES (@h::uuid, 'Chase', 'Own', 'visa', 0, '2024-01-01')
        RETURNING id::text
        ''',
          {'h': household},
        );
        Future<String> benefit({required bool lastCall}) => one(
          '''
        INSERT INTO benefits (household_id, card_id, name, category,
          value_cents, cadence, anchor, enrollment_required, last_call_only)
        VALUES (@h::uuid, @c::uuid, 'Own credit', 'dining', 1000, 'monthly',
          'calendar', false, @last)
        RETURNING id::text
        ''',
          {'h': household, 'c': card, 'last': lastCall},
        );
        final lastCall = await benefit(lastCall: true);
        await benefit(lastCall: false);

        await migrate(db, Directory('migrations'));

        final rows = await db.execute(
          'SELECT user_id::text, benefit_id::text FROM member_last_calls',
        );
        expect(
          {for (final r in rows) (r[0], r[1])},
          {(ann, lastCall), (bob, lastCall)},
        );
        // Once every member has it, the household's column is gone (#362).
        final column = await db.execute(
          "SELECT 1 FROM information_schema.columns WHERE table_schema = "
          "'last_call_migration' AND table_name = 'benefits' "
          "AND column_name = 'last_call_only'",
        );
        expect(column, isEmpty);
      },
    );
  }, skip: url == null ? 'DATABASE_URL is not set' : null);
}
