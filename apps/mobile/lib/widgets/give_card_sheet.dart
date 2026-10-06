import 'package:flutter/material.dart';

import '../data/household_api.dart';
import '../theme/nocturne_tokens.dart';

/// The people a card is shared with, to hand it to one of them; pops the
/// [Person] chosen.
class GiveCardSheet extends StatelessWidget {
  const GiveCardSheet({
    super.key,
    required this.cardName,
    required this.people,
  });

  final String cardName;
  final List<Person> people;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Give $cardName to', style: text.titleMedium),
            const SizedBox(height: Space.s1),
            Text(
              'They’ll own it and change it, and you’ll still see it and log '
              'what you use.',
              style: text.bodySmall?.copyWith(color: tokens.textSecondary),
            ),
            const SizedBox(height: Space.s3),
            for (final person in people)
              ListTile(
                key: ValueKey('give-${person.id}'),
                contentPadding: EdgeInsets.zero,
                title: Text(person.displayName),
                subtitle: person.name != null && person.email != null
                    ? Text(person.email!)
                    : null,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).pop(person),
              ),
          ],
        ),
      ),
    );
  }
}
