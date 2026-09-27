import 'package:domain/domain.dart';
import 'package:flutter/material.dart';

import '../theme/nocturne_tokens.dart';

/// "Notification levels": one member's choice of how much to hear about one
/// credit, Periodically, Last chance or Silence, with a line under it saying
/// what the selected level sends. The credit sheet and the credit editor
/// both show it.
class NotificationLevelControl extends StatelessWidget {
  const NotificationLevelControl({
    super.key,
    required this.benefit,
    required this.level,
    required this.onChanged,
    this.cardMuted = false,
  });

  final Benefit benefit;
  final NotificationLevel level;

  /// Null disables the control: a level in flight, or a silenced card.
  final ValueChanged<NotificationLevel>? onChanged;

  /// The whole card is silenced, so the credit is too whatever its level.
  final bool cardMuted;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    final text = Theme.of(context).textTheme;
    final onChanged = cardMuted ? null : this.onChanged;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text('Notification levels', style: text.titleSmall),
        ),
        const SizedBox(height: Space.s2),
        // A segment's label wraps onto a second line at a large text size
        // rather than overflowing.
        Semantics(
          label: 'Notification levels for ${benefit.name}',
          container: true,
          explicitChildNodes: true,
          child: SegmentedButton<NotificationLevel>(
            expandedInsets: EdgeInsets.zero,
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: NotificationLevel.periodically,
                label: Text('Periodically'),
              ),
              ButtonSegment(
                value: NotificationLevel.lastChance,
                label: Text('Last chance'),
              ),
              ButtonSegment(
                value: NotificationLevel.silenced,
                label: Text('Silence'),
              ),
            ],
            selected: {cardMuted ? NotificationLevel.silenced : level},
            onSelectionChanged: onChanged == null
                ? null
                : (next) => onChanged(next.single),
          ),
        ),
        const SizedBox(height: Space.s1),
        Text(
          cardMuted
              ? 'The whole card is silenced. Unsilence it on the card to choose.'
              : levelNote(benefit, level),
          style: text.bodySmall?.copyWith(color: tokens.textSecondary),
        ),
      ],
    );
  }
}
