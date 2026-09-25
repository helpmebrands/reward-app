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
  return appDataFromJson(json);
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
      // The sample ships with reminders off; the schedule is built for a
      // member who has switched them on, exactly as the TypeScript dump does.
      final schedule = buildSchedule(
        loadSampleHousehold(),
        defaultMemberPreferences.copyWith(enabled: true),
        DateTime(2026, 9, 16, 8, 0, 0),
      );
      expect(schedule.reminders.map((r) => r.id).toList(), expected);
    },
  );
}
