/// The migration runner: numbered SQL files in `migrations/`, applied once
/// each in version order and recorded in `schema_migrations`. Documented in
/// `lat.md/api/api-architecture.md#Migrations`.
library;

import 'dart:io';

import 'package:postgres/postgres.dart';

/// One file in the migrations directory: `NNNN_name.sql`.
class Migration {
  const Migration({
    required this.version,
    required this.name,
    required this.file,
  });

  final int version;
  final String name;
  final File file;
}

final _fileName = RegExp(r'^(\d+)_([a-z0-9_]+)\.sql$');

/// The `.sql` files in [dir] in ascending version order. Other files are
/// ignored; a `.sql` file that does not match `NNNN_name.sql`, or a version
/// claimed twice, is a [FormatException] because silently skipping either
/// would leave a database that looks migrated and is not.
List<Migration> listMigrations(Directory dir) {
  final migrations = <Migration>[];
  for (final entry in dir.listSync()) {
    final base = entry.uri.pathSegments.last;
    if (entry is! File || !base.endsWith('.sql')) continue;
    final match = _fileName.firstMatch(base);
    if (match == null) {
      throw FormatException('migration file name must be NNNN_name.sql', base);
    }
    migrations.add(
      Migration(version: int.parse(match[1]!), name: match[2]!, file: entry),
    );
  }
  migrations.sort((a, b) => a.version.compareTo(b.version));
  for (var i = 1; i < migrations.length; i++) {
    if (migrations[i].version == migrations[i - 1].version) {
      throw FormatException(
        'two migrations claim version ${migrations[i].version}',
      );
    }
  }
  return migrations;
}

/// Applies every migration in [dir] that `schema_migrations` does not yet
/// record, each in its own transaction with its row, and returns the ones
/// applied. A second run over the same files returns an empty list.
Future<List<Migration>> migrate(Connection db, Directory dir) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS schema_migrations (
      version    integer     PRIMARY KEY,
      name       text        NOT NULL,
      applied_at timestamptz NOT NULL DEFAULT now()
    )
  ''');
  final done = (await db.execute(
    'SELECT version FROM schema_migrations',
  )).map((row) => row[0] as int).toSet();

  final applied = <Migration>[];
  for (final migration in listMigrations(dir)) {
    if (done.contains(migration.version)) continue;
    final sql = await migration.file.readAsString();
    await db.runTx((tx) async {
      // Simple query mode: a migration file holds several statements, which
      // the extended protocol refuses.
      await tx.execute(sql, queryMode: QueryMode.simple);
      await tx.execute(
        Sql.named(
          'INSERT INTO schema_migrations (version, name) '
          'VALUES (@version, @name)',
        ),
        parameters: {'version': migration.version, 'name': migration.name},
      );
    });
    applied.add(migration);
  }
  return applied;
}
