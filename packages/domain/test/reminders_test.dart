import 'package:domain/domain.dart';
import 'package:test/test.dart';

import 'factories.dart';

/// 16 Sep 2026, 08:00 local, before the 09:00 reminder time.
final now = DateTime(2026, 9, 16, 8, 0, 0);

AppData withNotifications(
  AppData data, {
  int? minValueCents,
  bool? enrollmentReminder,
}) {
  final current = data.settings.notifications;
  return AppData(
    version: data.version,
    cards: data.cards,
    benefits: data.benefits,
    claims: data.claims,
    settings: Settings(
      notifications: NotificationSettings(
        enabled: true,
        timeOfDay: current.timeOfDay,
        minValueCents: minValueCents ?? current.minValueCents,
        annualFeeReminder: current.annualFeeReminder,
        enrollmentReminder: enrollmentReminder ?? current.enrollmentReminder,
      ),
      useSoonDays: data.settings.useSoonDays,
      theme: data.settings.theme,
      holderFilter: data.settings.holderFilter,
    ),
  );
}

Reminder stub(String id, int fireAt) => Reminder(
  id: id,
  fireAt: fireAt,
  title: '',
  body: '',
  tag: '',
  url: '',
  items: const [],
  totalCents: 0,
  tone: Tone.notice,
);

// @lat: [[tests#Ladder and schedule]]
void main() {
  group('the ladder', () {
    test('gives each cadence rungs proportional to its window', () {
      expect(defaultLadder(Cadence.monthly).map((r) => r.daysBefore).toList(), [
        23,
        7,
        0,
      ]);
      expect(
        defaultLadder(Cadence.quarterly).map((r) => r.daysBefore).toList(),
        [30, 14, 3],
      );
      expect(
        defaultLadder(Cadence.semiannual).map((r) => r.daysBefore).toList(),
        [60, 21, 7],
      );
      expect(defaultLadder(Cadence.annual).map((r) => r.daysBefore).toList(), [
        180,
        90,
        30,
        7,
      ]);
    });

    test('opens permissively and ends urgent', () {
      final rungs = defaultLadder(Cadence.quarterly);
      expect(rungs.first.tone, Tone.permissive);
      expect(rungs.last.tone, Tone.urgent);
    });

    test('reduces to a single last call when the user opts out', () {
      final rungs = ladderFor(makeBenefit(Cadence.annual, lastCallOnly: true));
      expect(rungs, hasLength(1));
      expect(rungs.first.daysBefore, 7);
    });

    test('reports the rung a credit is standing on', () {
      final monthly = makeBenefit(Cadence.monthly);
      expect(currentRung(monthly, 28), isNull);
      expect(currentRung(monthly, 23)?.tone, Tone.permissive);
      expect(currentRung(monthly, 7)?.tone, Tone.notice);
      expect(currentRung(monthly, 0)?.tone, Tone.urgent);
    });

    test('summarises a cadence for the settings screen', () {
      expect(ladderSummary(Cadence.quarterly), '30 · 14 · 3');
      expect(ladderSummary(Cadence.monthly), '23 · 7 · last day');
    });
  });

  group('buildSchedule', () {
    test('produces nothing while reminders are switched off', () {
      expect(buildSchedule(makeData(), now).reminders, isEmpty);
    });

    test('schedules a rung at the reminder time on the right day', () {
      // A monthly credit closing 30 Sep fires its 7-day rung on 23 Sep at 09:00.
      final data = withNotifications(
        makeData(benefits: [makeBenefit(Cadence.monthly)]),
      );
      final fired = buildSchedule(
        data,
        now,
      ).reminders.map((r) => DateTime.fromMillisecondsSinceEpoch(r.fireAt));
      final sept23 = fired.where((d) => d.day == 23 && d.month == 9).toList();
      expect(sept23, isNotEmpty);
      expect(sept23.first.hour, 9);
    });

    test('never schedules a rung in the past', () {
      final data = withNotifications(
        makeData(benefits: [makeBenefit(Cadence.monthly)]),
      );
      for (final reminder in buildSchedule(data, now).reminders) {
        expect(reminder.fireAt, greaterThan(now.millisecondsSinceEpoch));
      }
    });

    test('groups credits that fire on the same day into one notification', () {
      // Twelve separate alerts on one morning is how an app gets muted.
      final data = withNotifications(
        makeData(
          benefits: [
            makeBenefit(
              Cadence.monthly,
              id: 'a',
              name: 'Uber Cash',
              valueCents: 1500,
            ),
            makeBenefit(
              Cadence.monthly,
              id: 'b',
              name: 'Walmart+',
              valueCents: 1295,
            ),
            makeBenefit(
              Cadence.monthly,
              id: 'c',
              name: 'Entertainment',
              valueCents: 2500,
            ),
          ],
        ),
      );
      final sameDay = buildSchedule(
        data,
        now,
      ).reminders.where((r) => r.id == '2026-09-23|notice').toList();
      expect(sameDay, hasLength(1));
      expect(sameDay.first.items, hasLength(3));
      expect(sameDay.first.totalCents, 5295);
    });

    test('leads the copy with the single biggest loss', () {
      final data = withNotifications(
        makeData(
          benefits: [
            makeBenefit(
              Cadence.monthly,
              id: 'a',
              name: 'Uber Cash',
              valueCents: 1500,
            ),
            makeBenefit(
              Cadence.monthly,
              id: 'b',
              name: 'Resy',
              valueCents: 10000,
            ),
          ],
        ),
      );
      final reminder = buildSchedule(
        data,
        now,
      ).reminders.firstWhere((r) => r.id == '2026-09-23|notice');
      expect(reminder.body, contains('Resy'));
      expect(reminder.title, contains(r'$115'));
    });

    test('leads with the blocker when most of the money is locked', () {
      // Telling someone to spend money they cannot reach is worse than silence.
      final data = withNotifications(
        makeData(
          benefits: [
            makeBenefit(
              Cadence.monthly,
              id: 'a',
              name: 'Uber Cash',
              valueCents: 1500,
            ),
            makeBenefit(
              Cadence.monthly,
              id: 'b',
              name: 'Equinox',
              valueCents: 30000,
              enrollmentRequired: true,
            ),
          ],
        ),
      );
      final reminder = buildSchedule(
        data,
        now,
      ).reminders.firstWhere((r) => r.id == '2026-09-23|notice');
      expect(reminder.title, contains('locked'));
    });

    test(
      'stays silent about locked credits when that reminder is switched off',
      () {
        final data = withNotifications(
          makeData(
            benefits: [makeBenefit(Cadence.monthly, enrollmentRequired: true)],
          ),
          enrollmentReminder: false,
        );
        expect(buildSchedule(data, now).reminders, isEmpty);
      },
    );

    test(
      'skips a credit the user has muted, and every credit on a muted card',
      () {
        final muted = withNotifications(
          makeData(benefits: [makeBenefit(Cadence.monthly, muted: true)]),
        );
        expect(buildSchedule(muted, now).reminders, isEmpty);

        final mutedCard = withNotifications(
          makeData(cards: [makeCard(muted: true)]),
        );
        expect(buildSchedule(mutedCard, now).reminders, isEmpty);
      },
    );

    test('skips a cycle that has already been fully claimed', () {
      final data = withNotifications(
        makeData(
          benefits: [makeBenefit(Cadence.monthly, valueCents: 2500)],
          claims: [makeClaim(amountCents: 2500)],
        ),
      );
      final september = buildSchedule(data, now).reminders.where(
        (r) => DateTime.fromMillisecondsSinceEpoch(r.fireAt).month == 9,
      );
      expect(september, isEmpty);
    });

    test('still reminds about the balance of a partly used credit', () {
      final data = withNotifications(
        makeData(
          benefits: [makeBenefit(Cadence.monthly, valueCents: 2500)],
          claims: [makeClaim(amountCents: 1000)],
        ),
      );
      final reminder = buildSchedule(
        data,
        now,
      ).reminders.firstWhere((r) => r.id == '2026-09-23|notice');
      expect(reminder.totalCents, 1500);
    });

    test(
      'reminds against the clamped end of a credit that ends on a date, then stops',
      () {
        final data = withNotifications(
          makeData(
            benefits: [makeBenefit(Cadence.monthly, endsOn: '2026-09-20')],
          ),
        );
        final reminders = buildSchedule(data, now).reminders;
        expect(reminders.map((r) => r.id), ['2026-09-20|urgent']);
        expect(reminders.first.items.first.endsOn, '2026-09-20');
        expect(
          buildSchedule(data, DateTime(2026, 9, 21, 8, 0, 0)).reminders,
          isEmpty,
        );
      },
    );

    test(
      'never schedules a spend-locked credit, even with enrolment reminders on',
      () {
        final data = withNotifications(
          makeData(
            benefits: [makeBenefit(Cadence.monthly, spendThresholdCents: 100)],
          ),
          enrollmentReminder: true,
        );
        expect(buildSchedule(data, now).reminders, isEmpty);
      },
    );

    test('ignores untracked credits, which have no deadline to warn about', () {
      final data = withNotifications(
        makeData(benefits: [makeBenefit(Cadence.manual)]),
      );
      expect(buildSchedule(data, now).reminders, isEmpty);
    });

    test('respects the minimum-value floor', () {
      final data = withNotifications(
        makeData(benefits: [makeBenefit(Cadence.monthly, valueCents: 50)]),
        minValueCents: 100,
      );
      expect(buildSchedule(data, now).reminders, isEmpty);
    });

    test(
      'gives every reminder a stable, unique id so recomputing cannot duplicate',
      () {
        // Ids must survive a recompute: delivery dedupes on them, and a reminder
        // that changed identity every launch would fire again each time.
        final data = withNotifications(
          makeData(benefits: [makeBenefit(Cadence.quarterly)]),
        );
        final later = DateTime(2026, 9, 16, 10, 0, 0);
        final first = buildSchedule(data, now).reminders;
        final second = buildSchedule(data, later).reminders;

        expect(first.map((r) => r.id).toSet().length, first.length);
        // Rungs that passed between the two runs drop out; every one still ahead
        // keeps the id it had.
        expect(
          second.map((r) => r.id).toList(),
          first
              .where((r) => r.fireAt > later.millisecondsSinceEpoch)
              .map((r) => r.id)
              .toList(),
        );
      },
    );

    test('returns reminders in the order they will fire', () {
      final data = withNotifications(
        makeData(
          benefits: [
            makeBenefit(Cadence.monthly, id: 'm'),
            makeBenefit(Cadence.annual, id: 'a'),
          ],
        ),
      );
      final times = buildSchedule(
        data,
        now,
      ).reminders.map((r) => r.fireAt).toList();
      expect(times, [...times]..sort());
    });
  });

  group('dueReminders', () {
    final schedule = ReminderSchedule(
      generatedAt: 0,
      reminders: [stub('past', 1000), stub('future', 100000)],
    );

    test('returns only what has come due and has not been shown', () {
      expect(dueReminders(schedule, 2000, {}).map((r) => r.id).toList(), [
        'past',
      ]);
      expect(dueReminders(schedule, 2000, {'past'}), isEmpty);
    });

    test('drops a reminder the device slept through for days', () {
      // By then the deadline has moved and the schedule has been rebuilt.
      const threeDays = 3 * 24 * 60 * 60 * 1000;
      expect(dueReminders(schedule, threeDays, {}), isEmpty);
    });
  });
}
