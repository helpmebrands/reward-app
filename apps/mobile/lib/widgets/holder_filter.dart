import 'package:domain/domain.dart';
import 'package:flutter/material.dart';

import '../logic/app_store.dart';
import '../theme/nocturne_tokens.dart';

/// Narrows the screen to one member of the household: the PWA's
/// `HolderFilter` as a styled row over Material's popup menu, so the picker
/// is the platform's own rather than a custom dropdown.
///
/// The control hides itself when there is only one person, because a filter
/// with one option is furniture. The selection lives in the settings through
/// the store, as in the PWA, so Today and Credits share it.
class HolderFilter extends StatelessWidget {
  const HolderFilter({super.key, required this.store});

  final AppStore store;

  static const String everyone = 'Everyone in the household';

  @override
  Widget build(BuildContext context) {
    final data = store.data;
    if (data == null) return const SizedBox.shrink();
    final people = holders(data);
    if (people.length < 2) return const SizedBox.shrink();
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    final text = Theme.of(context).textTheme;
    final filter = data.settings.holderFilter;
    final count = store.instances.length;

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s6),
      child: Semantics(
        label: 'Filter by cardholder',
        child: PopupMenuButton<String>(
          key: const Key('holder-filter'),
          tooltip: 'Filter by cardholder',
          initialValue: filter,
          onSelected: (value) =>
              store.updateSettings((s) => s.copyWith(holderFilter: value)),
          itemBuilder: (context) => [
            const PopupMenuItem(value: '', child: Text(everyone)),
            for (final holder in people)
              PopupMenuItem(value: holder, child: Text(holder)),
          ],
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(
              horizontal: Space.s4,
              vertical: Space.s3,
            ),
            decoration: BoxDecoration(
              color: tokens.surfaceRaised,
              borderRadius: const BorderRadius.all(Radius.circular(Radii.md)),
              border: Border.all(color: tokens.controlBorder),
            ),
            child: Row(
              children: [
                Icon(Icons.people_outline, size: 16, color: tokens.accent),
                const SizedBox(width: Space.s3),
                Expanded(
                  child: Text(
                    filter.isEmpty ? everyone : filter,
                    style: text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: Space.s3),
                Text(
                  '$count credit${count == 1 ? '' : 's'}',
                  style: text.bodySmall?.copyWith(color: tokens.textSecondary),
                ),
                const SizedBox(width: Space.s2),
                Icon(Icons.expand_more, size: 16, color: tokens.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
