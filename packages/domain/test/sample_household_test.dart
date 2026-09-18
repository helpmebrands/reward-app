import 'dart:convert';
import 'dart:io';

import 'package:domain/domain.dart';
import 'package:test/test.dart';

/// The sample household is the PWA's `samples/sample-household.json`, read
/// straight from the frozen app so the two implementations are held to the
/// same data. The expected ids come from the TypeScript `buildSchedule` run
/// on 16 September 2026 at 08:00 local by `apps/pwa/scripts/schedule-ids.ts`.
AppData loadSampleHousehold() {
  final json =
      jsonDecode(
            File(
              '../../apps/pwa/samples/sample-household.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final data = appDataFromJson(json);
  // The sample ships with reminders off; the schedule is built as if the
  // user had switched them on, exactly as the TypeScript dump does.
  final n = data.settings.notifications;
  return AppData(
    version: data.version,
    cards: data.cards,
    benefits: data.benefits,
    claims: data.claims,
    settings: Settings(
      notifications: NotificationSettings(
        enabled: true,
        timeOfDay: n.timeOfDay,
        minValueCents: n.minValueCents,
        annualFeeReminder: n.annualFeeReminder,
        enrollmentReminder: n.enrollmentReminder,
      ),
      useSoonDays: data.settings.useSoonDays,
      theme: data.settings.theme,
      holderFilter: data.settings.holderFilter,
    ),
  );
}

// @lat: [[tests#Ladder and schedule#The sample household schedules the same ids in Dart]]
void main() {
  test(
    'the sample household schedules the same group ids as the TypeScript build',
    () {
      final expected =
          (jsonDecode(
                    File(
                      'test/fixtures/sample-schedule-ids.json',
                    ).readAsStringSync(),
                  )
                  as List)
              .cast<String>();
      final schedule = buildSchedule(
        loadSampleHousehold(),
        DateTime(2026, 9, 16, 8, 0, 0),
      );
      expect(schedule.reminders.map((r) => r.id).toList(), expected);
    },
  );
}
