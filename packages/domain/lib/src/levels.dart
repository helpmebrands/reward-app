/// Notification levels: one member's choice of how much to hear about one
/// credit, shown as one control over two stored flags.
///
/// The level is Silence when the credit or its card is muted, else Last
/// chance when the credit is in [MemberPreferences.lastCallBenefitIds], else
/// Periodically. Silence leaves last-call as it was, so unsilencing returns
/// the credit to its earlier level.
library;

import 'ladder.dart';
import 'types.dart';

/// The level [prefs] give [benefit]. The household's [Benefit.lastCallOnly]
/// still reads as Last chance until it is removed (#362).
NotificationLevel levelFor(Benefit benefit, MemberPreferences prefs) {
  if (prefs.isMuted(benefit)) return NotificationLevel.silenced;
  if (benefit.lastCallOnly || prefs.lastCallBenefitIds.contains(benefit.id)) {
    return NotificationLevel.lastChance;
  }
  return NotificationLevel.periodically;
}

/// [prefs] with [benefitId] set to [level]: Periodically clears both flags,
/// Last chance sets last-call and clears the mute, Silence sets the mute and
/// keeps last-call.
MemberPreferences withLevel(
  MemberPreferences prefs,
  Uuid benefitId,
  NotificationLevel level,
) {
  final muted = {...prefs.mutedBenefitIds}..remove(benefitId);
  final lastCall = {...prefs.lastCallBenefitIds}..remove(benefitId);
  switch (level) {
    case NotificationLevel.periodically:
      break;
    case NotificationLevel.lastChance:
      lastCall.add(benefitId);
    case NotificationLevel.silenced:
      muted.add(benefitId);
      if (prefs.lastCallBenefitIds.contains(benefitId)) lastCall.add(benefitId);
  }
  return prefs.copyWith(mutedBenefitIds: muted, lastCallBenefitIds: lastCall);
}

/// One line saying what [level] sends for [benefit], from its cadence's
/// ladder: "23 days, 7 days and the last day before it shuts".
String levelNote(Benefit benefit, NotificationLevel level) {
  final rungs = defaultLadder(benefit.cadence);
  if (level == NotificationLevel.silenced) {
    return 'Keeps tracking it, sends nothing.';
  }
  if (benefit.cadence == Cadence.rolling || benefit.cadence == Cadence.manual) {
    return 'Sends nothing: ${rungs.last.label.toLowerCase()}.';
  }
  if (level == NotificationLevel.lastChance) {
    final last = rungs.last.daysBefore;
    return last == 0
        ? 'Only on the last day'
        : 'Only $last days before it shuts';
  }
  final parts = [
    for (final rung in rungs)
      rung.daysBefore == 0 ? 'the last day' : '${rung.daysBefore} days',
  ];
  final list = parts.length == 1
      ? parts.single
      : '${parts.take(parts.length - 1).join(', ')} and ${parts.last}';
  return '$list before it shuts';
}
