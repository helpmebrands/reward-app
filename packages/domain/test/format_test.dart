import 'package:domain/domain.dart';
import 'package:test/test.dart';

const today = '2026-09-16';

void main() {
  group('money', () {
    // @lat: [[tests#Formatting#Whole dollars drop the cents]]
    test('drops the cents when the amount is whole and groups thousands', () {
      expect(formatMoney(1500), r'$15');
      expect(formatMoney(1295), r'$12.95');
      expect(formatMoney(150000), r'$1,500');
      expect(formatMoney(-500), r'-$5');
      expect(formatMoneyExact(1500), r'$15.00');
      expect(moneyParts(150000), (symbol: r'$', digits: '1,500'));
    });

    // @lat: [[tests#Formatting#Typed money becomes whole cents]]
    test('turns typed money into whole cents and refuses nonsense', () {
      expect(parseMoneyToCents(r'$1,234.50'), 123450);
      expect(parseMoneyToCents('12'), 1200);
      expect(parseMoneyToCents(''), isNull);
      expect(parseMoneyToCents('abc'), isNull);
      expect(parseMoney('12.5'), 1250);
      expect(parseMoney('-5'), -500);
      expect(parseMoney('1,000'), isNull);
    });
  });

  group('dates', () {
    // @lat: [[tests#Formatting#Dates show the year only outside the current one]]
    test('shows the year only when the date is outside the current one', () {
      expect(formatDate('2026-09-30', today), 'Sep 30');
      expect(formatDate('2027-03-13', today), 'Mar 13, 2027');
      expect(formatRange('2026-09-01', '2026-09-30', today), 'Sep 1 – Sep 30');
      expect(formatHeaderDate('2026-09-15'), 'Tue, 15 Sep');
      expect(formatResetDate('2026-09-30'), '30 September');
    });

    // @lat: [[tests#Formatting#Deadlines read the way a person would say them]]
    test('says how long is left in words, bluntly at the urgent end', () {
      expect(formatDaysRemaining(-1), 'Expired');
      expect(formatDaysRemaining(0), 'Today');
      expect(formatDaysRemaining(1), 'Tomorrow');
      expect(formatDaysRemaining(5), '5 days');
      expect(formatDaysRemaining(10), '1 week');
      expect(formatDaysRemaining(21), '3 weeks');
      expect(formatDaysRemaining(45), '1 month');
      expect(formatDaysRemaining(200), '7 months');
      expect(formatDaysRemaining(400), '1 year');
      expect(formatDaysRemaining(800), '2 years');
      expect(formatRelativeFromToday('2026-09-30', today), '2 weeks');
    });

    // @lat: [[tests#Formatting#Screen readers hear the date with the deadline]]
    test('describes a deadline with its date for screen readers', () {
      expect(
        describeDeadline(0, '2026-09-30'),
        startsWith('Expires today, Sep 30'),
      );
      expect(
        describeDeadline(1, '2026-09-30'),
        startsWith('Expires tomorrow, Sep 30'),
      );
      expect(
        describeDeadline(14, '2026-09-30'),
        startsWith('Expires in 14 days, on Sep 30'),
      );
      expect(
        describeDeadline(-3, '2026-09-30'),
        startsWith('Expired on Sep 30'),
      );
    });
  });

  group('initials', () {
    // @lat: [[tests#Formatting#Initials come from the first two words]]
    test(
      'takes the first letter of the first two words, or two letters of one',
      () {
        expect(initials('American Express'), 'AE');
        expect(initials('Chase'), 'CH');
        expect(initials(''), '?');
      },
    );
  });
}
