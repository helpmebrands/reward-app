import 'package:domain/domain.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:go_router/go_router.dart';

import '../logic/app_store.dart';
import '../logic/ui_state.dart';
import '../shell/router.dart';
import '../theme/nocturne_tokens.dart';
import '../widgets/screen_title.dart';

/// "Change the terms" on a card the catalogue keeps up to date. Nothing
/// changes until the person confirms: the screen says the card will be
/// replaced by one they maintain themselves, that it will no longer update
/// automatically, and that it keeps its claims and history. Confirming
/// converts it and opens the new card's editor.
class ConvertScreen extends StatefulWidget {
  const ConvertScreen({
    super.key,
    required this.store,
    required this.cardId,
    this.ui,
  });

  final AppStore store;
  final String cardId;
  final UiState? ui;

  @override
  State<ConvertScreen> createState() => _ConvertScreenState();
}

class _ConvertScreenState extends State<ConvertScreen> {
  bool _busy = false;

  Future<void> _convert() async {
    setState(() => _busy = true);
    final newId = await widget.store.convertCard(widget.cardId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (newId == null) return;
    widget.ui?.snackbar.show('The card is yours to edit now.');
    context.go(cardPath(newId));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    final text = Theme.of(context).textTheme;
    Card? card;
    for (final c in widget.store.data?.cards ?? const <Card>[]) {
      if (c.id == widget.cardId) card = c;
    }
    final name = card == null ? 'This card' : cardLabel(card);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(cardPath(widget.cardId)),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Space.s6),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ScreenTitle(
                    label: 'Change the terms',
                    style: text.headlineSmall,
                  ),
                  const SizedBox(height: Space.s4),
                  Text(
                    '$name follows the catalogue: when the issuer changes its '
                    'credits, the card changes with it.',
                    style: text.bodyMedium,
                  ),
                  const SizedBox(height: Space.s4),
                  Text(
                    'To change its terms yourself, it will be replaced by a '
                    'card you maintain. That card will no longer update '
                    'automatically. It keeps its claims, its history, its '
                    'enrolment and everyone’s silences.',
                    style: text.bodyMedium?.copyWith(
                      color: tokens.textSecondary,
                    ),
                  ),
                  const SizedBox(height: Space.s8),
                  FilledButton(
                    key: const Key('convert-confirm'),
                    onPressed: _busy || card == null ? null : _convert,
                    child: const Text('Make it mine'),
                  ),
                  const SizedBox(height: Space.s2),
                  TextButton(
                    onPressed: () => context.go(cardPath(widget.cardId)),
                    child: const Text('Keep it up to date'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
