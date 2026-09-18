/// Display formatting: money, dates and deadlines in the words a person would
/// use. Money is US dollars; dates follow the forms the screens were drawn
/// with rather than a locale table.
library;

import 'dates.dart';
import 'types.dart';

String _groupThousands(int whole) {
  final digits = whole.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    final fromEnd = digits.length - i;
    buffer.write(digits[i]);
    if (fromEnd > 1 && fromEnd % 3 == 1) buffer.write(',');
  }
  return buffer.toString();
}

/// Money for display. Cents are dropped when the amount is whole, because
/// most credits are round numbers and "$15" reads faster than "$15.00" in a
/// list.
String formatMoney(int cents) {
  final magnitude = cents.abs();
  if (magnitude % 100 == 0) {
    return '${cents < 0 ? '-' : ''}\$${_groupThousands(magnitude ~/ 100)}';
  }
  return formatMoneyExact(cents);
}

/// Always shows cents. Use in inputs and totals where precision matters.
String formatMoneyExact(int cents) {
  final magnitude = cents.abs();
  final whole = _groupThousands(magnitude ~/ 100);
  final fraction = (magnitude % 100).toString().padLeft(2, '0');
  return '${cents < 0 ? '-' : ''}\$$whole.$fraction';
}

final RegExp _notMoney = RegExp(r'[^0-9.]');

int? parseMoneyToCents(String input) {
  final cleaned = input.replaceAll(_notMoney, '');
  if (cleaned.isEmpty) return null;
  final value = double.tryParse(cleaned);
  if (value == null || !value.isFinite || value < 0) return null;
  return (value * 100).round();
}

const List<String> _monthShort = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

const List<String> _monthLong = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const List<String> _weekdayShort = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

/// `Sep 30`, or `Sep 30, 2027` when the date is outside the current year.
String formatDate(IsoDate iso, [IsoDate? on]) {
  final parts = parseIsoDate(iso);
  final label = '${_monthShort[parts.month - 1]} ${parts.day}';
  return parts.year == parseIsoDate(on ?? todayIso()).year
      ? label
      : '$label, ${parts.year}';
}

/// `Sep 1 – Sep 30`, the window a credit is usable in.
String formatRange(IsoDate start, IsoDate end, [IsoDate? on]) {
  final day = on ?? todayIso();
  return '${formatDate(start, day)} – ${formatDate(end, day)}';
}

/// How long is left, in the words a person would use. The urgent end is
/// deliberately blunt: "Today" and "Tomorrow" beat "in 0 days".
String formatDaysRemaining(int days) {
  if (days < 0) return 'Expired';
  if (days == 0) return 'Today';
  if (days == 1) return 'Tomorrow';
  if (days < 7) return '$days days';
  if (days < 14) return '1 week';
  if (days < 31) return '${(days / 7).round()} weeks';
  if (days < 60) return '1 month';
  if (days < 365) return '${(days / 30).round()} months';
  return '${(days / 365).round()} year${days >= 730 ? 's' : ''}';
}

/// Screen-reader friendly version of [formatDaysRemaining].
String describeDeadline(int days, IsoDate end) {
  if (days < 0) return 'Expired on ${formatDate(end)}';
  if (days == 0) return 'Expires today, ${formatDate(end)}';
  if (days == 1) return 'Expires tomorrow, ${formatDate(end)}';
  return 'Expires in $days days, on ${formatDate(end)}';
}

String formatRelativeFromToday(IsoDate iso, [IsoDate? on]) {
  return formatDaysRemaining(daysBetween(on ?? todayIso(), iso));
}

/// Initials for a card avatar, e.g. "American Express" -> "AE".
String initials(String text) {
  final words = text
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return '?';
  if (words.length == 1) {
    final word = words.first;
    return (word.length > 2 ? word.substring(0, 2) : word).toUpperCase();
  }
  return '${words[0][0]}${words[1][0]}'.toUpperCase();
}

/// `Tue, 15 Sep`: the date beside the app name in the header.
String formatHeaderDate(IsoDate iso) {
  final parts = parseIsoDate(iso);
  final weekday = DateTime.utc(parts.year, parts.month, parts.day).weekday;
  return '${_weekdayShort[weekday - 1]}, ${parts.day} ${_monthShort[parts.month - 1]}';
}

/// `30 September`: a reset date read as a sentence rather than a label.
String formatResetDate(IsoDate iso) {
  final parts = parseIsoDate(iso);
  return '${parts.day} ${_monthLong[parts.month - 1]}';
}

/// Money split into its symbol and digits, so the headline can set them at
/// different sizes the way the design does.
({String symbol, String digits}) moneyParts(int cents) {
  final formatted = formatMoney(cents);
  final match = RegExp(r'^([^\d-]*)(.*)$').firstMatch(formatted);
  return (symbol: match?[1] ?? r'$', digits: match?[2] ?? formatted);
}
