import 'dart:io';

import 'package:api/reminder_sender.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'support/api.dart';
import 'support/database.dart';
import 'support/push.dart';
import 'support/tokens.dart';

/// The reminder sender job and the reminder routes, against `DATABASE_URL`
/// in the suite's own schema; skipped without one.
///
/// Ann's household holds one card she maintains, with a $10 monthly credit
/// on the calendar month, so its October cycle's last-day reminder,
/// `2026-10-31|urgent`, fires on 31 October at each member's 09:00. That is
/// 09:00Z in London (back on GMT since the 25th) and 13:00Z in New York
/// (still on EDT until 1 November).
void main() {
  final url = Platform.environment['DATABASE_URL'];

  group('reminder sender against DATABASE_URL', () {
    late Connection db;
    late FakePush push;
    late TestApi api;

    setUpAll(() async {
      db = await openMigratedSchema(url!, 'reminder_sender');
    });

    tearDownAll(() => dropSchema(db, 'reminder_sender'));

    setUp(() async {
      await db.execute('TRUNCATE users, households CASCADE');
      push = FakePush();
      api = TestApi(await TestKey.generate(), db, push: push);
    });

    const lastDay = 'cardvantage-2026-10-31|urgent';
    final londonNine = DateTime.utc(2026, 10, 31, 9);
    final newYorkNine = DateTime.utc(2026, 10, 31, 13);

    Map<String, dynamic> json(Reply r) => r.body! as Map<String, dynamic>;

    Future<void> device(String uid, String token, String zone) async {
      final r = await api.as(uid).post('/v1/devices', {
        'token': token,
        'installationId': 'inst-$token',
        'platform': 'ios',
        'timezone': zone,
      });
      expect(r.status, 200, reason: '${r.body}');
    }

    Future<void> remindersOn(String uid) async {
      final r = await api.as(uid).put('/v1/me/preferences', {
        'enabled': true,
        'timeOfDay': '09:00',
        'minValueCents': 100,
        'annualFeeReminder': true,
        'enrollmentReminder': true,
      });
      expect(r.status, 200, reason: '${r.body}');
    }

    /// Ann's card and credit; returns the card id.
    Future<String> annsCard() async {
      final added = await api.as('ann').post('/v1/cards', {
        'issuer': 'Chase',
        'product': 'Freedom',
        'network': 'visa',
        'kind': 'personal',
        'annualFeeCents': 0,
        'anniversaryOn': '2023-01-15',
      });
      expect(added.status, 201, reason: '${added.body}');
      final card = (json(added)['card'] as Map)['id'] as String;
      final credit = await api.as('ann').post('/v1/cards/$card/benefits', {
        'name': 'Dining',
        'category': 'dining',
        'valueCents': 1000,
        'cadence': 'monthly',
        'anchor': 'calendar',
      });
      expect(credit.status, 201, reason: '${credit.body}');
      return card;
    }

    /// Bob joins Ann's household as an editor.
    Future<void> bobJoins() async {
      final code =
          json(
                await api.as('ann').post('/v1/household/invites', {
                  'role': 'edit',
                }),
              )['code']
              as String;
      final r = await api.as('bob').post('/v1/invites/$code/accept', {
        'confirmLeave': false,
      });
      expect(r.status, 200, reason: '${r.body}');
    }

    // @lat: [[api-tests#Reminder sender#A due reminder is sent once to each device]]
    test('a due reminder goes once to each device, and a second run '
        'sends nothing new', () async {
      await annsCard();
      await remindersOn('ann');
      await device('ann', 'phone', 'Europe/London');
      await device('ann', 'tablet', 'Europe/London');

      final early = await sendDueReminders(
        db,
        push,
        now: londonNine.subtract(const Duration(minutes: 1)),
      );
      expect(early, 0);

      final sent = await sendDueReminders(
        db,
        push,
        now: londonNine.add(const Duration(minutes: 1)),
      );
      expect(sent, 2);
      expect(push.tagsTo('phone'), [lastDay]);
      expect(push.tagsTo('tablet'), [lastDay]);
      final message = push.sent.first.message;
      expect(message.title, r'$10 expires tonight');
      expect(message.body, contains('Dining'));
      expect(message.data['reminderId'], '2026-10-31|urgent');
      expect(message.data['url'], isNotEmpty);

      final again = await sendDueReminders(
        db,
        push,
        now: londonNine.add(const Duration(minutes: 16)),
      );
      expect(again, 0);
      expect(push.sent, hasLength(2));
    });

    // @lat: [[api-tests#Reminder sender#A reminder more than 36 hours late is dropped]]
    test('a reminder more than 36 hours late is not sent', () async {
      await annsCard();
      await remindersOn('ann');
      await device('ann', 'phone', 'Europe/London');

      final sent = await sendDueReminders(
        db,
        push,
        now: londonNine.add(const Duration(hours: 36, minutes: 1)),
      );
      expect(sent, 0);
      expect(push.sent, isEmpty);
    });

    // @lat: [[api-tests#Reminder sender#Nothing is sent to a member with reminders off]]
    test('a member with reminders off gets nothing', () async {
      await annsCard();
      await device('ann', 'phone', 'Europe/London');
      expect(
        await sendDueReminders(
          db,
          push,
          now: londonNine.add(const Duration(minutes: 1)),
        ),
        0,
      );
    });

    // @lat: [[api-tests#Reminder sender#Each member gets it at their own time of day]]
    test('members in two zones each get it at their own 09:00', () async {
      await annsCard();
      await bobJoins();
      await remindersOn('ann');
      await remindersOn('bob');
      await device('ann', 'ann-phone', 'Europe/London');
      await device('bob', 'bob-phone', 'America/New_York');

      await sendDueReminders(
        db,
        push,
        now: londonNine.add(const Duration(minutes: 1)),
      );
      expect(push.tagsTo('ann-phone'), [lastDay]);
      expect(push.tagsTo('bob-phone'), isEmpty);

      await sendDueReminders(
        db,
        push,
        now: newYorkNine.add(const Duration(minutes: 1)),
      );
      expect(push.tagsTo('ann-phone'), [lastDay]);
      expect(push.tagsTo('bob-phone'), [lastDay]);
    });

    // @lat: [[api-tests#Reminder sender#A muted card is silent for that member only]]
    test(
      'a member who muted the card gets nothing; another member does',
      () async {
        final card = await annsCard();
        await bobJoins();
        await remindersOn('ann');
        await remindersOn('bob');
        await device('ann', 'ann-phone', 'Europe/London');
        await device('bob', 'bob-phone', 'Europe/London');
        expect(
          (await api.as('bob').put('/v1/me/mutes/cards/$card', {})).status,
          204,
        );

        await sendDueReminders(
          db,
          push,
          now: londonNine.add(const Duration(minutes: 1)),
        );
        expect(push.tagsTo('ann-phone'), [lastDay]);
        expect(push.tagsTo('bob-phone'), isEmpty);
      },
    );

    // @lat: [[api-tests#Reminder sender#An unregistered token deletes its device]]
    test('a token FCM reports unregistered loses its device row', () async {
      await annsCard();
      await remindersOn('ann');
      await device('ann', 'live', 'Europe/London');
      await device('ann', 'dead', 'Europe/London');
      push.unregistered.add('dead');

      await sendDueReminders(
        db,
        push,
        now: londonNine.add(const Duration(minutes: 1)),
      );
      expect(push.tagsTo('live'), [lastDay]);
      final tokens = await db.execute('SELECT token FROM devices');
      expect([for (final r in tokens) r[0]], ['live']);
    });

    // @lat: [[api-tests#Reminder sender#The summary counts the member's schedule]]
    test(
      'the summary counts the caller\'s reminders and names the next',
      () async {
        await annsCard();
        await remindersOn('ann');
        await device('ann', 'phone', 'Europe/London');

        final r = await api.as('ann').get('/v1/me/reminders/summary');
        expect(r.status, 200, reason: '${r.body}');
        final summary = json(r);
        expect(summary['count'], greaterThan(0));
        final next = summary['next'] as Map<String, dynamic>;
        expect(
          DateTime.parse(next['fireAt'] as String).isAfter(DateTime.now()),
          isTrue,
        );
        expect(next['title'], isNotEmpty);

        final off = await api.as('bob').get('/v1/me/reminders/summary');
        expect(off.body, {'count': 0, 'next': null});
      },
    );

    // @lat: [[api-tests#Reminder sender#The test push reaches every device of the caller]]
    test('a test push goes to each of the caller\'s devices', () async {
      await device('ann', 'phone', 'Europe/London');
      await device('ann', 'tablet', 'Europe/London');
      await device('bob', 'bob-phone', 'Europe/London');

      final r = await api.as('ann').post('/v1/me/reminders/test');
      expect(r.status, 200, reason: '${r.body}');
      expect(r.body, {'sent': 2});
      expect({for (final s in push.sent) s.token}, {'phone', 'tablet'});
    });
  }, skip: url == null ? 'DATABASE_URL is not set' : false);
}
