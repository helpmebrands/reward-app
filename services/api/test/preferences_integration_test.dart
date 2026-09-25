import 'dart:io';

import 'package:domain/domain.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'support/api.dart';
import 'support/database.dart';
import 'support/tokens.dart';

/// Each member's notification preferences and mutes, against
/// `DATABASE_URL` in the suite's own schema; skipped without one.
void main() {
  final url = Platform.environment['DATABASE_URL'];

  group(
    'member preferences against DATABASE_URL',
    () {
      late Connection db;
      late TestApi api;

      setUpAll(() async {
        db = await openMigratedSchema(url!, 'preferences');
        api = TestApi(await TestKey.generate(), db);
      });

      tearDownAll(() => dropSchema(db, 'preferences'));

      setUp(() => db.execute('TRUNCATE users, households CASCADE'));

      Map<String, dynamic> json(Reply r) => r.body! as Map<String, dynamic>;

      Future<MemberPreferences> prefs(String uid) async {
        final reply = await api.as(uid).get('/v1/me/preferences');
        expect(reply.status, 200, reason: '${reply.body}');
        return memberPreferencesFromJson(json(reply));
      }

      /// Ann's household with a Gold, and Bob in it with [role].
      Future<({String card, String benefit})> shared(String role) async {
        final added = json(
          await api.as('ann').post('/v1/cards', {
            'templateId': 'amex-gold',
            'anniversaryOn': '2024-05-01',
          }),
        );
        final code =
            json(
                  await api.as('ann').post('/v1/household/invites', {
                    'role': role,
                  }),
                )['code']
                as String;
        await api.as('bob').post('/v1/invites/$code/accept');
        return (
          card: (added['card'] as Map)['id'] as String,
          benefit: ((added['benefits'] as List).first as Map)['id'] as String,
        );
      }

      // @lat: [[api-tests#Member preferences#A new member reads the defaults]]
      test('a new member reads the default preferences', () async {
        expect(
          memberPreferencesToJson(await prefs('ann')),
          memberPreferencesToJson(defaultMemberPreferences),
        );
      });

      // @lat: [[api-tests#Member preferences#Preferences are the member's own]]
      test('preferences and mutes are per member', () async {
        final ids = await shared('edit');
        final put = await api.as('ann').put('/v1/me/preferences', {
          'enabled': true,
          'timeOfDay': '07:30',
          'minValueCents': 500,
          'annualFeeReminder': false,
          'enrollmentReminder': true,
        });
        expect(put.status, 200, reason: '${put.body}');
        expect(
          (await api.as('ann').put('/v1/me/mutes/cards/${ids.card}', {}))
              .status,
          204,
        );
        expect(
          (await api.as('ann').put('/v1/me/mutes/benefits/${ids.benefit}', {}))
              .status,
          204,
        );

        final ann = await prefs('ann');
        expect(ann.enabled, isTrue);
        expect(ann.timeOfDay, '07:30');
        expect(ann.mutedCardIds, {ids.card});
        expect(ann.mutedBenefitIds, {ids.benefit});
        final bob = await prefs('bob');
        expect(
          memberPreferencesToJson(bob),
          memberPreferencesToJson(defaultMemberPreferences),
        );

        expect(
          (await api.as('ann').delete('/v1/me/mutes/cards/${ids.card}')).status,
          204,
        );
        expect((await prefs('ann')).mutedCardIds, isEmpty);
      });

      // @lat: [[api-tests#Member preferences#A reader can mute]]
      test('a reader can set preferences and mute', () async {
        final ids = await shared('read');
        expect(
          (await api.as('bob').put('/v1/me/mutes/cards/${ids.card}', {}))
              .status,
          204,
        );
        expect((await prefs('bob')).mutedCardIds, {ids.card});
        expect(
          (await api.as('bob').put('/v1/me/preferences', {
            'enabled': true,
            'timeOfDay': '09:00',
            'minValueCents': 100,
            'annualFeeReminder': true,
            'enrollmentReminder': true,
          })).status,
          200,
        );
      });

      // @lat: [[api-tests#Member preferences#Muting another household's card is not found]]
      test('muting outside the household is 404', () async {
        final ids = await shared('edit');
        final outsider = api.as('cat');
        expect(
          (await outsider.put('/v1/me/mutes/cards/${ids.card}', {})).status,
          404,
        );
        expect(
          (await outsider.put(
            '/v1/me/mutes/benefits/${ids.benefit}',
            {},
          )).status,
          404,
        );
        expect(
          (await outsider.put(
            '/v1/me/mutes/cards/00000000-0000-4000-8000-000000000000',
            {},
          )).status,
          404,
        );
      });

      // @lat: [[api-tests#Member preferences#Preferences are validated]]
      test('a bad time or floor is 400', () async {
        for (final (field, value) in [
          ('timeOfDay', '25:00'),
          ('minValueCents', -1),
          ('enabled', 'yes'),
        ]) {
          final reply = await api.as('ann').put('/v1/me/preferences', {
            ...memberPreferencesToJson(defaultMemberPreferences),
            field: value,
          });
          expect(reply.status, 400, reason: field);
          expect(json(reply)['field'], field);
        }
      });
    },
    skip: url == null ? 'DATABASE_URL is not set' : false,
  );
}
