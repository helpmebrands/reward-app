import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'support/api.dart';
import 'support/database.dart';
import 'support/tokens.dart';

/// Drives the device routes through the handler, signed in, against
/// `DATABASE_URL` in the suite's own schema; skipped without one.
void main() {
  final url = Platform.environment['DATABASE_URL'];

  group('device routes against DATABASE_URL', () {
    late Connection db;
    late TestApi api;

    setUpAll(() async {
      db = await openMigratedSchema(url!, 'devices');
      api = TestApi(await TestKey.generate(), db);
    });

    tearDownAll(() => dropSchema(db, 'devices'));

    setUp(() => db.execute('TRUNCATE users, households CASCADE'));

    const body = {
      'token': 'fcm-token-1',
      'installationId': 'inst-1',
      'platform': 'ios',
      'timezone': 'Europe/London',
    };

    Future<int> devices() async =>
        (await db.execute('SELECT count(*) FROM devices')).single[0] as int;

    // @lat: [[api-tests#Devices#The devices migration creates the table]]
    test('the runner created the devices table', () async {
      final rows = await db.execute(
        "SELECT to_regclass('devices') IS NOT NULL",
      );
      expect(rows.single[0], isTrue);
    });

    // @lat: [[api-tests#Devices#Registering the same token twice upserts]]
    test(
      'POST twice with one token keeps one row with the latest fields',
      () async {
        final first = await api.as('ann').post('/v1/devices', body);
        expect(first.status, 200);
        expect(first.body, body);

        final second = {
          ...body,
          'installationId': 'inst-2',
          'platform': 'android',
          'timezone': 'America/New_York',
        };
        final again = await api.as('ann').post('/v1/devices', second);
        expect(again.status, 200);
        expect(again.body, second);

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

    // @lat: [[api-tests#Devices#A device belongs to the member who registered it]]
    test('a device is the caller\'s, and moves to whoever registers it '
        'next', () async {
      await api.as('ann').post('/v1/devices', body);
      final ann = await api.as('ann').id();
      Future<String> owner() async =>
          (await db.execute(
                Sql.named('SELECT user_id::text FROM devices WHERE token = @t'),
                parameters: {'t': 'fcm-token-1'},
              )).single[0]!
              as String;
      expect(await owner(), ann);

      await api.as('bob').post('/v1/devices', body);
      expect(await owner(), await api.as('bob').id());
      expect(await devices(), 1);
    });

    // @lat: [[api-tests#Devices#Missing or unknown timezone answers 400]]
    test('POST without a timezone answers 400 naming the field', () async {
      final r = await api
          .as('ann')
          .post('/v1/devices', Map.of(body)..remove('timezone'));
      expect(r.status, 400);
      expect(r.body, {'error': 'invalid', 'field': 'timezone'});
    });

    test('POST with a timezone Postgres does not know answers 400', () async {
      final r = await api.as('ann').post('/v1/devices', {
        ...body,
        'timezone': 'Mars/Olympus_Mons',
      });
      expect(r.status, 400);
      expect(r.body, {'error': 'invalid', 'field': 'timezone'});
      expect(await devices(), 0);
    });

    test('POST with a body that is not a JSON object answers 400', () async {
      final r = await api.as('ann').post('/v1/devices', [1, 2]);
      expect(r.status, 400);
    });

    // @lat: [[api-tests#Devices#Deleting a token removes it and a second delete is 404]]
    test('DELETE removes the token and a second DELETE answers 404', () async {
      await api.as('ann').post('/v1/devices', body);
      final first = await api.as('ann').delete('/v1/devices/fcm-token-1');
      expect(first.status, 204);
      expect(await devices(), 0);

      final second = await api.as('ann').delete('/v1/devices/fcm-token-1');
      expect(second.status, 404);
    });

    // @lat: [[api-tests#Devices#Another member's token is not found]]
    test('DELETE of another member\'s token is 404 and keeps it', () async {
      await api.as('ann').post('/v1/devices', body);
      final r = await api.as('bob').delete('/v1/devices/fcm-token-1');
      expect(r.status, 404);
      expect(await devices(), 1);
    });
  }, skip: url == null ? 'DATABASE_URL is not set' : false);
}
