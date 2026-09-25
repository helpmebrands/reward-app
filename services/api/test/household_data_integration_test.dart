import 'dart:io';

import 'package:api/catalog.dart';
import 'package:domain/domain.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'support/api.dart';
import 'support/database.dart';
import 'support/tokens.dart';

/// A household's cards, credits and claims through the handler, against
/// `DATABASE_URL` in the suite's own schema; skipped without one.
void main() {
  final url = Platform.environment['DATABASE_URL'];

  group(
    'household data against DATABASE_URL',
    () {
      late Connection db;
      late TestApi api;

      setUpAll(() async {
        db = await openMigratedSchema(url!, 'household_data');
        api = TestApi(await TestKey.generate(), db);
      });

      tearDownAll(() => dropSchema(db, 'household_data'));

      setUp(() => db.execute('TRUNCATE users, households CASCADE'));

      Map<String, dynamic> json(Reply r) => r.body! as Map<String, dynamic>;
      List<Map<String, dynamic>> list(Object? l) =>
          (l! as List).cast<Map<String, dynamic>>();

      Future<Map<String, dynamic>> addCard(
        String uid,
        Map<String, Object?> body,
      ) async {
        final reply = await api.as(uid).post('/v1/cards', body);
        expect(reply.status, 201, reason: '${reply.body}');
        return json(reply);
      }

      Future<AppData> data(String uid) async {
        final reply = await api.as(uid).get('/v1/household/data');
        expect(reply.status, 200, reason: '${reply.body}');
        return appDataFromJson(json(reply));
      }

      const platinum = {
        'templateId': 'amex-gold',
        'anniversaryOn': '2024-05-01',
      };

      // @lat: [[api-tests#Household data#A template card's benefits are the resolved version]]
      test(
        'a card from a template gets the resolved template credits',
        () async {
          final added = await addCard('ann', platinum);
          final card = cardFromJson(added['card'] as Map<String, dynamic>);
          expect(card.templateId, 'amex-gold');
          expect(maintainedBy(card), MaintainedBy.system);
          expect(card.label, isNull);

          final household = await data('ann');
          final template = findTemplate('amex-gold')!;
          final versions = await publishedVersions(db, templateId: 'amex-gold');
          final today = todayIso();
          final served = household.benefits
              .where((b) => b.cardId == card.id)
              .toList();
          expect(
            served.map((b) => b.templateBenefitId).toSet(),
            template.benefits.map((c) => c.id).toSet(),
          );
          for (final benefit in served) {
            final expected = resolveLinkedBenefit(
              versions,
              LinkedBenefitState(
                id: benefit.id,
                cardId: card.id,
                templateBenefitId: benefit.templateBenefitId!,
                createdAt: benefit.createdAt,
                updatedAt: benefit.updatedAt,
              ),
              card,
              today,
            )!;
            expect(benefitToJson(benefit), benefitToJson(expected));
          }
          final servedCard = household.cards.single;
          expect(servedCard.issuer, template.issuer);
          expect(servedCard.annualFeeCents, template.annualFeeCents);
        },
      );

      // @lat: [[api-tests#Household data#Duplicate products get numbered labels]]
      test(
        'a second card of a product is labelled (1); a taken label is 409',
        () async {
          await addCard('ann', platinum);
          final second = await addCard('ann', platinum);
          expect((second['card'] as Map)['label'], 'American Express Gold (1)');
          final taken = await api.as('ann').post('/v1/cards', {
            ...platinum,
            'label': 'american express gold (1)',
          });
          expect(taken.status, 409);
          expect(json(taken)['error'], 'label taken');
          final renamed = await api.as('ann').post('/v1/cards', {
            ...platinum,
            'label': 'Travel',
          });
          expect(renamed.status, 201);
        },
      );

      // @lat: [[api-tests#Household data#A retried claim is stored once]]
      test('a claim retried with its key is stored once', () async {
        final added = await addCard('ann', platinum);
        final benefit = list(added['benefits']).first;
        final claim = {
          'benefitId': benefit['id'],
          'cycleKey': '2026-09-01',
          'amountCents': 500,
          'claimedAt': '2026-09-10T12:00:00.000Z',
        };
        final first = await api
            .as('ann')
            .send(
              'POST',
              '/v1/claims',
              uid: 'ann',
              body: claim,
              headers: {'idempotency-key': 'k-1'},
            );
        expect(first.status, 201, reason: '${first.body}');
        final retried = await api
            .as('ann')
            .send(
              'POST',
              '/v1/claims',
              uid: 'ann',
              body: claim,
              headers: {'idempotency-key': 'k-1'},
            );
        expect(retried.status, 201);
        expect(json(retried)['id'], json(first)['id']);
        expect((await data('ann')).claims, hasLength(1));

        final changed = await api
            .as('ann')
            .send(
              'POST',
              '/v1/claims',
              uid: 'ann',
              body: {...claim, 'amountCents': 600},
              headers: {'idempotency-key': 'k-1'},
            );
        expect(changed.status, 409);
        final unkeyed = await api.as('ann').post('/v1/claims', claim);
        expect(unkeyed.status, 400);

        final removed = await api
            .as('ann')
            .delete('/v1/claims/${json(first)['id']}');
        expect(removed.status, 204);
        expect((await data('ann')).claims, isEmpty);
      });

      // @lat: [[api-tests#Household data#System-maintained terms cannot be edited]]
      test(
        'a linked benefit’s terms are 409; a user card’s edit freely',
        () async {
          final linked = await addCard('ann', platinum);
          final benefit = list(linked['benefits']).first;
          final edit = await api.as('ann').put(
            '/v1/benefits/${benefit['id']}',
            {...benefit, 'valueCents': 1},
          );
          expect(edit.status, 409);
          expect(json(edit), {'error': 'system maintained'});
          final cardTerms = await api.as('ann').patch(
            '/v1/cards/${(linked['card'] as Map)['id']}',
            {'annualFeeCents': 1},
          );
          expect(cardTerms.status, 409);
          final addCredit = await api
              .as('ann')
              .post('/v1/cards/${(linked['card'] as Map)['id']}/benefits', {});
          expect(addCredit.status, 409);

          // Household state is the household's to change on any card.
          final enrolled = await api.as('ann').put(
            '/v1/benefits/${benefit['id']}/state',
            {'enrolledAt': '2026-09-01T00:00:00.000Z'},
          );
          expect(enrolled.status, 200, reason: '${enrolled.body}');
          expect(json(enrolled)['enrolledAt'], '2026-09-01T00:00:00.000Z');

          final own = await addCard('ann', {
            'issuer': 'Chase',
            'product': 'Freedom',
            'network': 'visa',
            'kind': 'personal',
            'annualFeeCents': 0,
            'anniversaryOn': '2023-01-15',
          });
          final ownCard = own['card'] as Map<String, dynamic>;
          expect(ownCard.containsKey('templateId'), isFalse);
          final credit = await api
              .as('ann')
              .post('/v1/cards/${ownCard['id']}/benefits', {
                'name': 'Dining',
                'category': 'dining',
                'valueCents': 1000,
                'cadence': 'monthly',
                'anchor': 'calendar',
              });
          expect(credit.status, 201, reason: '${credit.body}');
          final changed = await api.as('ann').put(
            '/v1/benefits/${json(credit)['id']}',
            {...json(credit), 'valueCents': 1500},
          );
          expect(changed.status, 200, reason: '${changed.body}');
          expect(json(changed)['valueCents'], 1500);
          final fee = await api.as('ann').patch('/v1/cards/${ownCard['id']}', {
            'annualFeeCents': 9500,
            'label': 'Everyday',
          });
          expect(fee.status, 200, reason: '${fee.body}');
          expect(json(fee)['annualFeeCents'], 9500);
        },
      );

      // @lat: [[api-tests#Household data#Readers cannot write the household's data]]
      test('a reader’s writes are 403 and their reads succeed', () async {
        final added = await addCard('ann', platinum);
        final code =
            json(
                  await api.as('ann').post('/v1/household/invites', {
                    'role': 'read',
                  }),
                )['code']
                as String;
        await api.as('rex').post('/v1/invites/$code/accept');
        final cardId = (added['card'] as Map)['id'];
        final benefitId = list(added['benefits']).first['id'];
        final writes = [
          await api.as('rex').post('/v1/cards', platinum),
          await api.as('rex').patch('/v1/cards/$cardId', {'label': 'x'}),
          await api.as('rex').delete('/v1/cards/$cardId'),
          await api.as('rex').put('/v1/benefits/$benefitId/state', {}),
          await api
              .as('rex')
              .send(
                'POST',
                '/v1/claims',
                uid: 'rex',
                body: {'benefitId': benefitId},
                headers: {'idempotency-key': 'r'},
              ),
        ];
        expect(writes.map((r) => r.status), everyElement(403));
        expect((await data('rex')).cards, hasLength(1));
      });

      // @lat: [[api-tests#Household data#Another household's ids are not found]]
      test('ids from another household are 404', () async {
        final added = await addCard('ann', platinum);
        final cardId = (added['card'] as Map)['id'];
        expect(
          (await api.as('bob').patch('/v1/cards/$cardId', {
            'label': 'x',
          })).status,
          404,
        );
        expect((await api.as('bob').delete('/v1/cards/$cardId')).status, 404);
        expect((await data('bob')).cards, isEmpty);
      });

      // @lat: [[api-tests#Household data#Deleting a card takes its credits and claims]]
      test('deleting a card removes its benefits and claims', () async {
        final added = await addCard('ann', platinum);
        final benefitId = list(added['benefits']).first['id'];
        await api
            .as('ann')
            .send(
              'POST',
              '/v1/claims',
              uid: 'ann',
              body: {
                'benefitId': benefitId,
                'cycleKey': '2026-09-01',
                'amountCents': 100,
              },
              headers: {'idempotency-key': 'd-1'},
            );
        final cardId = (added['card'] as Map)['id'];
        expect((await api.as('ann').delete('/v1/cards/$cardId')).status, 204);
        final after = await data('ann');
        expect(after.cards, isEmpty);
        expect(after.benefits, isEmpty);
        expect(after.claims, isEmpty);
      });
    },
    skip: url == null ? 'DATABASE_URL is not set' : false,
  );
}
