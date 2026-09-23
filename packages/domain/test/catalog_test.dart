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

    // @lat: [[tests#Card catalogue#Business Platinum is priced at its unconditional credits]]
    test('prices Business Platinum at its unconditional credits only', () {
      final platinum = findTemplate('amex-business-platinum')!;
      final gated = platinum.benefits
          .where((b) => b.spendThresholdCents != null)
          .map((b) => (b.name, b.spendThresholdCents))
          .toList();
      expect(gated, [
        ('Dell Technologies Credit (\$5K spend bonus)', 500000),
        ('Amex Travel Flight Credit (\$250K spend unlock)', 25000000),
        ('American Express One AP Credit (\$250K spend unlock)', 25000000),
      ]);
      final unconditional = platinum.benefits
          .where((b) => b.spendThresholdCents == null)
          .fold(
            0,
            (sum, b) =>
                sum + annualValueOf(b.valueCents, b.cadence, b.intervalMonths),
          );
      expect(templateAnnualValueCents(platinum), unconditional);
      expect(
        templateAnnualValueCents(platinum),
        lessThan(platinum.annualFeeCents * 4),
      );
    });

    // @lat: [[tests#Card catalogue#Every Global Entry credit rolls every 48 months]]
    test('amortises every Global Entry credit to \$30 a year', () {
      var seen = 0;
      for (final template in cardTemplates) {
        for (final benefit in template.benefits) {
          expect(
            benefit.cadence,
            isNot(Cadence.manual),
            reason: '${template.id}/${benefit.name}',
          );
          if (!benefit.name.startsWith('Global Entry')) continue;
          seen++;
          expect(
            benefit.cadence,
            Cadence.rolling,
            reason: '${template.id}/${benefit.name}',
          );
          expect(benefit.intervalMonths, 48);
          expect(
            annualValueOf(
              benefit.valueCents,
              benefit.cadence,
              benefit.intervalMonths,
            ),
            3000,
          );
        }
      }
      expect(seen, greaterThan(0));
    });

    // @lat: [[tests#Card catalogue#Dated credits carry their end]]
    test('ends the credits the issuer has dated', () {
      String? endsOn(String id, String name) =>
          findTemplate(id)!.benefits.firstWhere((b) => b.name == name).endsOn;
      const reserve = 'chase-sapphire-reserve';
      const quest = 'chase-united-quest';
      expect(endsOn(reserve, 'StubHub / viagogo Credit'), '2027-12-31');
      expect(endsOn(reserve, 'Peloton Membership Credit'), '2027-12-31');
      expect(endsOn(reserve, 'DoorDash Restaurant Promo'), '2027-12-31');
      expect(endsOn(reserve, 'DoorDash Non-Restaurant Promos'), '2027-12-31');
      expect(endsOn(reserve, 'Lyft Credit'), '2027-09-30');
      expect(endsOn(quest, 'Instacart \$10 Monthly Credit'), '2027-12-31');
      expect(endsOn(quest, 'Instacart \$5 Monthly Credit'), '2027-12-31');
    });

    // @lat: [[tests#Card catalogue#Every template names its kind]]
    test('marks Business Platinum as business and blank as personal', () {
      expect(findTemplate('amex-business-platinum')!.kind, CardKind.business);
      expect(findTemplate('blank')!.kind, CardKind.personal);
    });

    // @lat: [[tests#Card catalogue#The IHG spend credit is gated]]
    test('gates the IHG \$20K spend credit', () {
      final ihg = findTemplate(
        'chase-ihg-one-rewards-premier',
      )!.benefits.firstWhere((b) => b.name == '\$20K Spend Statement Credit');
      expect(ihg.spendThresholdCents, 2000000);
    });

    // @lat: [[tests#Card catalogue#A template amortises a rolling credit]]
    test(
      'prices a rolling credit at its amortised value and copies the interval',
      () {
        const template = CardTemplate(
          id: 't',
          issuer: 'Issuer',
          product: 'Product',
          network: CardNetwork.visa,
          annualFeeCents: 0,
          benefits: [
            BenefitTemplate(
              name: 'Global Entry',
              category: BenefitCategory.travel,
              icon: 'x',
              valueCents: 12000,
              cadence: Cadence.rolling,
              anchor: CycleAnchor.anniversary,
              intervalMonths: 48,
            ),
            BenefitTemplate(
              name: 'Open',
              category: BenefitCategory.other,
              icon: 'x',
              valueCents: 1500,
              cadence: Cadence.monthly,
              anchor: CycleAnchor.calendar,
            ),
          ],
        );
        expect(templateAnnualValueCents(template), 21000);
        final benefit = benefitsFromTemplate(
          template,
          'card-9',
          '2026-09-16T00:00:00.000Z',
          () => 'id',
        ).first;
        expect(benefit.cadence, Cadence.rolling);
        expect(benefit.intervalMonths, 48);
      },
    );

    // @lat: [[tests#Card catalogue#A template prices its year without its spend-gated credits]]
    test('prices a template without its spend-gated credits', () {
      const template = CardTemplate(
        id: 't',
        issuer: 'Issuer',
        product: 'Product',
        network: CardNetwork.visa,
        annualFeeCents: 0,
        benefits: [
          BenefitTemplate(
            name: 'Gated',
            category: BenefitCategory.other,
            icon: 'x',
            valueCents: 120000,
            cadence: Cadence.annual,
            anchor: CycleAnchor.calendar,
            spendThresholdCents: 25000000,
          ),
          BenefitTemplate(
            name: 'Open',
            category: BenefitCategory.other,
            icon: 'x',
            valueCents: 1500,
            cadence: Cadence.monthly,
            anchor: CycleAnchor.calendar,
          ),
        ],
      );
      expect(templateAnnualValueCents(template), 18000);
      expect(
        benefitsFromTemplate(
          template,
          'card-9',
          '2026-09-16T00:00:00.000Z',
          () => 'id',
        ).first.spendThresholdCents,
        25000000,
      );
    });

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

    // @lat: [[tests#Card catalogue#A template credit that has already ended lands inactive]]
    test('copies the end date and lands an already-ended credit inactive', () {
      const template = CardTemplate(
        id: 't',
        issuer: 'Issuer',
        product: 'Product',
        network: CardNetwork.visa,
        annualFeeCents: 0,
        benefits: [
          BenefitTemplate(
            name: 'Ended',
            category: BenefitCategory.other,
            icon: 'x',
            valueCents: 1000,
            cadence: Cadence.monthly,
            anchor: CycleAnchor.calendar,
            endsOn: '2026-06-30',
          ),
          BenefitTemplate(
            name: 'Ending',
            category: BenefitCategory.other,
            icon: 'x',
            valueCents: 1000,
            cadence: Cadence.monthly,
            anchor: CycleAnchor.calendar,
            endsOn: '2026-12-31',
          ),
          BenefitTemplate(
            name: 'Open',
            category: BenefitCategory.other,
            icon: 'x',
            valueCents: 1000,
            cadence: Cadence.monthly,
            anchor: CycleAnchor.calendar,
          ),
        ],
      );
      final benefits = benefitsFromTemplate(
        template,
        'card-9',
        '2026-09-16T00:00:00.000Z',
        () => 'id',
      );
      expect(benefits.map((b) => (b.endsOn, b.active)), [
        ('2026-06-30', false),
        ('2026-12-31', true),
        (null, true),
      ]);
    });
  });
}
