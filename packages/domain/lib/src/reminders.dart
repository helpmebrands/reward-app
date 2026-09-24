/// Turning benefit cycles into a reminder schedule.
///
/// Deliberately pure: the schedule is computed here and handed to whatever
/// delivers it. That keeps the timing rules testable and means delivery needs
/// no domain knowledge.
library;

import 'cycles.dart';
import 'dates.dart';
import 'format.dart';
import 'ladder.dart';
import 'selectors.dart';
import 'types.dart';

class ReminderItem {
  const ReminderItem({
    required this.benefitId,
    required this.cycleKey,
    required this.benefitName,
    required this.cardName,
    this.merchant,
    required this.remainingCents,
    required this.endsOn,
    required this.locked,
  });

  final String benefitId;
  final IsoDate cycleKey;
  final String benefitName;
  final String cardName;
  final String? merchant;
  final int remainingCents;
  final IsoDate endsOn;
  final bool locked;
}

class Reminder {
  const Reminder({
    required this.id,
    required this.fireAt,
    required this.title,
    required this.body,
    required this.tag,
    required this.url,
    required this.items,
    required this.totalCents,
    required this.tone,
  });

  /// Stable across recomputes, so re-scheduling does not duplicate alerts.
  final String id;

  /// When to show it, as epoch milliseconds.
  final int fireAt;
  final String title;
  final String body;

  /// A newer reminder with the same tag replaces the older one.
  final String tag;

  /// Where tapping the notification should land.
  final String url;
  final List<ReminderItem> items;
  final int totalCents;
  final Tone tone;
}

class ReminderSchedule {
  const ReminderSchedule({required this.generatedAt, required this.reminders});

  final int generatedAt;
  final List<Reminder> reminders;
}

/// How far ahead to generate. Recomputed on each launch and daily by delivery.
const int horizonDays = 200;

class _Group {
  _Group({required this.fireAt, required this.rung});

  final int fireAt;
  final LadderRung rung;
  final List<ReminderItem> items = [];
}

/// A stable sort, matching the JavaScript reference.
List<T> _stableSorted<T>(Iterable<T> items, int Function(T a, T b) compare) {
  final indexed = items.toList().asMap().entries.toList()
    ..sort((a, b) {
      final order = compare(a.value, b.value);
      return order != 0 ? order : a.key - b.key;
    });
  return indexed.map((entry) => entry.value).toList();
}

/// Builds the reminder schedule.
///
/// Reminders are grouped by the day and rung they fire on, not emitted per
/// credit: a household with two premium cards can have a dozen credits lapsing
/// in the same week, and a dozen separate notifications is how an app gets
/// muted. The copy then leads with the single biggest loss, one decision per
/// notification.
///
/// The schedule is one member's: [prefs] carry their reminder settings and
/// mutes, so two members of one household get their own schedules.
ReminderSchedule buildSchedule(
  AppData data,
  MemberPreferences prefs, [
  DateTime? now,
  int horizon = horizonDays,
]) {
  final at = now ?? DateTime.now();
  final settings = prefs;
  final reminders = <Reminder>[];
  if (!settings.enabled) {
    return ReminderSchedule(
      generatedAt: at.millisecondsSinceEpoch,
      reminders: reminders,
    );
  }

  final from = todayIso(at);
  final until = addDays(from, horizon);
  final claims = indexClaims(data.claims);
  final cardsById = {for (final card in data.cards) card.id: card};
  final groups = <String, _Group>{};

  for (final benefit in data.benefits) {
    // A rolling credit has no deadline to warn about until the user claims
    // it, and then nothing to do until the interval runs out.
    if (!benefit.active ||
        benefit.cadence == Cadence.manual ||
        benefit.cadence == Cadence.rolling ||
        hasEnded(benefit, from)) {
      continue;
    }
    if (prefs.isMuted(benefit)) continue;
    final card = cardsById[benefit.cardId];
    if (card == null || card.archived) continue;
    if (benefit.valueCents < settings.minValueCents) continue;

    final reason = lockReason(benefit, card, from);
    // No reminder can unlock a spend threshold, so a gated credit gets none.
    if (reason == LockReason.spend) continue;
    final locked = reason != null;
    // A locked credit cannot be spent, so it is only worth a nudge if the user
    // asked to be told about enrolment; otherwise it is an impossible chore.
    if (locked && !settings.enrollmentReminder) continue;

    for (final cycle in cyclesBetween(benefit, card, from, until)) {
      final remainingCents =
          benefit.valueCents - claimedIn(claims, benefit.id, cycle.key);
      if (remainingCents <= 0) continue;

      for (final rung in ladderFor(benefit)) {
        final fireOn = addDays(cycle.end, -rung.daysBefore);
        if (compareIsoDate(fireOn, from) < 0) continue;

        final fireAt = atLocalTime(
          fireOn,
          settings.timeOfDay,
        ).millisecondsSinceEpoch;
        if (fireAt <= at.millisecondsSinceEpoch) continue;

        final key = '$fireOn|${rung.tone.name}';
        final group = groups.putIfAbsent(
          key,
          () => _Group(fireAt: fireAt, rung: rung),
        );
        group.items.add(
          ReminderItem(
            benefitId: benefit.id,
            cycleKey: cycle.key,
            benefitName: benefit.name,
            cardName: cardLabel(card),
            merchant: benefit.merchant,
            remainingCents: remainingCents,
            endsOn: cycle.end,
            locked: locked,
          ),
        );
      }
    }
  }

  for (final entry in groups.entries) {
    final group = entry.value;
    final items = _stableSorted(
      group.items,
      (a, b) => b.remainingCents - a.remainingCents,
    );
    final totalCents = _sum(items);
    if (totalCents < settings.minValueCents) continue;
    reminders.add(
      Reminder(
        id: entry.key,
        fireAt: group.fireAt,
        tag: 'cardvantage-${entry.key}',
        url: '/?from=notification',
        title: _titleFor(items, totalCents, group.rung),
        body: _bodyFor(items, group.rung),
        items: items,
        totalCents: totalCents,
        tone: group.rung.tone,
      ),
    );
  }

  return ReminderSchedule(
    generatedAt: at.millisecondsSinceEpoch,
    reminders: _stableSorted(reminders, (a, b) => a.fireAt - b.fireAt),
  );
}

int _sum(List<ReminderItem> items) =>
    items.fold(0, (total, item) => total + item.remainingCents);

String _titleFor(List<ReminderItem> items, int totalCents, LadderRung rung) {
  final money = formatMoney(totalCents);
  final locked = items.where((item) => item.locked).toList();

  // When most of the money is behind an enrolment box, lead with the blocker:
  // telling someone to spend money they cannot reach is worse than silence.
  if (locked.isNotEmpty && _sum(locked) > totalCents / 2) {
    return '${formatMoney(_sum(locked))} is still locked';
  }

  return switch (rung.tone) {
    Tone.permissive => '$money just opened',
    Tone.notice => '$money on the line — ${rung.label.toLowerCase()}',
    Tone.urgent =>
      rung.daysBefore == 0
          ? '$money expires tonight'
          : '$money — ${rung.label}',
  };
}

String _bodyFor(List<ReminderItem> items, LadderRung rung) {
  if (items.isEmpty) return '';
  final first = items.first;

  final merchant = first.merchant;
  final where = merchant != null && merchant.isNotEmpty ? ' at $merchant' : '';
  final card = first.cardName;

  if (items.length == 1) {
    if (first.locked) {
      return '${first.benefitName} on $card needs enrolment before you can spend a cent of it.';
    }
    return '${first.benefitName}$where on $card. '
        '${formatMoney(first.remainingCents)} untouched.';
  }

  final rest = items.length - 1;
  final tail = 'and $rest other credit${rest == 1 ? '' : 's'}';
  if (rung.tone == Tone.permissive) {
    return '${first.benefitName} $tail reset overnight. Nothing is urgent yet.';
  }
  return '${first.benefitName} on $card is the largest untouched at '
      '${formatMoney(first.remainingCents)}, $tail.';
}

/// The reminders due now, given a schedule and the current time.
List<Reminder> dueReminders(
  ReminderSchedule schedule,
  int now,
  Set<String> alreadyShown, {
  int graceMs = 36 * 60 * 60 * 1000,
}) {
  return schedule.reminders
      .where(
        (reminder) =>
            !alreadyShown.contains(reminder.id) &&
            reminder.fireAt <= now &&
            // Do not resurface something the device slept through for days.
            now - reminder.fireAt < graceMs,
      )
      .toList();
}
