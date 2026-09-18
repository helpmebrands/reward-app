/// The tiered reminder ladder.
///
/// A monthly $15 credit and an annual $300 one cannot share a reminder
/// schedule: warn about the monthly one 90 days out and it is noise, warn
/// about the annual one only on the last day and it is too late to book
/// anything. So each cadence gets its own rungs, and the tone climbs along
/// them: the first rung is a permissive "you can use me", the last is a last
/// call.
///
/// These are the presets from the design. A user can opt one credit out with
/// [Benefit.lastCallOnly].
library;

import 'types.dart';

const Map<Cadence, List<LadderRung>> _ladders = {
  Cadence.monthly: [
    // Day 7 of a ~30-day window, expressed as days remaining.
    LadderRung(daysBefore: 23, label: 'You can use me', tone: Tone.permissive),
    LadderRung(daysBefore: 7, label: 'One week left', tone: Tone.notice),
    LadderRung(daysBefore: 0, label: 'Expires tonight', tone: Tone.urgent),
  ],
  Cadence.quarterly: [
    LadderRung(daysBefore: 30, label: 'You can use me', tone: Tone.permissive),
    LadderRung(daysBefore: 14, label: 'Two weeks left', tone: Tone.notice),
    LadderRung(daysBefore: 3, label: 'Expires this week', tone: Tone.urgent),
  ],
  Cadence.semiannual: [
    LadderRung(daysBefore: 60, label: 'You can use me', tone: Tone.permissive),
    LadderRung(daysBefore: 21, label: 'Three weeks left', tone: Tone.notice),
    LadderRung(daysBefore: 7, label: 'Final week', tone: Tone.urgent),
  ],
  Cadence.annual: [
    LadderRung(
      daysBefore: 180,
      label: 'Half the year gone',
      tone: Tone.permissive,
    ),
    LadderRung(daysBefore: 90, label: 'Plan it now', tone: Tone.notice),
    LadderRung(daysBefore: 30, label: 'Urgent', tone: Tone.urgent),
    LadderRung(daysBefore: 7, label: 'Final week', tone: Tone.urgent),
  ],
  // Untracked credits get one rung and it is the user's own review, not a
  // deadline the app invented.
  Cadence.manual: [
    LadderRung(daysBefore: 0, label: 'Tracked manually', tone: Tone.permissive),
  ],
};

/// The rungs that apply to one credit.
List<LadderRung> ladderFor(Benefit benefit) {
  final rungs = _ladders[benefit.cadence]!;
  if (benefit.lastCallOnly) return rungs.isEmpty ? const [] : [rungs.last];
  return rungs;
}

/// The default ladder for a cadence, for the settings screen's preview.
List<LadderRung> defaultLadder(Cadence cadence) => _ladders[cadence]!;

/// A short description of a cadence's ladder, e.g. "30 · 14 · 3".
String ladderSummary(Cadence cadence) {
  return _ladders[cadence]!
      .map((rung) => rung.daysBefore == 0 ? 'last day' : '${rung.daysBefore}')
      .join(' · ');
}

/// Which rung a credit is currently standing on, or null before the first one
/// has been reached. Drives the tone of the row and of the notification copy.
LadderRung? currentRung(Benefit benefit, int daysRemaining) {
  LadderRung? reached;
  for (final rung in ladderFor(benefit)) {
    if (daysRemaining <= rung.daysBefore) reached = rung;
  }
  return reached;
}
