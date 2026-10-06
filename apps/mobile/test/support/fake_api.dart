import 'dart:async';

import 'package:domain/domain.dart';
import 'package:reward/data/household_api.dart';
import 'package:reward/data/snapshot_store.dart';

/// A fake service tier for widget and store tests: an in-memory household
/// that dedupes claims by idempotency key as the real api does, serves what
/// the caller may do with each card, and records the calls it is sent.

const stamp = '2026-01-01T00:00:00.000Z';

const card1 = Card(
  id: 'card-1',
  issuer: 'American Express',
  product: 'Gold',
  network: CardNetwork.amex,
  kind: CardKind.personal,
  annualFeeCents: 32500,
  anniversaryOn: '2024-05-01',
  archived: false,
  createdAt: stamp,
  updatedAt: stamp,
);

const benefit1 = Benefit(
  id: 'benefit-1',
  cardId: 'card-1',
  name: 'Dining Credit',
  category: BenefitCategory.dining,
  valueCents: 1000,
  cadence: Cadence.monthly,
  anchor: CycleAnchor.calendar,
  enrollmentRequired: false,
  redemptionSteps: [],
  active: true,
  createdAt: stamp,
  updatedAt: stamp,
);

AppData serverHousehold({String label = 'Server'}) => AppData(
  version: 2,
  cards: [card1.copyWith(label: label)],
  benefits: const [benefit1],
  claims: const [],
  settings: defaultSettings,
);

/// An in-memory service tier that dedupes claims by idempotency key, as
/// the real one does.
class FakeApi implements HouseholdApi {
  FakeApi({
    AppData? data,
    Map<String, CardAccess>? access,
    Map<String, Person>? people,
  }) : data = data ?? serverHousehold(),
       access = access ?? {},
       people = people ?? {};

  AppData data;

  /// What the caller may do with each card; a card not named is theirs.
  Map<String, CardAccess> access;

  /// The owners of the cards shared with the caller, by user id.
  Map<String, Person> people;
  bool online = true;
  int claimPosts = 0;
  final _claimsByKey = <String, Claim>{};

  void _check() {
    if (!online) throw const ApiOffline();
  }

  @override
  Future<HouseholdSnapshot> householdData() async {
    _check();
    return HouseholdSnapshot(
      data: data,
      access: {
        for (final card in data.cards)
          card.id: access[card.id] ?? CardAccess.owner,
      },
      people: {...people},
    );
  }

  /// Invites made: the access and the chosen cards, null for all of them.
  final invites = <({CardAccess access, List<String>? cardIds})>[];

  @override
  Future<Invite> createInvite(
    CardAccess access, {
    List<String>? cardIds,
  }) async {
    _check();
    invites.add((access: access, cardIds: cardIds));
    return Invite(
      code: 'ABCD2345',
      link: 'https://api.test/invite/ABCD2345',
      access: access,
      allCards: cardIds == null,
      cardIds: cardIds ?? const [],
      expiresAt: '2026-09-23T10:00:00.000Z',
    );
  }

  /// What reading an invite answers, unless [readAnswer] is thrown.
  InviteOffer offer = const InviteOffer(
    owner: Person(id: 'user-alex', name: 'Alex', email: 'alex@example.com'),
    access: CardAccess.view,
    allCards: true,
  );
  Object? readAnswer;

  @override
  Future<InviteOffer> readInvite(String code) async {
    _check();
    if (readAnswer case final answer?) throw answer;
    return offer;
  }

  /// Thrown by the next accept; otherwise [onAccept] adds what the share
  /// brings.
  Object? acceptAnswer;
  void Function(FakeApi api)? onAccept;
  final accepted = <String>[];

  @override
  Future<void> acceptInvite(String code) async {
    _check();
    accepted.add(code);
    if (acceptAnswer case final answer?) throw answer;
    onAccept?.call(this);
  }

  /// The shares the caller gives and receives, as the api holds them.
  final given = <CardShare>[];
  final received = <CardShare>[];
  final changes =
      <({String memberId, CardAccess access, List<String>? cardIds})>[];
  final stoppedSharing = <String>[];
  final stoppedSeeing = <String>[];

  @override
  Future<CardShares> shares() async {
    _check();
    return CardShares(given: [...given], received: [...received]);
  }

  @override
  Future<void> changeShare(
    String memberId, {
    required CardAccess access,
    List<String>? cardIds,
  }) async {
    _check();
    changes.add((memberId: memberId, access: access, cardIds: cardIds));
    final at = given.indexWhere((s) => s.person.id == memberId);
    given[at] = CardShare(
      person: given[at].person,
      access: access,
      allCards: cardIds == null,
      cardIds: cardIds ?? const [],
    );
  }

  @override
  Future<void> stopSharing(String memberId) async {
    _check();
    stoppedSharing.add(memberId);
    given.removeWhere((s) => s.person.id == memberId);
  }

  /// Stops seeing the owner's cards: they leave the household served.
  @override
  Future<void> stopSeeing(String ownerId) async {
    _check();
    stoppedSeeing.add(ownerId);
    received.removeWhere((s) => s.person.id == ownerId);
    final gone = {
      for (final card in data.cards)
        if (card.ownerId == ownerId) card.id,
    };
    data = data.copyWith(
      cards: [
        for (final card in data.cards)
          if (!gone.contains(card.id)) card,
      ],
      benefits: [
        for (final benefit in data.benefits)
          if (!gone.contains(benefit.cardId)) benefit,
      ],
    );
    people.remove(ownerId);
  }

  /// The member's mutes as the server holds them.
  final mutedCardIds = <String>{};
  final mutedBenefitIds = <String>{};

  /// Credits the member hears about only on the last rung, as the server
  /// holds them.
  final lastCallBenefitIds = <String>{};

  /// Holds the next `setMute` or `setNotificationLevel` open until
  /// completed.
  Completer<void>? holdMute;

  /// Thrown by `setMute` or `setNotificationLevel` (after any hold) instead
  /// of recording it.
  Object? muteAnswer;

  @override
  Future<MemberPreferences> preferences() async {
    _check();
    return defaultMemberPreferences.copyWith(
      mutedCardIds: {...mutedCardIds},
      mutedBenefitIds: {...mutedBenefitIds},
      lastCallBenefitIds: {...lastCallBenefitIds},
    );
  }

  @override
  Future<void> putPreferences(MemberPreferences preferences) async => _check();

  @override
  Future<void> setMute({
    String? cardId,
    String? benefitId,
    required bool muted,
  }) async {
    _check();
    final hold = holdMute;
    if (hold != null) {
      holdMute = null;
      await hold.future;
    }
    final answer = muteAnswer;
    if (answer != null) throw answer;
    final ids = cardId != null ? mutedCardIds : mutedBenefitIds;
    final id = cardId ?? benefitId!;
    muted ? ids.add(id) : ids.remove(id);
  }

  @override
  Future<void> setNotificationLevel(
    String benefitId,
    NotificationLevel level,
  ) async {
    _check();
    final hold = holdMute;
    if (hold != null) {
      holdMute = null;
      await hold.future;
    }
    final answer = muteAnswer;
    if (answer != null) throw answer;
    final next = withLevel(await preferences(), benefitId, level);
    mutedBenefitIds
      ..clear()
      ..addAll(next.mutedBenefitIds);
    lastCallBenefitIds
      ..clear()
      ..addAll(next.lastCallBenefitIds);
  }

  @override
  Future<Claim> postClaim(String key, Map<String, Object?> body) async {
    _check();
    claimPosts++;
    return _claimsByKey.putIfAbsent(key, () {
      final claim = Claim(
        id: 'server-${_claimsByKey.length + 1}',
        benefitId: body['benefitId']! as String,
        cycleKey: body['cycleKey']! as String,
        amountCents: body['amountCents']! as int,
        claimedAt: body['claimedAt']! as String,
      );
      data = data.copyWith(claims: [...data.claims, claim]);
      return claim;
    });
  }

  /// The state bodies sent, in order.
  final benefitStates = <Map<String, Object?>>[];

  /// Terms bodies sent to `PUT /v1/benefits/{id}`.
  final benefitTerms = <Map<String, Object?>>[];

  @override
  Future<void> putBenefitState(String id, Map<String, Object?> state) async {
    _check();
    benefitStates.add(state);
    data = data.copyWith(
      benefits: [
        for (final b in data.benefits)
          b.id == id ? benefitFromJson({...benefitToJson(b), ...state}) : b,
      ],
    );
  }

  @override
  Future<void> putBenefit(String id, Map<String, Object?> terms) async {
    _check();
    benefitTerms.add(terms);
  }

  @override
  Future<void> patchCard(String id, Map<String, Object?> body) async {
    _check();
    data = data.copyWith(
      cards: [
        for (final c in data.cards)
          c.id == id && body.containsKey('label')
              ? c.copyWith(label: body['label'] as String?)
              : c,
      ],
    );
  }

  int _ids = 0;
  String _id(String kind) => '$kind-${++_ids}';
  final converted = <String>[];

  @override
  Future<List<CardTemplate>> catalog() async {
    _check();
    return [
      for (final t in cardTemplates)
        if (t.id != 'blank') t,
    ];
  }

  @override
  Future<Card> addCard(Map<String, Object?> body) async {
    _check();
    final templateId = body['templateId'] as String?;
    final template = templateId == null ? null : findTemplate(templateId)!;
    final card = Card(
      id: _id('card'),
      templateId: templateId,
      label: body['label'] as String?,
      issuer: template?.issuer ?? body['issuer']! as String,
      product: template?.product ?? body['product']! as String,
      network: template?.network ?? CardNetwork.other,
      kind: CardKind.values.byName(body['kind']! as String),
      annualFeeCents: template?.annualFeeCents ?? 0,
      anniversaryOn: body['anniversaryOn']! as String,
      archived: false,
      createdAt: stamp,
      updatedAt: stamp,
    );
    final benefits = [
      for (final credit in template?.benefits ?? const <BenefitTemplate>[])
        benefitFromCredit(
          credit,
          LinkedBenefitState(
            id: _id('benefit'),
            cardId: card.id,
            templateBenefitId: credit.id,
            createdAt: stamp,
            updatedAt: stamp,
          ),
        ),
    ];
    data = data.copyWith(
      cards: [...data.cards, card],
      benefits: [...data.benefits, ...benefits],
    );
    return card;
  }

  @override
  Future<String> convertCard(String id) async {
    _check();
    converted.add(id);
    final newId = _id('card');
    final ids = <String, String>{};
    data = data.copyWith(
      cards: [
        for (final c in data.cards)
          c.id == id
              ? Card(
                  id: newId,
                  label: c.label,
                  issuer: c.issuer,
                  product: c.product,
                  network: c.network,
                  kind: c.kind,
                  annualFeeCents: c.annualFeeCents,
                  anniversaryOn: c.anniversaryOn,
                  archived: c.archived,
                  createdAt: c.createdAt,
                  updatedAt: c.updatedAt,
                )
              : c,
      ],
      benefits: [
        for (final b in data.benefits)
          if (b.cardId == id)
            (() {
              final nb = _id('benefit');
              ids[b.id] = nb;
              return Benefit(
                id: nb,
                cardId: newId,
                name: b.name,
                category: b.category,
                icon: b.icon,
                merchant: b.merchant,
                valueCents: b.valueCents,
                cadence: b.cadence,
                anchor: b.anchor,
                intervalMonths: b.intervalMonths,
                enrollmentRequired: b.enrollmentRequired,
                enrolledAt: b.enrolledAt,
                redemptionSteps: b.redemptionSteps,
                active: b.active,
                createdAt: b.createdAt,
                updatedAt: b.updatedAt,
              );
            })()
          else
            b,
      ],
    );
    data = data.copyWith(
      claims: [
        for (final c in data.claims)
          ids.containsKey(c.benefitId)
              ? Claim(
                  id: c.id,
                  benefitId: ids[c.benefitId]!,
                  cycleKey: c.cycleKey,
                  amountCents: c.amountCents,
                  claimedAt: c.claimedAt,
                )
              : c,
      ],
    );
    return newId;
  }

  /// Registered devices by token, as the api holds them for this member.
  final devices = <String, PushDevice>{};

  /// What `GET /v1/me/reminders/summary` answers.
  ReminderSummary summary = const ReminderSummary(count: 0);
  int testSends = 0;

  /// The delay each test notification asked for.
  final testDelays = <int>[];

  /// When set, a test notification waits for it, so a test can look at the
  /// app mid-request.
  Completer<void>? testGate;

  @override
  Future<void> registerDevice(PushDevice device) async {
    _check();
    devices[device.token] = device;
  }

  @override
  Future<void> unregisterDevice(String token) async {
    _check();
    devices.remove(token);
  }

  @override
  Future<ReminderSummary> reminderSummary() async {
    _check();
    return summary;
  }

  @override
  Future<int> sendTestReminder({int delaySeconds = 0}) async {
    _check();
    testDelays.add(delaySeconds);
    await testGate?.future;
    testSends++;
    return devices.length;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
