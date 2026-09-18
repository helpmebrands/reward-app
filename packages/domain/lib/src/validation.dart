/// Form rules, as pure functions.
///
/// Each returns the sentence the field shows under itself, or null when the
/// value is fine. The sentence says what to enter rather than what went
/// wrong, because the person reading it is about to type (WCAG 3.3.3). The
/// editors own no rules of their own; they call these on blur and on submit.
library;

import 'dates.dart';

/// A text field that must not be blank. [message] says what to enter.
String? requiredError(String value, String message) {
  return value.trim().isNotEmpty ? null : message;
}

/// An amount of money that may be zero, such as an annual fee.
String? moneyError(String raw) {
  final cents = parseMoney(raw);
  return cents != null && cents >= 0
      ? null
      : 'Enter the amount as a number, like 695.';
}

/// An amount of money that must be worth something, such as a credit's value.
String? positiveMoneyError(String raw) {
  final cents = parseMoney(raw);
  return cents != null && cents > 0 ? null : 'Enter a value above zero.';
}

final RegExp _isoDate = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

/// The cardmember year start, as a calendar date.
String? anniversaryError(String value) {
  final match = _isoDate.firstMatch(value);
  if (match != null) {
    final year = int.parse(match[1]!);
    final month = int.parse(match[2]!);
    final day = int.parse(match[3]!);
    if (month >= 1 &&
        month <= 12 &&
        day >= 1 &&
        day <= daysInMonth(year, month)) {
      return null;
    }
  }
  return 'Enter the date the cardmember year starts.';
}

/// An enrolment page, if given, must be somewhere a browser can open.
String? enrollmentUrlError(String value) {
  if (value.trim().isEmpty) return null;
  final url = Uri.tryParse(value);
  if (url != null &&
      (url.scheme == 'https' || url.scheme == 'http') &&
      url.host.isNotEmpty) {
    return null;
  }
  return 'Enter a full web address, starting with https://.';
}

final RegExp _money = RegExp(r'^-?\d*(\.\d*)?$');

/// Whole cents from what was typed, or null when it is not a number.
int? parseMoney(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty || !_money.hasMatch(trimmed)) return null;
  final value = double.tryParse(trimmed);
  if (value == null || !value.isFinite) return null;
  return (value * 100).round();
}
