import 'package:domain/domain.dart';
import 'package:flutter/material.dart' hide Card;

import '../data/household_api.dart';
import '../theme/nocturne_tokens.dart';

/// What [ShareChoices] comes to: the access and the chosen cards (null for
/// all of them), or a request to stop sharing.
class ShareChoice {
  const ShareChoice({required this.access, this.cardIds}) : stop = false;

  const ShareChoice.stop()
    : access = CardAccess.view,
      cardIds = null,
      stop = true;

  final CardAccess access;

  /// Null shares every card, including ones added later.
  final List<String>? cardIds;
  final bool stop;
}

String accessLabel(CardAccess access) =>
    access == CardAccess.view ? 'View' : 'Can record usage';

/// "All cards" or "2 cards": how much a share covers.
String scopeLabel(bool allCards, int cards) =>
    allCards ? 'All cards' : '$cards card${cards == 1 ? '' : 's'}';

/// What a share lets the other person do, and which of your cards: view or
/// record usage, then all cards (the default, which includes cards added
/// later) or the ones ticked. Pops a [ShareChoice]; with [canStop] it also
/// offers "Stop sharing", which pops [ShareChoice.stop].
class ShareChoices extends StatefulWidget {
  const ShareChoices({
    super.key,
    required this.title,
    required this.cards,
    required this.action,
    this.access = CardAccess.view,
    this.cardIds,
    this.canStop = false,
  });

  final String title;

  /// Your own cards, the only ones a share can choose.
  final List<Card> cards;

  /// The button that pops the choice: "Create and share" or "Save".
  final String action;
  final CardAccess access;

  /// The chosen cards to start from; null starts from all of them.
  final List<String>? cardIds;
  final bool canStop;

  @override
  State<ShareChoices> createState() => _ShareChoicesState();
}

class _ShareChoicesState extends State<ShareChoices> {
  late CardAccess _access = widget.access;
  late bool _all = widget.cardIds == null;
  late final Set<String> _chosen = {...?widget.cardIds};
  String? _error;

  void _done() {
    if (!_all && _chosen.isEmpty) {
      setState(() => _error = 'Choose at least one card.');
      return;
    }
    Navigator.of(context).pop(
      ShareChoice(
        access: _access,
        cardIds: _all
            ? null
            : [
                for (final card in widget.cards)
                  if (_chosen.contains(card.id)) card.id,
              ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    final text = Theme.of(context).textTheme;
    final note = text.bodySmall?.copyWith(color: tokens.textSecondary);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: text.titleMedium),
            const SizedBox(height: Space.s4),
            Text('What they can do', style: note),
            const SizedBox(height: Space.s2),
            Semantics(
              label: 'What they can do',
              container: true,
              explicitChildNodes: true,
              child: SegmentedButton<CardAccess>(
                expandedInsets: EdgeInsets.zero,
                segments: [
                  for (final access in [CardAccess.view, CardAccess.record])
                    ButtonSegment(
                      value: access,
                      label: Text(accessLabel(access)),
                    ),
                ],
                selected: {_access},
                onSelectionChanged: (next) =>
                    setState(() => _access = next.single),
              ),
            ),
            const SizedBox(height: Space.s1),
            Text(
              _access == CardAccess.view
                  ? 'They see your cards and what you log.'
                  : 'They also log what they use and unlock credits. Only you '
                        'change the cards themselves.',
              style: note,
            ),
            const SizedBox(height: Space.s4),
            Text('Which cards', style: note),
            const SizedBox(height: Space.s2),
            Semantics(
              label: 'Which cards',
              container: true,
              explicitChildNodes: true,
              child: SegmentedButton<bool>(
                expandedInsets: EdgeInsets.zero,
                segments: const [
                  ButtonSegment(value: true, label: Text('All cards')),
                  ButtonSegment(value: false, label: Text('Chosen cards')),
                ],
                selected: {_all},
                onSelectionChanged: (next) => setState(() {
                  _all = next.single;
                  _error = null;
                }),
              ),
            ),
            const SizedBox(height: Space.s1),
            if (_all)
              Text('Cards you add later are shared too.', style: note)
            else ...[
              for (final card in widget.cards)
                CheckboxListTile(
                  key: ValueKey('share-card-${card.id}'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(cardLabel(card)),
                  value: _chosen.contains(card.id),
                  onChanged: (on) => setState(() {
                    on == true ? _chosen.add(card.id) : _chosen.remove(card.id);
                    _error = null;
                  }),
                ),
              if (_error case final error?)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    error,
                    style: text.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
            const SizedBox(height: Space.s6),
            FilledButton(
              key: const Key('share-done'),
              onPressed: _done,
              child: Text(widget.action),
            ),
            if (widget.canStop) ...[
              const SizedBox(height: Space.s2),
              TextButton(
                key: const Key('stop-sharing'),
                onPressed: () =>
                    Navigator.of(context).pop(const ShareChoice.stop()),
                child: const Text('Stop sharing'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
