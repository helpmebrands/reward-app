import 'dart:io';

import 'package:api/migrate.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

/// Runs only when `DATABASE_URL` points at a PostgreSQL the test may reset:
/// the `api` CI job's service container, or the local docker compose one.
void main() {
  final url = Platform.environment['DATABASE_URL'];

  group('migrations against DATABASE_URL', () {
    late Connection db;
    late Directory fixtures;

    // Everything happens in its own schema, so this suite can drop
    // schema_migrations freely while the device suite uses the migrated
    // public schema in parallel.
    setUp(() async {
      db = await Connection.openFromUrl(url!);
      await db.execute('DROP SCHEMA IF EXISTS migrate_test CASCADE');
      await db.execute('CREATE SCHEMA migrate_test');
      await db.execute('SET search_path TO migrate_test');
      fixtures = await Directory.systemTemp.createTemp('migrations-');
    });

    tearDown(() async {
      await db.execute('DROP SCHEMA migrate_test CASCADE');
      await db.close();
      await fixtures.delete(recursive: true);
    });

    Future<List<int>> recorded() async {
      final rows = await db.execute(
        'SELECT version FROM schema_migrations ORDER BY version',
      );
      return rows.map((r) => r[0] as int).toList();
    }

    // @lat: [[api-tests#Migrations#Real migrations apply from DATABASE_URL and land in schema_migrations]]
    test('applies services/api/migrations and records each version', () async {
      final applied = await migrate(db, Directory('migrations'));

      expect(applied, isNotEmpty);
      expect(applied.first.version, 1);
      expect(await recorded(), applied.map((m) => m.version).toList());
      final rows = await db.execute(
        'SELECT name, applied_at FROM schema_migrations WHERE version = 1',
      );
      expect(rows.single[0], applied.first.name);
      expect(rows.single[1], isA<DateTime>());
    });

    // @lat: [[api-tests#Migrations#A second run applies nothing]]
    test('a second run over the same files applies nothing', () async {
      File(
        '${fixtures.path}/0001_fixture_a.sql',
      ).writeAsStringSync('CREATE TABLE fixture_a (id int PRIMARY KEY);');
      File('${fixtures.path}/0002_fixture_b.sql').writeAsStringSync(
        'CREATE TABLE fixture_b (id int PRIMARY KEY);\n'
        'INSERT INTO fixture_b VALUES (1);',
      );

      final first = await migrate(db, fixtures);
      final second = await migrate(db, fixtures);

      expect(first.map((m) => m.version), [1, 2]);
      expect(second, isEmpty);
      expect(await recorded(), [1, 2]);
      final b = await db.execute('SELECT count(*) FROM fixture_b');
      expect(b.single[0], 1);
    });

    // @lat: [[api-tests#Migrations#A failing migration rolls back and is not recorded]]
    test('a failing migration rolls back and is not recorded', () async {
      File(
        '${fixtures.path}/0001_fixture_a.sql',
      ).writeAsStringSync('CREATE TABLE fixture_a (id int PRIMARY KEY);');
      File('${fixtures.path}/0002_broken.sql').writeAsStringSync(
        'CREATE TABLE fixture_c (id int PRIMARY KEY);\n'
        'SELECT * FROM no_such_table;',
      );

      await expectLater(migrate(db, fixtures), throwsA(isA<ServerException>()));

      expect(await recorded(), [1]);
      final tables = await db.execute(
        "SELECT to_regclass('fixture_c') IS NOT NULL",
      );
      expect(tables.single[0], isFalse);
    });
  }, skip: url == null ? 'DATABASE_URL is not set' : null);
}
