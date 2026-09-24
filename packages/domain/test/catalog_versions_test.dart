import 'package:domain/domain.dart';
import 'package:test/test.dart';

import 'factories.dart';

/// Versioned catalogue templates, and how a linked card's credits resolve
/// against them: each cycle uses the version in force at its start.

BenefitTemplate _credit(
  String id, {
  int valueCents = 1500,
  Cadence cadence = Cadence.monthly,
  bool enrollmentRequired = false,
}) => BenefitTemplate(
  id: 'plat/$id',
  name: id,
  category: BenefitCategory.dining,
  icon: 'fork-knife',
  valueCents: valueCents,
  cadence: cadence,
  anchor: CycleAnchor.calendar,
  enrollmentRequired: enrollmentRequired,
);

TemplateVersion _version(
  int version,
  IsoDate effectiveFrom,
  List<BenefitTemplate> credits,
) => TemplateVersion(
  version: version,
  effectiveFrom: effectiveFrom,
  template: CardTemplate(
    id: 'plat',
    issuer: 'American Express',
    product: 'Platinum',
    network: CardNetwork.amex,
    kind: CardKind.personal,
    annualFeeCents: 89500,
    benefits: credits,
  ),
);

/// Version 1 from 2020 has $15 Uber and Resy; version 2 from 15 October
/// 2026 raises Uber to $20, drops Resy and adds a locked Equinox credit.
final versions = [
  _version(1, '2020-01-01', [
    _credit('uber'),
    _credit('resy', valueCents: 5000, cadence: Cadence.quarterly),
  ]),
  _version(2, '2026-10-15', [
    _credit('uber', valueCents: 2000),
    _credit('equinox', valueCents: 2500, enrollmentRequired: true),
  ]),
];

final card = makeCard(id: 'card-1').copyWith(templateId: 'plat');

LinkedBenefitState _state(String creditId) => LinkedBenefitState(
  id: 'benefit-$creditId',
  cardId: 'card-1',
  templateBenefitId: 'plat/$creditId',
  createdAt: '2020-01-01T00:00:00.000Z',
  updatedAt: '2020-01-01T00:00:00.000Z',
);

Benefit? resolve(String creditId, IsoDate on) =>
    resolveLinkedBenefit(versions, _state(creditId), card, on);

void main() {
  group('stable ids', () {
    // @lat: [[tests#Catalogue versions#Every template credit has a stable id]]
    test('every template credit has an id under its template, unique', () {
      for (final template in cardTemplates) {
        final ids = template.benefits.map((b) => b.id).toList();
        expect(ids.toSet(), hasLength(ids.length), reason: template.id);
        for (final id in ids) {
          expect(id, startsWith('${template.id}/'));
          expect(id, matches(RegExp(r'^[a-z0-9-]+/[a-z0-9-]+$')));
        }
      }
      expect(
        findTemplate('amex-gold')!.credit('amex-gold/uber-cash')?.name,
        'Uber Cash',
      );
    });
  });

  group('versionInForce', () {
    // @lat: [[tests#Catalogue versions#The version in force is the latest that has started]]
    test('picks the latest version whose effectiveFrom has passed', () {
      expect(versionInForce(versions, '2019-12-31'), isNull);
      expect(versionInForce(versions, '2026-10-14')!.version, 1);
      expect(versionInForce(versions, '2026-10-15')!.version, 2);
      expect(
        versionInForce(versions.reversed.toList(), '2027-01-01')!.version,
        2,
      );
    });
  });

  group('resolveLinkedBenefit', () {
    // @lat: [[tests#Catalogue versions#A cycle resolves against the version in force at its start]]
    test('a cycle that began before effectiveFrom keeps the old terms', () {
      // October's cycle began on the 1st, before version 2.
      expect(resolve('uber', '2026-10-20')!.valueCents, 1500);
      // November's began after it.
      expect(resolve('uber', '2026-11-05')!.valueCents, 2000);
      expect(resolve('uber', '2026-11-05')!.templateBenefitId, 'plat/uber');
    });

    // @lat: [[tests#Catalogue versions#Claims attach across versions by the stable id]]
    test('the resolved benefit keeps the household id across versions', () {
      final october = resolve('uber', '2026-10-20')!;
      final november = resolve('uber', '2026-11-05')!;
      expect(october.id, 'benefit-uber');
      expect(november.id, october.id);
      final claims = indexClaims([
        const Claim(
          id: 'c1',
          benefitId: 'benefit-uber',
          cycleKey: '2026-11-01',
          amountCents: 800,
          claimedAt: '2026-11-03T12:00:00.000Z',
        ),
      ]);
      final cycle = cycleFor(november, card, '2026-11-05')!;
      expect(claimedIn(claims, november.id, cycle.key), 800);
    });

    // @lat: [[tests#Catalogue versions#A credit dropped from a version stops at its effectiveFrom]]
    test('a credit missing from the newer version ends the day before it', () {
      final resy = resolve('resy', '2026-10-20')!;
      expect(resy.endsOn, '2026-10-14');
      expect(hasEnded(resy, '2026-10-20'), isTrue);
      expect(resolve('resy', '2026-09-20')!.endsOn, isNull);
    });

    // @lat: [[tests#Catalogue versions#A credit added in a version appears from its effectiveFrom]]
    test('a credit added in a version appears from its date, locked', () {
      expect(resolve('equinox', '2026-10-14'), isNull);
      final equinox = resolve('equinox', '2026-10-20')!;
      expect(equinox.valueCents, 2500);
      expect(isLocked(equinox, card, '2026-10-20'), isTrue);
    });
  });

  group('maintainedBy', () {
    // @lat: [[tests#Catalogue versions#A template link makes a card system-maintained]]
    test('is derived from the template link', () {
      expect(maintainedBy(makeCard()), MaintainedBy.user);
      expect(maintainedBy(card), MaintainedBy.system);
    });

    // @lat: [[tests#Catalogue versions#The links round-trip in the snapshot]]
    test(
      'the card and benefit links round-trip and are omitted when absent',
      () {
        final json = cardToJson(card);
        expect(json['templateId'], 'plat');
        expect(cardFromJson(json).templateId, 'plat');
        expect(cardToJson(makeCard()).containsKey('templateId'), isFalse);
        final benefit = resolve('uber', '2026-11-05')!;
        expect(
          benefitFromJson(benefitToJson(benefit)).templateBenefitId,
          'plat/uber',
        );
        expect(
          benefitToJson(
            makeBenefit(Cadence.monthly),
          ).containsKey('templateBenefitId'),
          isFalse,
        );
      },
    );
  });
}
