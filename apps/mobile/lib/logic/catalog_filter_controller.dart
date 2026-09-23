import 'package:domain/domain.dart';
import 'package:flutter/widgets.dart';

/// The add-card catalogue's filter: the selected facet values, the search
/// text and the merchant sub-search. The screen owns it, so leaving the
/// screen resets it, and it is never written to the URL.
///
/// The two text controllers live here rather than in the panel so the side
/// panel and the compact sheet share one caret and "Clear all" can empty
/// them.
class CatalogFilterController extends ChangeNotifier {
  CatalogFilterController() {
    search.addListener(_searchChanged);
    merchantSearch.addListener(_merchantSearchChanged);
  }

  final search = TextEditingController();

  /// Narrows the merchant options only; it never filters cards.
  final merchantSearch = TextEditingController();

  CatalogFilter _filter = const CatalogFilter();
  String _merchantQuery = '';

  CatalogFilter get filter => _filter;
  String get merchantQuery => _merchantQuery;

  /// The cards the filter keeps, highest annual value first.
  List<CardTemplate> get results =>
      sortByValue(filterTemplates(cardTemplates, _filter));

  /// Every card the catalogue lists, for "N of 16 cards".
  int get total => filterTemplates(cardTemplates, const CatalogFilter()).length;

  FacetCounts get counts => facetCounts(cardTemplates, _filter);

  void update(CatalogFilter Function(CatalogFilter filter) change) {
    _filter = change(_filter);
    notifyListeners();
  }

  /// Every facet, the search and the merchant sub-search.
  void clear() {
    _filter = const CatalogFilter();
    _merchantQuery = '';
    search.clear();
    merchantSearch.clear();
    notifyListeners();
  }

  // A controller also notifies on caret moves; only text changes count.
  void _searchChanged() {
    if (search.text == _filter.search) return;
    _filter = _filter.copyWith(search: search.text);
    notifyListeners();
  }

  void _merchantSearchChanged() {
    if (merchantSearch.text == _merchantQuery) return;
    _merchantQuery = merchantSearch.text;
    notifyListeners();
  }

  @override
  void dispose() {
    search.dispose();
    merchantSearch.dispose();
    super.dispose();
  }
}
