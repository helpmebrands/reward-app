/// Form rules, as pure functions.
///
/// Each returns the sentence the field shows under itself, or null when the
/// value is fine. The sentence says what to enter rather than what went
/// wrong, because the person reading it is about to type (WCAG 3.3.3). The
/// editors own no rules of their own; they call these on blur and on submit.
library;

import 'dates.dart';
import 'selectors.dart';
import 'types.dart';

/// A text field that must not be blank. [message] says what to enter.
String? requiredError(String value, String message) {
  return value.trim().isNotEmpty ? null : message;
}

/// A card's label, checked against every other card in the household: the
/// display name it gives ([cardLabel]) must not be another card's. [cardId]
/// is the card being edited, left out for a new one. Case and surrounding
/// space do not make two names different.
String? labelError(
  String label, {
  required List<Card> cards,
  required String issuer,
  required String product,
  String? cardId,
}) {
  final trimmed = label.trim();
  final name = trimmed.isNotEmpty ? trimmed : productName(issuer, product);
  final key = name.toLowerCase();
  final clash = cards.any(
    (card) => card.id != cardId && cardLabel(card).trim().toLowerCase() == key,
  );
  return clash
      ? 'Another card is already called $name. Enter a different label.'
      : null;
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
  return _isCalendarDate(value)
      ? null
      : 'Enter the date the cardmember year starts.';
}

final RegExp _wholeNumber = RegExp(r'^\d+$');

/// Months between claims: a whole number for a rolling credit, nothing
/// otherwise.
String? intervalMonthsError(Cadence cadence, String raw) {
  if (cadence != Cadence.rolling) return null;
  final trimmed = raw.trim();
  return _wholeNumber.hasMatch(trimmed) && int.parse(trimmed) > 0
      ? null
      : 'Enter how many months between claims.';
}

/// The last day a credit can be used, if it has one, as a calendar date.
String? endsOnError(String value) {
  if (value.trim().isEmpty) return null;
  return _isCalendarDate(value)
      ? null
      : 'Enter the last day it can be used as a date, or leave it blank.';
}

bool _isCalendarDate(String value) {
  final match = _isoDate.firstMatch(value);
  if (match == null) return false;
  final year = int.parse(match[1]!);
  final month = int.parse(match[2]!);
  final day = int.parse(match[3]!);
  return month >= 1 &&
      month <= 12 &&
      day >= 1 &&
      day <= daysInMonth(year, month);
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
