import 'package:flutter/material.dart';

import '../theme/nocturne_tokens.dart';

/// A titled switch on a quiet panel, the PWA's `panel row` with a `Switch`:
/// the title and the note for the eye, one label for the screen reader.
/// The whole row is the target, and a null [onChanged] disables all of it.
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

  /// Null disables the switch, as for a term the catalogue owns.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    final text = Theme.of(context).textTheme;
    final onChanged = this.onChanged;
    // One target and one node: the whole row flips the switch, and the
    // screen reader hears the label, the note and the state together.
    return MergeSemantics(
      child: Semantics(
        label: label,
        hint: note,
        child: Material(
          color: tokens.surfaceQuiet,
          shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.all(Radius.circular(Radii.md)),
            side: BorderSide(color: tokens.surfaceLine),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onChanged == null ? null : () => onChanged(!value),
            child: Padding(
              padding: const EdgeInsets.all(Space.s4),
              child: Row(
                children: [
                  Expanded(
                    child: ExcludeSemantics(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: text.bodyMedium),
                          Text(
                            note,
                            style: text.bodySmall?.copyWith(
                              color: tokens.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: Space.s3),
                  Switch(value: value, onChanged: onChanged),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
