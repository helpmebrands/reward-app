import 'package:flutter/material.dart';

import '../shell/width_class.dart';
import '../theme/nocturne_tokens.dart';

/// A destination whose screen has not arrived yet: its heading, so the
/// shell's branches are real, and one line saying so.
class StubScreen extends StatelessWidget {
  const StubScreen(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.all(WidthClass.of(context).padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(header: true, child: Text(title, style: text.titleMedium)),
          const SizedBox(height: Space.s3),
          Text(
            'This screen arrives with a later issue.',
            style: text.bodyMedium?.copyWith(color: tokens.textSecondary),
          ),
        ],
      ),
    );
  }
}
