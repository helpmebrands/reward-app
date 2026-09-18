import 'dart:convert';
import 'dart:io';

import 'package:api/api.dart';
import 'package:api/migrate.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// Drives the device routes through the handler against the migrated
/// `public` schema at `DATABASE_URL`; skipped without one.
void main() {
  final url = Platform.environment['DATABASE_URL'];

  group(
    'device routes against DATABASE_URL',
    () {
      late Connection db;
      late Handler handler;

      setUpAll(() async {
        db = await Connection.openFromUrl(url!);
        await migrate(db, Directory('migrations'));
        handler = buildHandler(db: db);
      });

      tearDownAll(() => db.close());

      setUp(() => db.execute('TRUNCATE devices'));

      Future<Response> post(Map<String, Object?> body) => handler(
        Request(
          'POST',
          Uri.parse('http://localhost/v1/devices'),
          body: jsonEncode(body),
          headers: {'content-type': 'application/json'},
        ),
      );

      Future<Map<String, dynamic>> json(Response r) async =>
          jsonDecode(await r.readAsString()) as Map<String, dynamic>;

      const body = {
        'token': 'fcm-token-1',
        'installationId': 'inst-1',
        'platform': 'ios',
        'timezone': 'Europe/London',
      };

      // @lat: [[api-tests#Devices#The devices migration creates the table]]
      test('the runner created the devices table', () async {
        final rows = await db.execute(
          "SELECT to_regclass('public.devices') IS NOT NULL",
        );
        expect(rows.single[0], isTrue);
      });

      // @lat: [[api-tests#Devices#Registering the same token twice upserts]]
      test(
        'POST twice with one token keeps one row with the latest fields',
        () async {
          final first = await post(body);
          expect(first.statusCode, 200);
          expect(await json(first), body);

          final second = await post({
            ...body,
            'installationId': 'inst-2',
            'platform': 'android',
            'timezone': 'America/New_York',
          });
          expect(second.statusCode, 200);
          expect(await json(second), {
            ...body,
            'installationId': 'inst-2',
            'platform': 'android',
            'timezone': 'America/New_York',
          });

          final rows = await db.execute(
            'SELECT installation_id, platform, timezone, '
            'updated_at >= registered_at FROM devices',
          );
          expect(rows.length, 1);
          expect(rows.single.toList(), [
            'inst-2',
            'android',
            'America/New_York',
            true,
          ]);
        },
      );

      // @lat: [[api-tests#Devices#Missing or unknown timezone answers 400]]
      test('POST without a timezone answers 400 naming the field', () async {
        final r = await post(Map.of(body)..remove('timezone'));
        expect(r.statusCode, 400);
        expect(await json(r), {'error': 'invalid', 'field': 'timezone'});
      });

      test('POST with a timezone Postgres does not know answers 400', () async {
        final r = await post({...body, 'timezone': 'Mars/Olympus_Mons'});
        expect(r.statusCode, 400);
        expect(await json(r), {'error': 'invalid', 'field': 'timezone'});
        final rows = await db.execute('SELECT count(*) FROM devices');
        expect(rows.single[0], 0);
      });

      test('POST with a body that is not a JSON object answers 400', () async {
        final r = await handler(
          Request(
            'POST',
            Uri.parse('http://localhost/v1/devices'),
            body: '[1, 2]',
            headers: {'content-type': 'application/json'},
          ),
        );
        expect(r.statusCode, 400);
      });

      // @lat: [[api-tests#Devices#Deleting a token removes it and a second delete is 404]]
      test(
        'DELETE removes the token and a second DELETE answers 404',
        () async {
          await post(body);
          final first = await handler(
            Request(
              'DELETE',
              Uri.parse('http://localhost/v1/devices/fcm-token-1'),
            ),
          );
          expect(first.statusCode, 204);
          final rows = await db.execute('SELECT count(*) FROM devices');
          expect(rows.single[0], 0);

          final second = await handler(
            Request(
              'DELETE',
              Uri.parse('http://localhost/v1/devices/fcm-token-1'),
            ),
          );
          expect(second.statusCode, 404);
        },
      );
    },
    skip: url == null ? 'DATABASE_URL is not set' : null,
  );
}
