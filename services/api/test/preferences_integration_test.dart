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

  group('member preferences against DATABASE_URL', () {
    late Connection db;
    late TestApi api;

    setUpAll(() async {
      db = await openMigratedSchema(url!, 'preferences');
      api = TestApi(await TestKey.generate(), db);
    });

    tearDownAll(() => dropSchema(db, 'preferences'));

    setUp(() => db.execute('TRUNCATE users CASCADE'));

    Map<String, dynamic> json(Reply r) => r.body! as Map<String, dynamic>;

    Future<MemberPreferences> prefs(String uid) async {
      final reply = await api.as(uid).get('/v1/me/preferences');
      expect(reply.status, 200, reason: '${reply.body}');
      return memberPreferencesFromJson(json(reply));
    }

    /// Ann's Gold, which she shares with Bob at [access].
    Future<({String card, String benefit})> shared(String access) async {
      final added = json(
        await api.as('ann').post('/v1/cards', {
          'templateId': 'amex-gold',
          'anniversaryOn': '2024-05-01',
        }),
      );
      final code =
          json(
                await api.as('ann').post('/v1/invites', {
                  'access': access,
                  'allCards': true,
                }),
              )['code']
              as String;
      final accepted = await api.as('bob').post('/v1/invites/$code/accept');
      expect(accepted.status, 200, reason: '${accepted.body}');
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
      final ids = await shared('record');
      final put = await api.as('ann').put('/v1/me/preferences', {
        'enabled': true,
        'timeOfDay': '07:30',
        'minValueCents': 500,
        'annualFeeReminder': false,
        'enrollmentReminder': true,
      });
      expect(put.status, 200, reason: '${put.body}');
      expect(
        (await api.as('ann').put('/v1/me/mutes/cards/${ids.card}', {})).status,
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

    // @lat: [[api-tests#Member preferences#A viewer can mute]]
    test('a viewer can set preferences and mute', () async {
      final ids = await shared('view');
      expect(
        (await api.as('bob').put('/v1/me/mutes/cards/${ids.card}', {})).status,
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

    // @lat: [[api-tests#Member preferences#Muting a card nobody shared is not found]]
    test('muting a card nobody shared is 404', () async {
      final ids = await shared('record');
      final outsider = api.as('cat');
      expect(
        (await outsider.put('/v1/me/mutes/cards/${ids.card}', {})).status,
        404,
      );
      expect(
        (await outsider.put('/v1/me/mutes/benefits/${ids.benefit}', {})).status,
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

    Future<Reply> level(String uid, String benefit, Object? level) =>
        api.as(uid).put('/v1/me/benefits/$benefit/level', {'level': level});

    // @lat: [[api-tests#Member preferences#A viewer sets a credit's notification level]]
    test('each level leaves the flags the rule says, for a viewer', () async {
      final ids = await shared('view');
      for (final (name, muted, lastCall) in [
        ('lastChance', <String>{}, {ids.benefit}),
        ('silenced', {ids.benefit}, {ids.benefit}),
        ('periodically', <String>{}, <String>{}),
        ('silenced', {ids.benefit}, <String>{}),
        ('lastChance', <String>{}, {ids.benefit}),
      ]) {
        final reply = await level('bob', ids.benefit, name);
        expect(reply.status, 200, reason: '$name ${reply.body}');
        final answered = memberPreferencesFromJson(json(reply));
        final read = await prefs('bob');
        for (final p in [answered, read]) {
          expect(p.mutedBenefitIds, muted, reason: name);
          expect(p.lastCallBenefitIds, lastCall, reason: name);
        }
      }
    });

    // @lat: [[api-tests#Member preferences#One member's level leaves the other's alone]]
    test('last chance for one member changes nothing for another', () async {
      final ids = await shared('record');
      expect((await level('ann', ids.benefit, 'lastChance')).status, 200);
      expect((await prefs('ann')).lastCallBenefitIds, {ids.benefit});
      expect(
        memberPreferencesToJson(await prefs('bob')),
        memberPreferencesToJson(defaultMemberPreferences),
      );
    });

    // @lat: [[api-tests#Member preferences#A bad level or an unshared credit is refused]]
    test('an unknown level is 400; an unshared credit is 404', () async {
      final ids = await shared('record');
      for (final bad in ['loud', null, 3]) {
        final reply = await level('ann', ids.benefit, bad);
        expect(reply.status, 400, reason: '$bad');
        expect(json(reply)['field'], 'level');
      }
      expect((await level('cat', ids.benefit, 'silenced')).status, 404);
      expect(
        (await level(
          'ann',
          '00000000-0000-4000-8000-000000000000',
          'silenced',
        )).status,
        404,
      );
      expect((await level('ann', 'not-a-uuid', 'silenced')).status, 404);
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
  }, skip: url == null ? 'DATABASE_URL is not set' : false);
}
