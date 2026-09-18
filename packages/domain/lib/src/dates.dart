/// Calendar-date arithmetic.
///
/// Everything here operates on `YYYY-MM-DD` strings and computes in UTC,
/// which has no DST transitions. Using local-time dates for calendar maths
/// silently shifts dates by a day twice a year in most timezones.
library;

import 'types.dart';

final RegExp _isoDate = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

class DateParts {
  const DateParts({required this.year, required this.month, required this.day});

  final int year;

  /// 1-12.
  final int month;

  /// 1-31.
  final int day;
}

DateParts parseIsoDate(IsoDate iso) {
  final match = _isoDate.firstMatch(iso);
  if (match == null) throw RangeError('Not an ISO calendar date: $iso');
  final parts = DateParts(
    year: int.parse(match[1]!),
    month: int.parse(match[2]!),
    day: int.parse(match[3]!),
  );
  if (parts.month < 1 || parts.month > 12) {
    throw RangeError('Bad month in $iso');
  }
  if (parts.day < 1 || parts.day > daysInMonth(parts.year, parts.month)) {
    throw RangeError('Bad day in $iso');
  }
  return parts;
}

IsoDate formatIsoDate(DateParts parts) {
  final yyyy = parts.year.toString().padLeft(4, '0');
  final mm = parts.month.toString().padLeft(2, '0');
  final dd = parts.day.toString().padLeft(2, '0');
  return '$yyyy-$mm-$dd';
}

int daysInMonth(int year, int month) {
  // Day 0 of the next month is the last day of this one.
  return DateTime.utc(year, month + 1, 0).day;
}

DateTime _toUtc(IsoDate iso) {
  final parts = parseIsoDate(iso);
  return DateTime.utc(parts.year, parts.month, parts.day);
}

IsoDate _fromUtc(DateTime date) {
  return formatIsoDate(
    DateParts(year: date.year, month: date.month, day: date.day),
  );
}

IsoDate addDays(IsoDate iso, int days) {
  return _fromUtc(_toUtc(iso).add(Duration(days: days)));
}

/// Adds calendar months, clamping the day to the target month's length so
/// that `2026-01-31 + 1 month` is `2026-02-28` rather than rolling into March.
IsoDate addMonths(IsoDate iso, int months) {
  final parts = parseIsoDate(iso);
  final zeroBased = parts.year * 12 + (parts.month - 1) + months;
  // Dart's % is non-negative for a positive divisor, so this floors for
  // negative totals too.
  final targetMonth = zeroBased % 12 + 1;
  final targetYear = (zeroBased - zeroBased % 12) ~/ 12;
  final day = parts.day < daysInMonth(targetYear, targetMonth)
      ? parts.day
      : daysInMonth(targetYear, targetMonth);
  return formatIsoDate(
    DateParts(year: targetYear, month: targetMonth, day: day),
  );
}

/// Whole days from [from] to [to]; negative when [to] is earlier.
int daysBetween(IsoDate from, IsoDate to) {
  return _toUtc(to).difference(_toUtc(from)).inDays;
}

int compareIsoDate(IsoDate a, IsoDate b) {
  // ISO calendar dates are zero-padded, so lexical order is chronological.
  return a.compareTo(b).sign;
}

IsoDate minIsoDate(IsoDate a, IsoDate b) => compareIsoDate(a, b) <= 0 ? a : b;

IsoDate maxIsoDate(IsoDate a, IsoDate b) => compareIsoDate(a, b) >= 0 ? a : b;

/// True when [iso] falls within `[start, end]`, both inclusive.
bool isWithin(IsoDate iso, IsoDate start, IsoDate end) {
  return compareIsoDate(iso, start) >= 0 && compareIsoDate(iso, end) <= 0;
}

/// The user's current calendar date, read from their local clock. Benefit
/// windows are the issuer's calendar dates, and the user experiences them
/// locally, so "today" is deliberately local rather than UTC.
IsoDate todayIso([DateTime? now]) {
  final local = (now ?? DateTime.now()).toLocal();
  return formatIsoDate(
    DateParts(year: local.year, month: local.month, day: local.day),
  );
}

/// Local midnight at the start of [iso], as a real instant.
DateTime startOfDayLocal(IsoDate iso) {
  final parts = parseIsoDate(iso);
  return DateTime(parts.year, parts.month, parts.day);
}

/// Local `HH:MM` on [iso], as a real instant. Used to schedule reminders.
DateTime atLocalTime(IsoDate iso, String timeOfDay) {
  final pieces = timeOfDay.split(':');
  final hour = pieces.isNotEmpty ? int.tryParse(pieces[0]) ?? 9 : 9;
  final minute = pieces.length > 1 ? int.tryParse(pieces[1]) ?? 0 : 0;
  final parts = parseIsoDate(iso);
  return DateTime(parts.year, parts.month, parts.day, hour, minute);
}
