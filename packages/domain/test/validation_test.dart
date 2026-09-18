import 'package:domain/domain.dart';
import 'package:test/test.dart';

/// Form rules, as pure functions. Each returns the sentence the field shows,
/// or null, so the editors never carry validation logic of their own.
void main() {
  group('form rules', () {
    // @lat: [[tests#Form rules#A required field must not be blank]]
    test('rejects a blank or whitespace holder and says what to enter', () {
      expect(
        requiredError('', 'Enter whose card this is.'),
        'Enter whose card this is.',
      );
      expect(
        requiredError('   ', 'Enter whose card this is.'),
        'Enter whose card this is.',
      );
      expect(requiredError('Jim', 'Enter whose card this is.'), isNull);
    });

    // @lat: [[tests#Form rules#Money must be a number, and a value must be above zero]]
    test('rejects a fee that is not a number and a value at or below zero', () {
      expect(moneyError(''), contains('number'));
      expect(moneyError('abc'), contains('number'));
      expect(moneyError('-5'), contains('number'));
      expect(moneyError('0'), isNull);
      expect(moneyError('695'), isNull);
      expect(moneyError('12.50'), isNull);

      expect(positiveMoneyError('0'), contains('above zero'));
      expect(positiveMoneyError('-1'), contains('above zero'));
      expect(positiveMoneyError('x'), contains('above zero'));
      expect(positiveMoneyError('0.01'), isNull);
    });

    // @lat: [[tests#Form rules#An anniversary must be a calendar date]]
    test('rejects a missing or malformed anniversary', () {
      expect(anniversaryError(''), contains('date'));
      expect(anniversaryError('2026-13-01'), contains('date'));
      expect(anniversaryError('14/03/2021'), contains('date'));
      expect(anniversaryError('2021-03-14'), isNull);
    });

    // @lat: [[tests#Form rules#An enrolment page must be a web address]]
    test(
      'rejects an enrolment page that is not an http(s) URL, and allows none',
      () {
        expect(enrollmentUrlError(''), isNull);
        expect(enrollmentUrlError('amex.com/enrol'), contains('https://'));
        expect(enrollmentUrlError('ftp://amex.com'), contains('https://'));
        expect(enrollmentUrlError('https://amex.com/enrol'), isNull);
        expect(enrollmentUrlError('http://amex.com/enrol'), isNull);
      },
    );
  });
}
