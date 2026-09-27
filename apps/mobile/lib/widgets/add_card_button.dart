import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../logic/app_store.dart';
import '../shell/router.dart';

/// The empty states' one filled button: pushes the catalogue, so Back
/// returns to the tab it was tapped on.
///
/// It reads "Add your first card" in a household that never had one and
/// "Add a card" when only archived cards remain, and a reader, who cannot
/// add, gets nothing.
class AddCardButton extends StatelessWidget {
  const AddCardButton({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    if (!store.canWrite) return const SizedBox.shrink();
    final first = store.data?.cards.isEmpty ?? true;
    return FilledButton(
      key: const Key('empty-add-card'),
      onPressed: () => context.push(Paths.newCard),
      child: Text(first ? 'Add your first card' : 'Add a card'),
    );
  }
}
