import 'package:domain/domain.dart';
import 'package:flutter/material.dart';

import '../logic/sample_household.dart';
import '../theme/nocturne_tokens.dart' hide Tone;
import '../widgets/credit_row.dart';

// These are placeholders for the premium features (bank-linked tracking and
// AI insights), which do not exist yet. Replace them with the premium widgets
// once the premium epic builds those.

/// Slide three's picture: a credit marked used from a bank transaction, and
/// an insight card with one example of each kind of insight.
class PremiumFeaturesHero extends StatelessWidget {
  const PremiumFeaturesHero({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    final text = Theme.of(context).textTheme;
    final captured = currentInstances(
      sampleHousehold(),
      sampleToday,
    ).firstWhere((i) => i.status == BenefitStatus.captured);
    final secondary = text.labelSmall?.copyWith(color: tokens.textSecondary);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            key: const Key('premium-tracked-row'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CreditRow(instance: captured, showCard: true),
              const SizedBox(height: Space.s2),
              Row(
                children: [
                  Icon(
                    Icons.account_balance_outlined,
                    size: 14,
                    color: tokens.accent,
                  ),
                  const SizedBox(width: Space.s2),
                  Expanded(
                    child: Text(
                      'Tracked from your bank · Uber, Sep 10',
                      style: secondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: Space.s8),
          Container(
            key: const Key('premium-insights'),
            padding: const EdgeInsets.all(Space.s4),
            decoration: BoxDecoration(
              color: tokens.surfaceRaised,
              borderRadius: BorderRadius.circular(Radii.lg),
              border: Border.all(color: tokens.surfaceLine),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.auto_awesome, size: 16, color: tokens.accent),
                    const SizedBox(width: Space.s2),
                    Text('Insights', style: text.titleSmall),
                  ],
                ),
                const _Insight(
                  key: Key('premium-insight-earn'),
                  icon: Icons.trending_up,
                  text:
                      'Dining on Jim’s Platinum earned 1x this month. A '
                      'dining card would have earned 4x.',
                ),
                const _Insight(
                  key: Key('premium-insight-use'),
                  icon: Icons.swap_horiz,
                  text:
                      'Kathy’s Uber Cash is still open. Take this week’s '
                      'rides on her card.',
                ),
                const _Insight(
                  key: Key('premium-insight-missed'),
                  icon: Icons.history,
                  text: '\$20 of Resy Dining Credit lapsed in June.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Insight extends StatelessWidget {
  const _Insight({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    return Padding(
      padding: const EdgeInsets.only(top: Space.s4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: tokens.textSecondary),
          const SizedBox(width: Space.s3),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
