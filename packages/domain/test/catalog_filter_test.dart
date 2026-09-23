import 'package:domain/domain.dart';
import 'package:test/test.dart';

BenefitTemplate _credit(
  String name, {
  String? merchant,
  int valueCents = 1000,
}) => BenefitTemplate(
  name: name,
  category: BenefitCategory.other,
  icon: 'gift',
  merchant: merchant,
  valueCents: valueCents,
  cadence: Cadence.annual,
  anchor: CycleAnchor.calendar,
);

CardTemplate _template(
  String id, {
  String issuer = 'Chase',
  String product = 'Card',
  CardNetwork network = CardNetwork.visa,
  int annualFeeCents = 0,
  List<BenefitTemplate> benefits = const [],
}) => CardTemplate(
  id: id,
  issuer: issuer,
  product: product,
  network: network,
  kind: CardKind.personal,
  annualFeeCents: annualFeeCents,
  benefits: benefits,
);

List<String> _ids(List<CardTemplate> templates) =>
    templates.map((t) => t.id).toList();

void main() {
  group('fee bands', () {
    // @lat: [[tests#Catalogue filter#Fee bands split at their cent boundaries]]
    test('put each fee in the band whose cent range holds it', () {
      expect(FeeBand.of(0), FeeBand.none);
      expect(FeeBand.of(1), FeeBand.under100);
      expect(FeeBand.of(9999), FeeBand.under100);
      expect(FeeBand.of(10000), FeeBand.from100);
      expect(FeeBand.of(39999), FeeBand.from100);
      expect(FeeBand.of(40000), FeeBand.from400);
      expect(FeeBand.of(59999), FeeBand.from400);
      expect(FeeBand.of(60000), FeeBand.from600);
      expect(FeeBand.values.map((b) => b.label), [
        'No fee',
        'Under \$100',
        '\$100–\$399',
        '\$400–\$599',
        '\$600+',
      ]);
    });
  });

  group('filterTemplates', () {
    final templates = [
      _template(
        'chase-a',
        issuer: 'Chase',
        benefits: [_credit('DoorDash', merchant: 'DoorDash')],
      ),
      _template(
        'citi-a',
        issuer: 'Citi',
        benefits: [_credit('Uber Cash', merchant: 'Uber')],
      ),
      _template(
        'amex-a',
        issuer: 'American Express',
        benefits: [_credit('Resy', merchant: 'Resy')],
      ),
      _template(
        'chase-b',
        issuer: 'Chase',
        benefits: [_credit('Uber One', merchant: 'Uber')],
      ),
    ];

    // @lat: [[tests#Catalogue filter#Values OR within a facet and facets AND together]]
    test('ors values within a facet and ands the facets', () {
      final twoIssuers = const CatalogFilter()
          .toggleIssuer('Chase')
          .toggleIssuer('Citi');
      expect(_ids(filterTemplates(templates, twoIssuers)), [
        'chase-a',
        'citi-a',
        'chase-b',
      ]);
      expect(
        _ids(filterTemplates(templates, twoIssuers.toggleMerchant('Uber'))),
        ['citi-a', 'chase-b'],
      );
      expect(
        _ids(
          filterTemplates(
            templates,
            const CatalogFilter().toggleNetwork(CardNetwork.amex),
          ),
        ),
        isEmpty,
      );
      expect(
        _ids(
          filterTemplates(
            templates,
            const CatalogFilter().toggleFeeBand(FeeBand.none),
          ),
        ),
        _ids(templates),
      );
    });

    // @lat: [[tests#Catalogue filter#Search matches issuer, product, benefit name and merchant]]
    test('searches issuer, product, benefit name and merchant in any case', () {
      final real = cardTemplates;
      final uber = filterTemplates(real, const CatalogFilter(search: 'UbEr'));
      expect(uber, isNotEmpty);
      for (final t in uber) {
        expect(
          '${t.issuer} ${t.product}'.toLowerCase(),
          isNot(contains('uber')),
        );
        expect(
          t.benefits.any(
            (b) =>
                b.name.toLowerCase().contains('uber') ||
                (b.merchant ?? '').toLowerCase().contains('uber'),
          ),
          isTrue,
        );
      }
      expect(_ids(uber), contains('amex-platinum'));
      final chase = filterTemplates(real, const CatalogFilter(search: 'chase'));
      expect(chase.map((t) => t.issuer).toSet(), contains('Chase'));
      expect(
        _ids(filterTemplates(real, const CatalogFilter(search: 'sapphire p'))),
        ['chase-sapphire-preferred'],
      );
    });

    // @lat: [[tests#Catalogue filter#The blank template never appears]]
    test('never returns or counts the blank template', () {
      expect(
        _ids(filterTemplates(cardTemplates, const CatalogFilter())),
        isNot(contains('blank')),
      );
      expect(
        filterTemplates(cardTemplates, const CatalogFilter()),
        hasLength(cardTemplates.length - 1),
      );
      final counts = facetCounts(cardTemplates, const CatalogFilter());
      expect(counts.feeBands[FeeBand.none], 0);
      expect(counts.networks.keys, isNot(contains(CardNetwork.other)));
      expect(counts.issuers.keys, isNot(contains('')));
    });
  });

  group('facetCounts', () {
    // @lat: [[tests#Catalogue filter#A facet's counts ignore its own selection]]
    test('counts each option against every facet but its own', () {
      final none = facetCounts(cardTemplates, const CatalogFilter());
      final chase = const CatalogFilter().toggleIssuer('Chase');
      final counts = facetCounts(cardTemplates, chase);
      expect(counts.issuers['Chase'], 4);
      expect(counts.issuers, none.issuers);
      final chaseCards = filterTemplates(cardTemplates, chase);
      for (final entry in counts.merchants.entries) {
        expect(
          entry.value,
          chaseCards
              .where((t) => t.benefits.any((b) => b.merchant == entry.key))
              .length,
          reason: entry.key,
        );
      }
      expect(counts.feeBands.values.fold(0, (a, b) => a + b), 4);
    });

    // @lat: [[tests#Catalogue filter#Options stay listed at zero and follow a fixed order]]
    test('lists every option, zero counts included, in a fixed order', () {
      final counts = facetCounts(
        cardTemplates,
        const CatalogFilter().toggleIssuer('Wells Fargo'),
      );
      expect(counts.feeBands.keys, FeeBand.values);
      expect(counts.feeBands[FeeBand.from600], 0);
      expect(counts.networks.keys, [
        CardNetwork.amex,
        CardNetwork.visa,
        CardNetwork.mastercard,
      ]);
      expect(counts.networks[CardNetwork.amex], 0);
      expect(counts.issuers.keys, [
        'American Express',
        'Bank of America',
        'Capital One',
        'Chase',
        'Citi',
        'Wells Fargo',
      ]);
      final merchants = counts.merchants.keys.toList();
      expect(merchants, contains('Uber'));
      expect(merchants, contains('lululemon'));
      expect(merchants.toSet(), hasLength(merchants.length));
      expect(
        merchants,
        [...merchants]
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())),
      );
      expect(counts.merchants['Uber'], 0);
    });
  });

  group('sortByValue', () {
    // @lat: [[tests#Catalogue filter#The catalogue sorts by annual value, ties in catalogue order]]
    test('puts the highest annual value first and keeps ties in order', () {
      final sorted = sortByValue([
        _template('low', benefits: [_credit('a', valueCents: 100)]),
        _template('tie-1', benefits: [_credit('a', valueCents: 500)]),
        _template('high', benefits: [_credit('a', valueCents: 900)]),
        _template('tie-2', benefits: [_credit('a', valueCents: 500)]),
      ]);
      expect(_ids(sorted), ['high', 'tie-1', 'tie-2', 'low']);
      final real = sortByValue(cardTemplates);
      for (var i = 1; i < real.length; i++) {
        expect(
          templateAnnualValueCents(real[i - 1]),
          greaterThanOrEqualTo(templateAnnualValueCents(real[i])),
        );
      }
    });
  });

  group('the filter value', () {
    // @lat: [[tests#Catalogue filter#The active count leaves out the search text]]
    test('counts selected values, not the search text', () {
      const empty = CatalogFilter();
      expect(empty.isEmpty, isTrue);
      expect(empty.activeCount, 0);
      final some = empty
          .toggleIssuer('Chase')
          .toggleFeeBand(FeeBand.from600)
          .copyWith(search: 'uber');
      expect(some.activeCount, 2);
      expect(some.isEmpty, isFalse);
      expect(const CatalogFilter(search: 'x').isEmpty, isFalse);
      expect(some.toggleIssuer('Chase').activeCount, 1);
    });
  });

  group('matchedBenefits', () {
    // @lat: [[tests#Catalogue filter#Matched benefits come from the merchant or the search]]
    test('names the benefits a merchant or the search matched', () {
      final platinum = findTemplate('amex-platinum')!;
      expect(matchedBenefits(platinum, const CatalogFilter()), isEmpty);
      final byMerchant = matchedBenefits(
        platinum,
        const CatalogFilter().toggleMerchant('Uber'),
      );
      expect(byMerchant, isNotEmpty);
      expect(byMerchant.every((b) => b.merchant == 'Uber'), isTrue);
      final bySearch = matchedBenefits(
        platinum,
        const CatalogFilter(search: 'resy'),
      );
      expect(bySearch.map((b) => b.merchant).toSet(), {'Resy'});
      expect(
        matchedBenefits(platinum, const CatalogFilter(search: 'platinum')),
        isEmpty,
      );
    });
  });
}
