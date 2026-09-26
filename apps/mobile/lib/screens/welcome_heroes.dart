import 'package:domain/domain.dart';
import 'package:flutter/material.dart';

import '../logic/sample_household.dart';
import '../theme/nocturne_tokens.dart' hide Tone;
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

/// Slide two's picture: a notification lookalike carrying the first
/// one-week reminder the sample household gets, its title and body from
/// `buildSchedule` (default preferences, reminders on) so the slide follows
/// the real copy, above the row of the credit it leads with.
class TimelyRemindersHero extends StatelessWidget {
  const TimelyRemindersHero({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    final text = Theme.of(context).textTheme;
    final reminder = buildSchedule(
      sampleHousehold(),
      defaultMemberPreferences.copyWith(enabled: true),
      sampleClock,
    ).reminders.firstWhere((r) => r.tone == Tone.notice);
    final biggest = _sampleInstances().firstWhere(
      (i) => i.benefit.id == reminder.items.first.benefitId,
    );
    final secondary = text.labelSmall?.copyWith(color: tokens.textSecondary);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            key: const Key('welcome-notification'),
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
                    // The app icon's place in a system notification.
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: tokens.accent,
                        borderRadius: BorderRadius.circular(Radii.sm),
                      ),
                    ),
                    const SizedBox(width: Space.s3),
                    Expanded(child: Text('HelpMe Reward', style: secondary)),
                    Text('now', style: secondary),
                  ],
                ),
                const SizedBox(height: Space.s3),
                Text(reminder.title, style: text.titleSmall),
                const SizedBox(height: Space.s1),
                Text(reminder.body, style: text.bodySmall),
              ],
            ),
          ),
          const SizedBox(height: Space.s8),
          CreditRow(instance: biggest, showCard: true),
        ],
      ),
    );
  }
}
