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

String kindLabel(CardKind kind) => switch (kind) {
  CardKind.personal => 'Personal',
  CardKind.business => 'Business',
};

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
            _Heading('Card kind'),
            for (final MapEntry(key: kind, value: count)
                in counts.kinds.entries)
              _Option(
                id: 'kind-${kind.name}',
                label: kindLabel(kind),
                count: count,
                selected: filter.kinds.contains(kind),
                onToggle: () => c.update((f) => f.toggleKind(kind)),
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

/// The compact catalogue's filters: the same panel in a modal bottom sheet
/// at most 80% of the height. Filters apply behind the scrim as they are
/// checked; "Show N" only closes the sheet.
Future<void> showCatalogFilterSheet(
  BuildContext context,
  CatalogFilterController controller,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  constraints: BoxConstraints(
    maxHeight: MediaQuery.sizeOf(context).height * 0.8,
  ),
  builder: (context) => CatalogFilterSheet(controller: controller),
);

class CatalogFilterSheet extends StatelessWidget {
  const CatalogFilterSheet({super.key, required this.controller});

  final CatalogFilterController controller;

  @override
  Widget build(BuildContext context) {
    // Growing past compact hands over to the side panel, which reads the
    // same controller.
    if (MediaQuery.sizeOf(context).width >= 600) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final route = context.mounted ? ModalRoute.of(context) : null;
        if (route != null && route.isCurrent) Navigator.of(context).pop();
      });
    }
    return Column(
      key: const Key('filter-sheet'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, Space.s4, 20, Space.s2),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    'Filters',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
              ListenableBuilder(
                listenable: controller,
                builder: (context, _) => FilledButton(
                  key: const Key('show-results'),
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    visualDensity: VisualDensity.standard,
                  ),
                  child: Text('Show ${controller.results.length}'),
                ),
              ),
            ],
          ),
        ),
        Flexible(
          child: CatalogFilterPanel(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          ),
        ),
      ],
    );
  }
}
