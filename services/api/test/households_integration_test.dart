import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'support/api.dart';
import 'support/database.dart';
import 'support/tokens.dart';

/// Households, memberships and invites through the handler, against
/// `DATABASE_URL` in the suite's own schema; skipped without one.
void main() {
  final url = Platform.environment['DATABASE_URL'];

  group(
    'households against DATABASE_URL',
    () {
      late Connection db;
      late TestApi api;

      setUpAll(() async {
        db = await openMigratedSchema(url!, 'households');
        api = TestApi(await TestKey.generate(), db);
      });

      tearDownAll(() => dropSchema(db, 'households'));

      setUp(() => db.execute('TRUNCATE users, households CASCADE'));

      Map<String, dynamic> json(Reply r) => r.body! as Map<String, dynamic>;

      Future<String> invite(String uid, String role) async {
        final reply = await api.as(uid).post('/v1/household/invites', {
          'role': role,
        });
        expect(reply.status, 201, reason: '${reply.body}');
        return json(reply)['code'] as String;
      }

      List<Map<String, dynamic>> members(Reply r) =>
          (json(r)['members'] as List).cast<Map<String, dynamic>>();

      // @lat: [[api-tests#Households#A new user owns a new empty household]]
      test('a new user owns a household of one', () async {
        final reply = await api.as('ann').get('/v1/household');
        expect(reply.status, 200);
        expect(json(reply)['role'], 'owner');
        expect(members(reply), hasLength(1));
        expect(members(reply).single['role'], 'owner');
        expect(members(reply).single['email'], 'ann@x.test');
        // The second call finds the same household rather than making one.
        final again = await api.as('ann').get('/v1/household');
        expect(json(again)['id'], json(reply)['id']);
      });

      // @lat: [[api-tests#Households#An invite joins its household once, for seven days]]
      test('a code joins with its role once, and not after 7 days', () async {
        final code = await invite('ann', 'edit');
        final created = await api.as('ann').post('/v1/household/invites', {
          'role': 'read',
        });
        expect(
          json(created)['link'],
          endsWith('/invite/${json(created)['code']}'),
        );
        expect(json(created)['role'], 'read');

        final joined = await api.as('bob').post('/v1/invites/$code/accept');
        expect(joined.status, 200);
        final household = await api.as('ann').get('/v1/household');
        expect(json(joined)['id'], json(household)['id']);
        expect(
          {for (final m in members(household)) m['email']: m['role']},
          {'ann@x.test': 'owner', 'bob@x.test': 'editor'},
        );

        final reused = await api.as('cat').post('/v1/invites/$code/accept');
        expect(reused.status, 410);

        final old = await invite('ann', 'read');
        await db.execute(
          Sql.named(
            "UPDATE invites SET expires_at = now() - interval '1 second' "
            'WHERE code = @c',
          ),
          parameters: {'c': old},
        );
        expect(
          (await api.as('cat').post('/v1/invites/$old/accept')).status,
          410,
        );
        expect(
          (await api.as('cat').post('/v1/invites/NOSUCH/accept')).status,
          404,
        );
      });

      // @lat: [[api-tests#Households#Readers cannot write]]
      test('a reader’s writes to the household get 403', () async {
        await api
            .as('rex')
            .post('/v1/invites/${await invite('ann', 'read')}/accept');
        final annId = await api.as('ann').id();
        expect(
          (await api.as('rex').post('/v1/household/invites', {
            'role': 'read',
          })).status,
          403,
        );
        expect(
          (await api.as('rex').delete('/v1/household/members/$annId')).status,
          403,
        );
        // Editors cannot manage members either: that is the owner's.
        await api
            .as('eve')
            .post('/v1/invites/${await invite('ann', 'edit')}/accept');
        expect(
          (await api.as('eve').post('/v1/household/invites', {
            'role': 'read',
          })).status,
          403,
        );
      });

      // @lat: [[api-tests#Households#Leaving a household that holds cards needs confirmation]]
      test('accepting while holding cards needs confirmLeave', () async {
        final code = await invite('ann', 'edit');
        final bob = await api.as('bob').get('/v1/household');
        await db.execute(
          Sql.named('INSERT INTO cards (household_id) VALUES (@h::uuid)'),
          parameters: {'h': json(bob)['id']},
        );
        final refused = await api.as('bob').post('/v1/invites/$code/accept');
        expect(refused.status, 409);
        expect(json(refused)['error'], 'household holds cards');

        final joined = await api.as('bob').post('/v1/invites/$code/accept', {
          'confirmLeave': true,
        });
        expect(joined.status, 200);
        // Bob's old household, and its card, are gone with him gone.
        final left = await db.execute(
          Sql.named('SELECT count(*) FROM households WHERE id = @h::uuid'),
          parameters: {'h': json(bob)['id']},
        );
        expect(left.single[0], 0);
        final cards = await db.execute('SELECT count(*) FROM cards');
        expect(cards.single[0], 0);
      });

      // @lat: [[api-tests#Households#An owner with members cannot leave]]
      test('an owner cannot leave while others remain', () async {
        await api
            .as('bob')
            .post('/v1/invites/${await invite('ann', 'edit')}/accept');
        final elsewhere = await invite('cat', 'edit');
        final refused = await api
            .as('ann')
            .post('/v1/invites/$elsewhere/accept');
        expect(refused.status, 409);
        expect(json(refused)['error'], 'owner has members');
      });

      // @lat: [[api-tests#Households#A removed member loses access at once]]
      test(
        'a removed member is out on their next call, with nothing',
        () async {
          await api
              .as('bob')
              .post('/v1/invites/${await invite('ann', 'edit')}/accept');
          final ann = json(await api.as('ann').get('/v1/household'));
          final bobId = await api.as('bob').id();

          final removed = await api
              .as('ann')
              .delete('/v1/household/members/$bobId');
          expect(removed.status, 204);
          expect(
            (await api.as('ann').delete('/v1/household/members/$bobId')).status,
            404,
          );
          final bobNow = await api.as('bob').get('/v1/household');
          expect(json(bobNow)['id'], isNot(ann['id']));
          expect(json(bobNow)['role'], 'owner');
          expect(members(bobNow), hasLength(1));
          expect(
            members(await api.as('ann').get('/v1/household')),
            hasLength(1),
          );
        },
      );

      // @lat: [[api-tests#Households#An invite names a role]]
      test('an invite needs a role of read or edit', () async {
        final reply = await api.as('ann').post('/v1/household/invites', {
          'role': 'admin',
        });
        expect(reply.status, 400);
        expect(json(reply), {'error': 'invalid', 'field': 'role'});
      });
    },
    skip: url == null ? 'DATABASE_URL is not set' : false,
  );
}
