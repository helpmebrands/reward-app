import 'package:domain/domain.dart';
import 'package:flutter/material.dart';

import '../logic/sample_household.dart';
import '../theme/nocturne_tokens.dart';
import '../widgets/credit_row.dart';
import '../widgets/today_headline.dart';

/// The sample household's current credits, less those opted out of, as
/// Today lists them.
List<BenefitInstance> _sampleInstances() => [
  for (final instance in currentInstances(sampleHousehold(), sampleToday))
    if (instance.status != BenefitStatus.optedOut) instance,
];

/// Slide one's picture: Today's headline over the sample household and its
/// first rows, soonest first, then available, then locked.
class UpcomingRewardsHero extends StatelessWidget {
  const UpcomingRewardsHero({super.key});

  @override
  Widget build(BuildContext context) {
    final instances = _sampleInstances();
    final rows = [
      ...byStatus(instances, BenefitStatus.useSoon),
      ...byStatus(instances, BenefitStatus.available),
      ...byStatus(instances, BenefitStatus.locked),
    ].take(4);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TodayHeadline(
            heading: false,
            eyebrow: todayEyebrow(sampleToday),
            claimableCents: totalsFor(instances, 0).claimableCents,
            sub: todayHeadlineSub(
              open: instances.where(isClaimable).length,
              cards: sampleHousehold().cards.length,
              resetOn: nextReset(instances),
            ),
          ),
          for (final instance in rows) ...[
            const SizedBox(height: Space.s2),
            CreditRow(instance: instance, showCard: true),
          ],
        ],
      ),
    );
  }
}
