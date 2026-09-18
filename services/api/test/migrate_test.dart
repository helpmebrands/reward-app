import 'dart:io';

import 'package:api/migrate.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('migrations-');
  });

  tearDown(() => dir.delete(recursive: true));

  // @lat: [[api-tests#Migrations#Migration files are ordered by version]]
  test('lists .sql files by numeric version, ignoring other files', () async {
    File('${dir.path}/0010_ten.sql').writeAsStringSync('select 10;');
    File('${dir.path}/0002_two.sql').writeAsStringSync('select 2;');
    File('${dir.path}/README.md').writeAsStringSync('not a migration');

    final migrations = listMigrations(dir);

    expect(migrations.map((m) => m.version), [2, 10]);
    expect(migrations.map((m) => m.name), ['two', 'ten']);
    expect(migrations.last.file.path, endsWith('0010_ten.sql'));
  });

  // @lat: [[api-tests#Migrations#Malformed and duplicate file names are rejected]]
  test('rejects a .sql file without a version prefix', () {
    File('${dir.path}/create_things.sql').writeAsStringSync('select 1;');
    expect(() => listMigrations(dir), throwsFormatException);
  });

  test('rejects two files claiming the same version', () {
    File('${dir.path}/0001_a.sql').writeAsStringSync('select 1;');
    File('${dir.path}/0001_b.sql').writeAsStringSync('select 1;');
    expect(() => listMigrations(dir), throwsFormatException);
  });
}
