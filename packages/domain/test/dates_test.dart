import 'package:domain/domain.dart';
import 'package:test/test.dart';

// @lat: [[tests#Date arithmetic]]
void main() {
  group('addMonths', () {
    test('clamps to the end of a shorter target month', () {
      expect(addMonths('2026-01-31', 1), '2026-02-28');
      expect(addMonths('2026-08-31', 1), '2026-09-30');
    });

    test('handles leap years', () {
      expect(addMonths('2024-01-31', 1), '2024-02-29');
      expect(addMonths('2024-02-29', 12), '2025-02-28');
    });

    test('crosses year boundaries in both directions', () {
      expect(addMonths('2026-11-15', 3), '2027-02-15');
      expect(addMonths('2026-02-15', -3), '2025-11-15');
    });
  });

  group('addDays', () {
    test('does not drift across a DST transition', () {
      // US DST starts 2026-03-08; naive local-time arithmetic loses an hour
      // here and can roll the date back a day.
      expect(addDays('2026-03-07', 1), '2026-03-08');
      expect(addDays('2026-03-08', 1), '2026-03-09');
      expect(addDays('2026-11-01', 1), '2026-11-02');
    });

    test('steps backwards over month ends', () {
      expect(addDays('2026-03-01', -1), '2026-02-28');
    });
  });

  group('daysBetween', () {
    test('counts whole days and signs the direction', () {
      expect(daysBetween('2026-09-16', '2026-09-16'), 0);
      expect(daysBetween('2026-09-16', '2026-09-30'), 14);
      expect(daysBetween('2026-09-30', '2026-09-16'), -14);
    });

    test('spans a full non-leap year', () {
      expect(daysBetween('2026-01-01', '2027-01-01'), 365);
    });
  });

  group('isWithin', () {
    test('treats both bounds as inclusive', () {
      expect(isWithin('2026-09-01', '2026-09-01', '2026-09-30'), isTrue);
      expect(isWithin('2026-09-30', '2026-09-01', '2026-09-30'), isTrue);
      expect(isWithin('2026-08-31', '2026-09-01', '2026-09-30'), isFalse);
    });
  });

  group('todayIso', () {
    test('reads the local calendar date, not the UTC one', () {
      // 2026-09-16T23:30 local is already the 17th in UTC for eastern
      // offsets; the user still thinks of it as the 16th.
      expect(todayIso(DateTime(2026, 9, 16, 23, 30)), '2026-09-16');
      expect(todayIso(DateTime(2026, 1, 1, 0, 1)), '2026-01-01');
    });
  });
}
