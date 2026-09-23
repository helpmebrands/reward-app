import 'package:domain/domain.dart';
import 'package:flutter/material.dart';

import '../logic/catalog_filter_controller.dart';
import '../screens/card_editor_screen.dart' show networkLabel;
import '../theme/nocturne_tokens.dart';

/// The catalogue's filters: the search, then one group of checkboxes per
/// facet with each option's count. The side panel from medium width up and
/// the compact sheet show this same widget.
class CatalogFilterPanel extends StatefulWidget {
  const CatalogFilterPanel({
    super.key,
    required this.controller,
    this.padding = EdgeInsets.zero,
  });

  final CatalogFilterController controller;
  final EdgeInsetsGeometry padding;

  @override
  State<CatalogFilterPanel> createState() => _CatalogFilterPanelState();
}

/// Merchants listed before "Show all".
const _merchantsShown = 6;

class _CatalogFilterPanelState extends State<CatalogFilterPanel> {
  bool _showAllMerchants = false;

  CatalogFilterController get c => widget.controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final filter = c.filter;
        final counts = c.counts;
        final query = c.merchantQuery.trim().toLowerCase();
        final merchants = [
          for (final m in counts.merchants.keys)
            if (query.isEmpty || m.toLowerCase().contains(query)) m,
        ];
        final listed = query.isEmpty && !_showAllMerchants
            ? merchants.take(_merchantsShown)
            : merchants;
        return ListView(
          padding: widget.padding,
          children: [
            TextField(
              key: const Key('catalog-search'),
              controller: c.search,
              decoration: const InputDecoration(
                labelText: 'Search cards',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            _Heading('Annual fee'),
            for (final band in FeeBand.values)
              _Option(
                id: 'fee-${band.name}',
                label: band.label,
                count: counts.feeBands[band]!,
                selected: filter.feeBands.contains(band),
                onToggle: () => c.update((f) => f.toggleFeeBand(band)),
              ),
            _Heading('Network'),
            for (final MapEntry(key: network, value: count)
                in counts.networks.entries)
              _Option(
                id: 'network-${network.name}',
                label: networkLabel(network),
                count: count,
                selected: filter.networks.contains(network),
                onToggle: () => c.update((f) => f.toggleNetwork(network)),
              ),
            _Heading('Issuer'),
            for (final MapEntry(key: issuer, value: count)
                in counts.issuers.entries)
              _Option(
                id: 'issuer-$issuer',
                label: issuer,
                count: count,
                selected: filter.issuers.contains(issuer),
                onToggle: () => c.update((f) => f.toggleIssuer(issuer)),
              ),
            _Heading('Benefit merchant'),
            TextField(
              key: const Key('merchant-search'),
              controller: c.merchantSearch,
              decoration: const InputDecoration(
                labelText: 'Find a merchant',
                isDense: true,
              ),
            ),
            for (final merchant in listed)
              _Option(
                id: 'merchant-$merchant',
                label: merchant,
                count: counts.merchants[merchant]!,
                selected: filter.merchants.contains(merchant),
                onToggle: () => c.update((f) => f.toggleMerchant(merchant)),
              ),
            if (query.isEmpty && merchants.length > _merchantsShown)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: () =>
                      setState(() => _showAllMerchants = !_showAllMerchants),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    visualDensity: VisualDensity.standard,
                  ),
                  child: Text(_showAllMerchants ? 'Show fewer' : 'Show all'),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Space.s6, bottom: Space.s2),
    child: Semantics(
      header: true,
      child: Text(label, style: Theme.of(context).textTheme.titleSmall),
    ),
  );
}

/// One checkbox with its count on the right. An option no card would match
/// is dimmed but stays selectable; once checked it is drawn in full.
class _Option extends StatelessWidget {
  const _Option({
    required this.id,
    required this.label,
    required this.count,
    required this.selected,
    required this.onToggle,
  });

  final String id;
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    final text = Theme.of(context).textTheme;
    return Opacity(
      opacity: count == 0 && !selected ? 0.5 : 1,
      child: CheckboxListTile(
        key: ValueKey('facet-$id'),
        value: selected,
        onChanged: (_) => onToggle(),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        title: Row(
          children: [
            Expanded(child: Text(label, style: text.bodyMedium)),
            const SizedBox(width: Space.s3),
            Text(
              '$count',
              style: text.bodySmall?.copyWith(color: tokens.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
