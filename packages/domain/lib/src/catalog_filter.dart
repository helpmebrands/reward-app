/// Filtering and ordering the card catalogue behind "Add a card".
///
/// Values within a facet are OR-ed; facets are AND-ed with each other and
/// with the search text. The blank template is never a result: it is the
/// manual-entry path, reached from its own buttons.
library;

import 'catalog.dart';
import 'types.dart';

/// Annual fee bands, with their inclusive cent ranges.
enum FeeBand {
  none('No fee', 0, 0),
  under100('Under \$100', 1, 9999),
  from100('\$100–\$399', 10000, 39999),
  from400('\$400–\$599', 40000, 59999),
  from600('\$600+', 60000, null);

  const FeeBand(this.label, this.minCents, this.maxCents);

  final String label;
  final int minCents;

  /// Null for the open-ended top band.
  final int? maxCents;

  bool contains(int cents) =>
      cents >= minCents && (maxCents == null || cents <= maxCents!);

  static FeeBand of(int cents) => values.firstWhere((b) => b.contains(cents));
}

/// The selected values of each facet, plus the search text.
class CatalogFilter {
  const CatalogFilter({
    this.feeBands = const {},
    this.networks = const {},
    this.issuers = const {},
    this.merchants = const {},
    this.search = '',
  });

  final Set<FeeBand> feeBands;
  final Set<CardNetwork> networks;
  final Set<String> issuers;
  final Set<String> merchants;
  final String search;

  /// Selected values across every facet. The search text is not counted.
  int get activeCount =>
      feeBands.length + networks.length + issuers.length + merchants.length;

  bool get isEmpty => activeCount == 0 && search.trim().isEmpty;

  CatalogFilter copyWith({
    Set<FeeBand>? feeBands,
    Set<CardNetwork>? networks,
    Set<String>? issuers,
    Set<String>? merchants,
    String? search,
  }) => CatalogFilter(
    feeBands: feeBands ?? this.feeBands,
    networks: networks ?? this.networks,
    issuers: issuers ?? this.issuers,
    merchants: merchants ?? this.merchants,
    search: search ?? this.search,
  );

  CatalogFilter toggleFeeBand(FeeBand band) =>
      copyWith(feeBands: _toggled(feeBands, band));
  CatalogFilter toggleNetwork(CardNetwork network) =>
      copyWith(networks: _toggled(networks, network));
  CatalogFilter toggleIssuer(String issuer) =>
      copyWith(issuers: _toggled(issuers, issuer));
  CatalogFilter toggleMerchant(String merchant) =>
      copyWith(merchants: _toggled(merchants, merchant));

  bool _matchesFee(CardTemplate t) =>
      feeBands.isEmpty || feeBands.any((b) => b.contains(t.annualFeeCents));
  bool _matchesNetwork(CardTemplate t) =>
      networks.isEmpty || networks.contains(t.network);
  bool _matchesIssuer(CardTemplate t) =>
      issuers.isEmpty || issuers.contains(t.issuer);
  bool _matchesMerchant(CardTemplate t) =>
      merchants.isEmpty ||
      t.benefits.any((b) => merchants.contains(b.merchant));

  bool _matchesSearch(CardTemplate t) {
    final query = _query;
    if (query.isEmpty) return true;
    return t.issuer.toLowerCase().contains(query) ||
        t.product.toLowerCase().contains(query) ||
        t.benefits.any((b) => _benefitMatchesSearch(b, query));
  }

  String get _query => search.trim().toLowerCase();
}

Set<T> _toggled<T>(Set<T> values, T value) =>
    values.contains(value) ? ({...values}..remove(value)) : {...values, value};

bool _benefitMatchesSearch(BenefitTemplate b, String query) =>
    b.name.toLowerCase().contains(query) ||
    (b.merchant ?? '').toLowerCase().contains(query);

Iterable<CardTemplate> _listable(List<CardTemplate> templates) =>
    templates.where((t) => t.id != 'blank');

/// The templates the filter keeps, in their given order, never `blank`.
List<CardTemplate> filterTemplates(
  List<CardTemplate> templates,
  CatalogFilter filter,
) => _listable(templates)
    .where(
      (t) =>
          filter._matchesFee(t) &&
          filter._matchesNetwork(t) &&
          filter._matchesIssuer(t) &&
          filter._matchesMerchant(t) &&
          filter._matchesSearch(t),
    )
    .toList();

/// Highest annual benefit value first; equal values keep their order.
List<CardTemplate> sortByValue(List<CardTemplate> templates) {
  final indexed = templates.indexed.toList()
    ..sort((a, b) {
      final byValue = templateAnnualValueCents(
        b.$2,
      ).compareTo(templateAnnualValueCents(a.$2));
      return byValue != 0 ? byValue : a.$1.compareTo(b.$1);
    });
  return [for (final (_, t) in indexed) t];
}

/// For each option of each facet, the number of cards selecting it would
/// return: every other facet and the search apply, the facet's own
/// selection does not. Map order is display order, and an option stays
/// listed at zero.
class FacetCounts {
  const FacetCounts({
    required this.feeBands,
    required this.networks,
    required this.issuers,
    required this.merchants,
  });

  /// Every band, in band order.
  final Map<FeeBand, int> feeBands;

  /// Networks present in the catalogue, in enum order.
  final Map<CardNetwork, int> networks;

  /// Issuers, alphabetical.
  final Map<String, int> issuers;

  /// Non-empty merchants, alphabetical ignoring case.
  final Map<String, int> merchants;
}

FacetCounts facetCounts(List<CardTemplate> templates, CatalogFilter filter) {
  final all = _listable(templates).toList();
  final present = all.map((t) => t.network).toSet();
  final issuers = all.map((t) => t.issuer).toSet().toList()..sort();
  final merchants = {
    for (final t in all)
      for (final b in t.benefits)
        if ((b.merchant ?? '').isNotEmpty) b.merchant!,
  }.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  int count(CatalogFilter without, bool Function(CardTemplate) option) =>
      filterTemplates(all, without).where(option).length;

  final noFee = filter.copyWith(feeBands: const {});
  final noNetwork = filter.copyWith(networks: const {});
  final noIssuer = filter.copyWith(issuers: const {});
  final noMerchant = filter.copyWith(merchants: const {});
  return FacetCounts(
    feeBands: {
      for (final band in FeeBand.values)
        band: count(noFee, (t) => band.contains(t.annualFeeCents)),
    },
    networks: {
      for (final network in CardNetwork.values)
        if (present.contains(network))
          network: count(noNetwork, (t) => t.network == network),
    },
    issuers: {
      for (final issuer in issuers)
        issuer: count(noIssuer, (t) => t.issuer == issuer),
    },
    merchants: {
      for (final merchant in merchants)
        merchant: count(
          noMerchant,
          (t) => t.benefits.any((b) => b.merchant == merchant),
        ),
    },
  );
}

/// The benefits in [template] that a selected merchant or the search text
/// matched; empty when neither applies.
List<BenefitTemplate> matchedBenefits(
  CardTemplate template,
  CatalogFilter filter,
) {
  final query = filter._query;
  if (filter.merchants.isEmpty && query.isEmpty) return const [];
  return template.benefits
      .where(
        (b) =>
            filter.merchants.contains(b.merchant) ||
            (query.isNotEmpty && _benefitMatchesSearch(b, query)),
      )
      .toList();
}
