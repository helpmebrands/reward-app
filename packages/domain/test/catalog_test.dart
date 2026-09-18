import 'package:domain/domain.dart';
import 'package:test/test.dart';

void main() {
  group('the catalogue', () {
    // @lat: [[tests#Card catalogue#Every template gives each credit an icon and a value]]
    test(
      'gives every template an icon and a positive value for each credit',
      () {
        for (final template in cardTemplates) {
          for (final benefit in template.benefits) {
            expect(
              benefit.icon,
              isNotEmpty,
              reason: '${template.id}/${benefit.name}',
            );
            expect(
              benefit.valueCents,
              greaterThan(0),
              reason: '${template.id}/${benefit.name}',
            );
          }
        }
      },
    );

    // @lat: [[tests#Card catalogue#Templates are found by id and end with blank]]
    test('finds a template by id and keeps a blank one for unknown cards', () {
      expect(findTemplate('amex-platinum')?.product, 'Platinum');
      expect(findTemplate('nope'), isNull);
      final blank = findTemplate('blank');
      expect(blank?.benefits, isEmpty);
      expect(cardTemplates.last.id, 'blank');
    });

    // @lat: [[tests#Card catalogue#A template prices its year and names its locked credits]]
    test(
      'prices a template over a year and names the credits behind enrolment',
      () {
        final template = CardTemplate(
          id: 't',
          issuer: 'Issuer',
          product: 'Product',
          network: CardNetwork.visa,
          annualFeeCents: 0,
          benefits: const [
            BenefitTemplate(
              name: 'Monthly',
              category: BenefitCategory.other,
              icon: 'x',
              valueCents: 1500,
              cadence: Cadence.monthly,
              anchor: CycleAnchor.calendar,
              enrollmentRequired: true,
            ),
            BenefitTemplate(
              name: 'Annual',
              category: BenefitCategory.other,
              icon: 'x',
              valueCents: 20000,
              cadence: Cadence.annual,
              anchor: CycleAnchor.anniversary,
            ),
          ],
        );
        expect(templateAnnualValueCents(template), 38000);
        expect(templateEnrollmentNames(template), ['Monthly']);
      },
    );

    // @lat: [[tests#Card catalogue#Template credits become ordinary benefits]]
    test('stamps template entries into real benefits with fresh ids', () {
      final template = findTemplate('amex-platinum')!;
      var next = 0;
      final benefits = benefitsFromTemplate(
        template,
        'card-9',
        '2026-09-16T00:00:00.000Z',
        () => 'b${next++}',
      );
      expect(benefits, hasLength(template.benefits.length));
      expect(benefits.map((b) => b.id).toSet().length, benefits.length);
      expect(benefits.first.cardId, 'card-9');
      expect(benefits.first.name, template.benefits.first.name);
      expect(benefits.first.active, isTrue);
      expect(benefits.first.muted, isFalse);
      expect(benefits.first.createdAt, '2026-09-16T00:00:00.000Z');
      final locked = benefits
          .where((b) => b.enrollmentRequired)
          .map((b) => b.name)
          .toList();
      expect(locked, templateEnrollmentNames(template));
    });
  });
}
