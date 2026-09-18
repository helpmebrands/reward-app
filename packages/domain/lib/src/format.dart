/// Display formatting shared by notification copy and the screens.
library;

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

/// Money for display, US dollars. Cents are dropped when the amount is whole,
/// because most credits are round numbers and "$15" reads faster than
/// "$15.00" in a list.
String formatMoney(int cents) {
  final sign = cents < 0 ? '-' : '';
  final magnitude = cents.abs();
  final whole = _groupThousands(magnitude ~/ 100);
  if (magnitude % 100 == 0) return '$sign\$$whole';
  return '$sign\$$whole.${(magnitude % 100).toString().padLeft(2, '0')}';
}

/// Always shows cents. Use in inputs and totals where precision matters.
String formatMoneyExact(int cents) {
  final sign = cents < 0 ? '-' : '';
  final magnitude = cents.abs();
  final whole = _groupThousands(magnitude ~/ 100);
  return '$sign\$$whole.${(magnitude % 100).toString().padLeft(2, '0')}';
}
