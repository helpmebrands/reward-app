import 'dart:io';

import 'package:api/migrate.dart';
import 'package:postgres/postgres.dart';

/// Applies `services/api/migrations/` to the database at `DATABASE_URL`:
/// `dart run bin/migrate.dart` from `services/api`. Exits 2 without a URL.
Future<void> main() async {
  final url = Platform.environment['DATABASE_URL'];
  if (url == null || url.isEmpty) {
    stderr.writeln('DATABASE_URL is not set');
    exit(2);
  }
  final dir = Directory.fromUri(Platform.script.resolve('../migrations/'));
  final db = await Connection.openFromUrl(url);
  try {
    final applied = await migrate(db, dir);
    if (applied.isEmpty) {
      stdout.writeln('schema is current; nothing to apply');
    }
    for (final m in applied) {
      stdout.writeln('applied ${m.version} ${m.name}');
    }
  } finally {
    await db.close();
  }
}
