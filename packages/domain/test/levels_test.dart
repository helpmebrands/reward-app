import 'dart:convert';

import 'package:domain/domain.dart';
import 'package:test/test.dart';

import 'factories.dart';

/// 16 Sep 2026, 08:00 local, before the 09:00 reminder time.
final now = DateTime(2026, 9, 16, 8, 0, 0);

final on = defaultMemberPreferences.copyWith(enabled: true);

void main() {
  final credit = makeBenefit(Cadence.monthly);

  // @lat: [[tests#Notification levels#A credit's level comes from the member's flags]]
  test('levelFor reads the level from the member\'s flags', () {
    expect(levelFor(credit, on), NotificationLevel.periodically);
    expect(
      levelFor(credit, on.copyWith(lastCallBenefitIds: {credit.id})),
      NotificationLevel.lastChance,
    );
    expect(
      levelFor(credit, on.copyWith(mutedBenefitIds: {credit.id})),
      NotificationLevel.silenced,
    );
    expect(
      levelFor(
        credit,
        on.copyWith(
          mutedBenefitIds: {credit.id},
          lastCallBenefitIds: {credit.id},
        ),
      ),
      NotificationLevel.silenced,
    );
    expect(
      levelFor(credit, on.copyWith(mutedCardIds: {credit.cardId})),
      NotificationLevel.silenced,
    );
    // Transitional: the household's lastCallOnly still reads as Last chance.
    expect(
      levelFor(makeBenefit(Cadence.monthly, lastCallOnly: true), on),
      NotificationLevel.lastChance,
    );
  });

  // @lat: [[tests#Notification levels#Choosing a level sets the two flags]]
  test('withLevel sets the two flags from every level to every level', () {
    const id = 'benefit-1';
    final starts = {
      NotificationLevel.periodically: on,
      NotificationLevel.lastChance: on.copyWith(lastCallBenefitIds: {id}),
      NotificationLevel.silenced: on.copyWith(mutedBenefitIds: {id}),
    };
    for (final start in starts.values) {
      final periodically = withLevel(start, id, NotificationLevel.periodically);
      expect(periodically.mutedBenefitIds, isEmpty);
      expect(periodically.lastCallBenefitIds, isEmpty);

      final lastChance = withLevel(start, id, NotificationLevel.lastChance);
      expect(lastChance.mutedBenefitIds, isEmpty);
      expect(lastChance.lastCallBenefitIds, {id});

      final silenced = withLevel(start, id, NotificationLevel.silenced);
      expect(silenced.mutedBenefitIds, {id});
      expect(silenced.lastCallBenefitIds, start.lastCallBenefitIds);
    }

    // Silence keeps last-call, so unsilencing returns to Last chance.
    final lastChance = withLevel(on, id, NotificationLevel.lastChance);
    final silenced = withLevel(lastChance, id, NotificationLevel.silenced);
    expect(silenced.lastCallBenefitIds, {id});
    final cleared = withLevel(silenced, id, NotificationLevel.periodically);
    expect(cleared.mutedBenefitIds, isEmpty);
    expect(cleared.lastCallBenefitIds, isEmpty);

    // Other credits' flags are left alone.
    final other = on.copyWith(
      mutedBenefitIds: {'other'},
      lastCallBenefitIds: {'other'},
    );
    final changed = withLevel(other, id, NotificationLevel.periodically);
    expect(changed.mutedBenefitIds, {'other'});
    expect(changed.lastCallBenefitIds, {'other'});
  });

  // @lat: [[tests#Notification levels#Last chance collapses the member's schedule]]
  test('a member\'s last call gives the credit only its final rung', () {
    final household = makeData(benefits: [credit]);
    List<int> fireDays(MemberPreferences prefs) =>
        buildSchedule(household, prefs, now).reminders
            .where(
              (r) => DateTime.fromMillisecondsSinceEpoch(r.fireAt).month == 9,
            )
            .map((r) => DateTime.fromMillisecondsSinceEpoch(r.fireAt).day)
            .toList();

    expect(fireDays(on), [23, 30]);
    expect(fireDays(on.copyWith(lastCallBenefitIds: {credit.id})), [30]);
    expect(
      ladderFor(credit, on.copyWith(lastCallBenefitIds: {credit.id})),
      hasLength(1),
    );
    expect(ladderFor(credit, on), hasLength(3));
  });

  // @lat: [[tests#Notification levels#Last call round-trips in the preferences]]
  test('lastCallBenefitIds round-trips and loads empty when absent', () {
    final prefs = on.copyWith(lastCallBenefitIds: {'b2', 'b1'});
    final json = memberPreferencesToJson(prefs);
    expect(json['lastCallBenefitIds'], ['b1', 'b2']);
    final back = memberPreferencesFromJson(
      jsonDecode(jsonEncode(json)) as Map<String, dynamic>,
    );
    expect(back.lastCallBenefitIds, {'b1', 'b2'});

    final legacy = Map<String, dynamic>.of(json)..remove('lastCallBenefitIds');
    expect(memberPreferencesFromJson(legacy).lastCallBenefitIds, isEmpty);
  });

  // @lat: [[tests#Notification levels#Each level has a one-line note]]
  test('each level has a note naming what it sends', () {
    expect(
      levelNote(credit, NotificationLevel.periodically),
      '23 days, 7 days and the last day before it shuts',
    );
    expect(
      levelNote(credit, NotificationLevel.lastChance),
      'Only on the last day',
    );
    expect(
      levelNote(makeBenefit(Cadence.annual), NotificationLevel.lastChance),
      'Only 7 days before it shuts',
    );
    expect(
      levelNote(credit, NotificationLevel.silenced),
      'Keeps tracking it, sends nothing.',
    );
  });
}
