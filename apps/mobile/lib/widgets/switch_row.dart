import 'package:flutter/material.dart';

import '../theme/nocturne_tokens.dart';

/// A titled switch on a quiet panel, the PWA's `panel row` with a `Switch`:
/// the title and the note for the eye, one label for the screen reader.
class SwitchRow extends StatelessWidget {
  const SwitchRow({
    super.key,
    required this.title,
    required this.note,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String note;

  /// What the screen reader hears for the switch itself.
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(Space.s4),
      decoration: BoxDecoration(
        color: tokens.surfaceQuiet,
        borderRadius: const BorderRadius.all(Radius.circular(Radii.md)),
        border: Border.all(color: tokens.surfaceLine),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.bodyMedium),
                Text(
                  note,
                  style: text.bodySmall?.copyWith(color: tokens.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.s3),
          MergeSemantics(
            child: Semantics(
              label: label,
              child: Switch(value: value, onChanged: onChanged),
            ),
          ),
        ],
      ),
    );
  }
}
