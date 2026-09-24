/// A private, freshly migrated schema per suite, so suites that write can
/// run in parallel against one `DATABASE_URL` without truncating each
/// other's rows.
library;

import 'dart:io';

import 'package:api/migrate.dart';
import 'package:postgres/postgres.dart';

/// Opens [url], recreates [schema], points the connection's `search_path`
/// at it and applies `migrations/` there. Drop it with [dropSchema].
Future<Connection> openMigratedSchema(String url, String schema) async {
  final db = await Connection.openFromUrl(url);
  await db.execute('DROP SCHEMA IF EXISTS $schema CASCADE');
  await db.execute('CREATE SCHEMA $schema');
  await db.execute('SET search_path TO $schema');
  await migrate(db, Directory('migrations'));
  return db;
}

Future<void> dropSchema(Connection db, String schema) async {
  await db.execute('DROP SCHEMA $schema CASCADE');
  await db.close();
}
