/// The next day a credit window opens, which Today names once nothing is
/// left to claim.
library;

import 'cycles.dart';
import 'dates.dart';
import 'selectors.dart';
import 'types.dart';

/// The day the next window opens and the credits that open on it.
class NextOpening {
  const NextOpening({required this.on, required this.benefits});

  final IsoDate on;

  /// In the household's benefit order.
  final List<Benefit> benefits;

  /// The full value of every credit opening that day.
  int get valueCents => benefits.fold(0, (sum, b) => sum + b.valueCents);
}

/// The earliest day after [today] on which a credit's next window opens, or
/// null when none will. Opted-out credits, credits on archived cards, credits
/// that end first and credits still locked on that day are skipped.
NextOpening? nextOpening(AppData data, IsoDate today) {
  final cardsById = {for (final card in data.cards) card.id: card};
  IsoDate? earliest;
  final benefits = <Benefit>[];

  for (final benefit in data.benefits) {
    if (!benefit.active || benefit.optedOutAt != null) continue;
    final card = cardsById[benefit.cardId];
    if (card == null || card.archived) continue;
    final cycle = cycleFor(benefit, card, today, claims: data.claims);
    // No window, or a rolling one that only a claim can close.
    if (cycle == null || cycle.end == '2999-12-31') continue;
    final start = addDays(cycle.end, 1);
    if (hasEnded(benefit, start) || isLocked(benefit, card, start)) continue;

    final order = earliest == null ? -1 : compareIsoDate(start, earliest);
    if (order < 0) {
      earliest = start;
      benefits.clear();
    }
    if (order <= 0) benefits.add(benefit);
  }

  return earliest == null
      ? null
      : NextOpening(on: earliest, benefits: benefits);
}
