import 'dart:async';

import 'package:domain/domain.dart';
import 'package:domain/domain.dart' as domain show nextOpening;
import 'package:flutter/foundation.dart';

import '../data/claim_outbox.dart';
import '../data/household_api.dart';
import '../data/household_cache.dart';
import '../data/snapshot_store.dart';
import 'command.dart';
import 'ids.dart';

/// Said when an edit needs the network and there is none.
const offlineMessage =
    'You are offline. Changes need a connection; claims you log are kept '
    'and sent when you are back.';

/// Said when someone tries to log on, or change, a card shared with them
/// only to view.
String viewOnlyMessage(String? owner) =>
    'You can view ${owner == null ? 'this card' : '$owner’s card'} but not '
    'change it.';

/// Said when someone tries to change a card shared with them to record
/// usage.
String ownerOnlyMessage(String? owner) =>
    'Only ${owner ?? 'its owner'} can change this card.';

/// The app store: the cards this person can see as `AppData`, what they
/// may do with each, their preferences, today's date, the derived views the
/// screens read, and the mutations.
///
/// Two modes. Without a [HouseholdApi] (tests, previews) the snapshot is
/// local and every card is the device user's: every mutation replaces it,
/// notifies once and writes it through the [SnapshotStore]. With one, the
/// service tier holds the cards: the store serves the last answer from a
/// versioned [HouseholdCache] while it fetches, sends an edit and fetches
/// again, refuses edits offline and beyond a card's access, and queues
/// claims in a [ClaimOutbox] that is flushed in order. Screens never touch
/// storage or the network.
class AppStore extends ChangeNotifier {
  AppStore({
    required SnapshotStore store,
    DateTime Function()? clock,
    HouseholdApi? api,
    HouseholdCache? cache,
    ClaimOutbox? outbox,
  }) : _clock = clock ?? DateTime.now,
       // ignore: prefer_initializing_formals
       _store = store,
       // ignore: prefer_initializing_formals
       _api = api,
       _cache = cache ?? MemoryHouseholdCache(),
       _outbox = outbox ?? MemoryClaimOutbox();

  final SnapshotStore _store;
  final DateTime Function() _clock;
  final HouseholdApi? _api;
  final HouseholdCache _cache;
  final ClaimOutbox _outbox;

  /// The household as the api last served it; [data] adds pending claims.
  AppData? _server;
  List<PendingClaim> _pending = const [];
  Settings? _localSettings;

  /// What this person may do with each card, and who owns the cards shared
  /// with them, as the api last served them.
  Map<String, CardAccess> _access = const {};
  Map<String, Person> _people = const {};
  List<CardTemplate> _catalog = const [];
  bool _offline = false;
  String? _problem;
  Future<void>? _flushing;

  /// Whether the service tier holds the household.
  bool get remote => _api != null;

  /// The last request could not reach the api.
  bool get offline => remote && _offline;

  /// The catalogue "Add a card" lists: the api's in the service-tier mode
  /// (the built-in one until it has been fetched), with `blank` last.
  List<CardTemplate> get templates => remote && _catalog.isNotEmpty
      ? [..._catalog, findTemplate('blank')!]
      : cardTemplates;

  /// What this person may do with the card: everything with a local
  /// snapshot, where every card is theirs; otherwise what the api says, and
  /// only viewing for a card it has not named.
  CardAccess accessTo(String cardId) =>
      remote ? _access[cardId] ?? CardAccess.view : CardAccess.owner;

  /// The owner of a card shared with this person, or null for their own.
  Person? ownerOf(Card card) =>
      accessTo(card.id) == CardAccess.owner ? null : _people[card.ownerId];

  /// Everyone who shares cards with this person, in the api's order.
  List<Person> get people => _people.values.toList();

  /// The card's name as the app shows it: its display name, followed by
  /// its owner's name when it is someone else's ("Platinum · Alex").
  String cardName(Card card) {
    final owner = ownerOf(card);
    return owner == null
        ? cardLabel(card)
        : '${cardLabel(card)} · ${owner.displayName}';
  }

  /// The cards this person owns, the only ones their labels must not
  /// repeat ([labelError], [defaultLabel]).
  List<Card> get ownCards => [
    for (final card in _data?.cards ?? const <Card>[])
      if (accessTo(card.id) == CardAccess.owner) card,
  ];

  /// Whether the network allows an edit other than a claim now; what may
  /// be changed depends on each card's [accessTo].
  bool get canEdit => !offline;

  /// What stops this person writing to [cardId], said with its owner's
  /// name, or null when nothing does. [usage] is a claim or a credit's
  /// state, which a card shared to record allows.
  String? refusal(String cardId, {bool usage = false}) {
    final access = accessTo(cardId);
    if (access == CardAccess.owner || (usage && access.records)) return null;
    final owner = _ownerName(cardId);
    return access == CardAccess.view
        ? viewOnlyMessage(owner)
        : ownerOnlyMessage(owner);
  }

  /// The name of [cardId]'s owner as the api served it, or null.
  String? _ownerName(String cardId) {
    final card = _data?.cards.where((c) => c.id == cardId).firstOrNull;
    return card == null ? null : _people[card.ownerId]?.displayName;
  }

  /// The sentence to show for the last edit that could not be made, until
  /// [clearProblem].
  String? get problem => _problem;

  void clearProblem() => _problem = null;

  /// Whether any claim is waiting in the outbox.
  bool get hasPending => _pending.isNotEmpty;

  /// Signing out: the household, its cache and its queued claims are the
  /// last person's, and go.
  Future<void> forget() async {
    _server = null;
    _pending = const [];
    _access = const {};
    _people = const {};
    _shares = null;
    await _cache.clear();
    await _outbox.save(const []);
    _rebuild();
    notifyListeners();
  }

  /// Whether the claim is still waiting in the outbox.
  bool isPending(String claimId) => _pending.any((p) => p.claim.id == claimId);

  /// Fetches the household with each card's access and owners, and the
  /// preferences, then sends any queued claims. A second call while one is
  /// running joins it.
  late final Command0<void> refreshCommand = Command0(_refresh);

  Future<void> refresh() => refreshCommand.execute();

  AppData? _data;
  MemberPreferences _preferences = defaultMemberPreferences;
  bool _loading = true;
  bool _hasLocalPreferences = false;

  /// Set by any mutation. In the app the UI is gated on [loading], but a
  /// caller that writes before the snapshot arrives must not have its change
  /// discarded when the read resolves: the user's action wins, as in the PWA.
  bool _hasLocalChanges = false;

  /// The snapshot, or null before [load] completes or on a fresh install.
  AppData? get data => _data;
  bool get loading => _loading;

  /// This member's reminder settings and mutes, kept on the device until the
  /// api holds them. Never part of [data], which the household shares.
  MemberPreferences get preferences => _preferences;

  /// The user's local calendar date. Re-read on every access so an app
  /// resumed the next morning shows that morning's deadlines.
  IsoDate get today => todayIso(_clock());

  IsoInstant get _now => _clock().toUtc().toIso8601String();

  Future<void> load() async {
    if (remote) return _loadRemote();
    final loaded = await _store.load();
    final preferences = await _store.loadPreferences();
    if (!_hasLocalChanges) _data = loaded;
    if (!_hasLocalPreferences && preferences != null) {
      _preferences = preferences;
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> _loadRemote() async {
    _pending = await _outbox.load();
    final cached = await _cache.load();
    if (cached != null && cached.version == householdCacheVersion) {
      _server = cached.data;
      _access = cached.access;
      _people = cached.people;
    } else if (cached != null) {
      // Another version's shape: fetch again rather than migrate.
      _server = null;
      await _cache.clear();
    }
    final preferences = await _store.loadPreferences();
    if (preferences != null) _preferences = preferences;
    _localSettings = (await _store.load())?.settings;
    _rebuild();
    _loading = false;
    notifyListeners();
    try {
      await refresh();
    } on Object {
      // Offline: the cache is what there is.
    }
  }

  Future<void> _refresh() async {
    final api = _api!;
    try {
      final snapshot = await api.householdData();
      final preferences = await api.preferences();
      _catalog = await api.catalog();
      _server = snapshot.data;
      _access = snapshot.access;
      _people = snapshot.people;
      _preferences = preferences;
      _offline = false;
      await _cache.save(
        CachedHousehold(
          version: householdCacheVersion,
          data: snapshot.data,
          access: snapshot.access,
          people: snapshot.people,
        ),
      );
    } on ApiOffline {
      _offline = true;
      _rebuild();
      notifyListeners();
      rethrow;
    }
    _rebuild();
    notifyListeners();
    await flush();
  }

  /// The household as shown: the server's, with every claim still in the
  /// outbox added, and this device's display settings.
  void _rebuild() {
    final server = _server;
    if (server == null) {
      _data = null;
      return;
    }
    final served = {for (final c in server.claims) c.id};
    _data = server.copyWith(
      claims: [
        ...server.claims,
        for (final p in _pending)
          if (!served.contains(p.claim.id)) p.claim,
      ],
      settings: _localSettings ?? server.settings,
    );
  }

  /// Sends the queued claims in the order they were logged, each under its
  /// own idempotency key, so a flush repeated after a lost answer never
  /// makes a second claim. Concurrent calls share one flush.
  Future<void> flush() {
    if (!remote) return Future.value();
    return _flushing ??= _flush().whenComplete(() => _flushing = null);
  }

  Future<void> _flush() async {
    while (_pending.isNotEmpty) {
      final next = _pending.first;
      Claim? stored;
      try {
        stored = await _api!.postClaim(next.key, next.body);
      } on ApiOffline {
        _offline = true;
        notifyListeners();
        return;
      } on ApiError {
        // Refused for good (the credit is gone): drop it rather than retry
        // forever.
        stored = null;
      }
      _pending = _pending.skip(1).toList();
      await _outbox.save(_pending);
      final server = _server;
      if (server != null && stored != null) {
        final kept = stored;
        _server = server.copyWith(
          claims: [...server.claims.where((c) => c.id != kept.id), kept],
        );
      }
      _offline = false;
      _rebuild();
      notifyListeners();
    }
  }

  /// Runs one edit against the api and fetches the household again; false,
  /// with [problem] set, when it cannot be made. An edit to a card names it
  /// as [cardId] and is refused beyond the card's access; [usage] is a
  /// claim or a credit's state, which a card shared to record allows.
  Future<bool> _edit(
    Future<void> Function(HouseholdApi api) call, {
    String? cardId,
    bool usage = false,
  }) async {
    final refused = cardId == null ? null : refusal(cardId, usage: usage);
    if (refused != null) {
      _problem = refused;
      notifyListeners();
      return false;
    }
    try {
      await call(_api!);
      _problem = null;
      _offline = false;
    } on ApiOffline {
      _offline = true;
      _problem = offlineMessage;
      notifyListeners();
      return false;
    } on ApiError catch (e) {
      _problem = switch (e.error) {
        'system maintained' =>
          'This card follows the catalog. Change the terms to make it '
              'your own first.',
        'label taken' => 'Another card is already called that.',
        'forbidden' => ownerOnlyMessage(
          cardId == null ? null : _ownerName(cardId),
        ),
        _ => 'That did not work (${e.error}). Try again.',
      };
      notifyListeners();
      return false;
    }
    try {
      await refresh();
    } on Object {
      // The edit landed; the next refresh will show it.
    }
    return true;
  }

  // Sharing

  CardShares? _shares;

  /// The shares this person gives and receives, once [loadShares] has
  /// fetched them.
  CardShares? get shares => _shares;

  /// Fetches the shares both ways.
  Future<void> loadShares() async {
    try {
      _shares = await _api!.shares();
      _offline = false;
    } on ApiOffline {
      _offline = true;
    }
    notifyListeners();
  }

  /// Makes an invite at [access] to all of this person's cards, or to
  /// [cardIds]; null, with [problem] set, when it cannot be made.
  Future<Invite?> createInvite(
    CardAccess access, {
    List<String>? cardIds,
  }) async {
    Invite? invite;
    final done = await _edit((api) async {
      invite = await api.createInvite(access, cardIds: cardIds);
    });
    return done ? invite : null;
  }

  /// What the invite [code] offers, or why it cannot be read.
  Future<({InviteOffer? offer, JoinOutcome? problem})> readInvite(
    String code,
  ) async {
    if (!remote) return (offer: null, problem: JoinOutcome.failed);
    try {
      return (offer: await _api!.readInvite(code), problem: null);
    } on ApiOffline {
      return (offer: null, problem: JoinOutcome.offline);
    } on ApiError catch (e) {
      return (offer: null, problem: _joinProblem(e));
    }
  }

  /// Accepts the invite [code]: the share it carries is made, and the
  /// cards it brings are fetched. Nothing of this person's changes.
  Future<JoinOutcome> acceptInvite(String code) async {
    try {
      await _api!.acceptInvite(code);
    } on ApiOffline {
      _offline = true;
      notifyListeners();
      return JoinOutcome.offline;
    } on ApiError catch (e) {
      return _joinProblem(e);
    }
    try {
      await refresh();
      await loadShares();
    } on Object {
      // Accepted; the next refresh shows the cards.
    }
    return JoinOutcome.accepted;
  }

  static JoinOutcome _joinProblem(ApiError e) => switch (e.error) {
    'invite used' => JoinOutcome.used,
    'invite expired' => JoinOutcome.expired,
    'not found' => JoinOutcome.notFound,
    'own invite' => JoinOutcome.ownInvite,
    'already shared' => JoinOutcome.alreadyShared,
    _ => JoinOutcome.failed,
  };

  /// Sets what [memberId] sees of this person's cards: [access] to all of
  /// them, or to [cardIds].
  Future<bool> changeShare(
    String memberId,
    CardAccess access, {
    List<String>? cardIds,
  }) => _shareEdit(
    (api) => api.changeShare(memberId, access: access, cardIds: cardIds),
  );

  /// Stops sharing this person's cards with [memberId], at once.
  Future<bool> stopSharing(String memberId) =>
      _shareEdit((api) => api.stopSharing(memberId));

  /// Stops seeing [ownerId]'s cards, at once: they leave every list.
  Future<bool> stopSeeing(String ownerId) =>
      _shareEdit((api) => api.stopSeeing(ownerId));

  /// An edit to a share, followed by the shares fetched again.
  Future<bool> _shareEdit(Future<void> Function(HouseholdApi api) call) async {
    final done = await _edit(call);
    if (done) await loadShares();
    return done;
  }

  /// Turns a card the catalogue keeps up to date into one its owner
  /// maintains: claims, history, enrollment and everyone's silences go
  /// with it. The new card's id, or null with [problem] set.
  Future<String?> convertCard(String id) async {
    String? newId;
    final done = await _edit((api) async {
      newId = await api.convertCard(id);
    }, cardId: id);
    return done ? newId : null;
  }

  /// Replaces the whole snapshot, as an import does.
  Future<void> replaceAll(AppData data) => _commit(data);

  /// The snapshot every mutation starts from: what is loaded, or an empty
  /// household when nothing is yet.
  AppData get _current => _data ?? emptyAppData();

  Future<void> _commit(AppData next) {
    _hasLocalChanges = true;
    _data = next;
    _loading = false;
    notifyListeners();
    return _store.save(next);
  }

  // Cards

  /// Creates a card from a catalogue template with its credits attached.
  /// [anniversaryOn] defaults to today; [issuer] and [product] override the
  /// template's for the blank card.
  Future<Card> addCardFromTemplate(
    CardTemplate template, {
    String? label,
    String? last4,
    IsoDate? anniversaryOn,
    String? issuer,
    String? product,
    CardKind? kind,
  }) async {
    if (remote) {
      Card? created;
      final linked = template.id != 'blank';
      final done = await _edit((api) async {
        created = await api.addCard({
          if (linked) 'templateId': template.id,
          if (!linked) ...{
            'issuer': issuer ?? template.issuer,
            'product': product ?? template.product,
            'network': template.network.name,
            'annualFeeCents': template.annualFeeCents,
          },
          'anniversaryOn': anniversaryOn ?? today,
          'label': ?label,
          'last4': ?last4,
          'kind': (kind ?? template.kind).name,
        });
      });
      if (!done) throw StateError(_problem ?? offlineMessage);
      return created!;
    }
    final now = _now;
    final card = Card(
      id: newId(),
      issuer: issuer ?? template.issuer,
      product: product ?? template.product,
      label: label,
      network: template.network,
      kind: kind ?? template.kind,
      last4: last4,
      annualFeeCents: template.annualFeeCents,
      anniversaryOn: anniversaryOn ?? today,
      archived: false,
      createdAt: now,
      updatedAt: now,
    );
    final benefits = benefitsFromTemplate(template, card.id, now, newId);
    final data = _current;
    await _commit(
      data.copyWith(
        cards: [...data.cards, card],
        benefits: [...data.benefits, ...benefits],
      ),
    );
    return card;
  }

  Future<bool> updateCard(String id, Card Function(Card card) patch) async {
    final data = _current;
    if (remote) {
      final before = data.cards.firstWhere((c) => c.id == id);
      final after = patch(before);
      final body = <String, Object?>{
        if (after.label != before.label) 'label': after.label,
        if (after.last4 != before.last4) 'last4': after.last4,
        if (after.kind != before.kind) 'kind': after.kind.name,
        if (after.anniversaryOn != before.anniversaryOn)
          'anniversaryOn': after.anniversaryOn,
        if (after.archived != before.archived) 'archived': after.archived,
        if (after.issuer != before.issuer) 'issuer': after.issuer,
        if (after.product != before.product) 'product': after.product,
        if (after.network != before.network) 'network': after.network.name,
        if (after.annualFeeCents != before.annualFeeCents)
          'annualFeeCents': after.annualFeeCents,
      };
      if (body.isEmpty) return true;
      return _edit((api) => api.patchCard(id, body), cardId: id);
    }
    await _commit(
      data.copyWith(
        cards: [
          for (final card in data.cards)
            card.id == id ? patch(card).copyWith(updatedAt: _now) : card,
        ],
      ),
    );
    return true;
  }

  /// Silences or unsilences every credit on a card, for this member only.
  Future<void> toggleCardMute(String id) async {
    if (!remote) {
      _setPreferences(
        _preferences.copyWith(
          mutedCardIds: _toggled(_preferences.mutedCardIds, id),
        ),
      );
      return;
    }
    if (isMutePending(id)) return;
    final muted = !isCardMuted(id);
    _cardMutesInFlight[id] = muted;
    notifyListeners();
    final done = await _edit((api) => api.setMute(cardId: id, muted: muted));
    _cardMutesInFlight.remove(id);
    // The refresh after the edit brings the server's mutes; apply the
    // request only if the edit landed and that refresh did not.
    if (done && _preferences.mutedCardIds.contains(id) != muted) {
      await _setPreferences(
        _preferences.copyWith(
          mutedCardIds: _toggled(_preferences.mutedCardIds, id),
        ),
      );
      return;
    }
    notifyListeners();
  }

  bool isCardMuted(String id) => _shownPreferences.mutedCardIds.contains(id);

  /// Requested mutes the api has not answered yet, by card or benefit id.
  final _cardMutesInFlight = <String, bool>{};
  final _benefitMutesInFlight = <String, bool>{};

  /// Requested notification levels the api has not answered yet, by
  /// benefit id.
  final _levelsInFlight = <String, NotificationLevel>{};

  /// A mute or a notification level for this card or credit is on its way
  /// to the api; its control shows the requested state and is disabled
  /// until the answer.
  bool isMutePending(String id) =>
      _cardMutesInFlight.containsKey(id) ||
      _benefitMutesInFlight.containsKey(id) ||
      _levelsInFlight.containsKey(id);

  /// The member's preferences with every in-flight mute and level at its
  /// requested state.
  MemberPreferences get _shownPreferences {
    if (_cardMutesInFlight.isEmpty &&
        _benefitMutesInFlight.isEmpty &&
        _levelsInFlight.isEmpty) {
      return _preferences;
    }
    Set<String> overlay(Set<String> ids, Map<String, bool> inFlight) => {
      for (final id in ids)
        if (inFlight[id] ?? true) id,
      for (final MapEntry(:key, :value) in inFlight.entries)
        if (value) key,
    };
    var shown = _preferences.copyWith(
      mutedCardIds: overlay(_preferences.mutedCardIds, _cardMutesInFlight),
      mutedBenefitIds: overlay(
        _preferences.mutedBenefitIds,
        _benefitMutesInFlight,
      ),
    );
    for (final MapEntry(:key, :value) in _levelsInFlight.entries) {
      shown = withLevel(shown, key, value);
    }
    return shown;
  }

  Future<bool> archiveCard(String id) =>
      updateCard(id, (card) => card.copyWith(archived: true));

  /// Removes the card, its benefits and every claim on them.
  Future<void> deleteCard(String id) async {
    if (remote) {
      await _edit((api) => api.deleteCard(id), cardId: id);
      return;
    }
    final data = _current;
    final benefitIds = {
      for (final b in data.benefits)
        if (b.cardId == id) b.id,
    };
    return _commit(
      data.copyWith(
        cards: data.cards.where((c) => c.id != id).toList(),
        benefits: data.benefits.where((b) => b.cardId != id).toList(),
        claims: data.claims
            .where((c) => !benefitIds.contains(c.benefitId))
            .toList(),
      ),
    );
  }

  // Benefits

  /// Adds a benefit; the draft's id and timestamps are replaced by the store's.
  Future<Benefit> addBenefit(Benefit draft) async {
    if (remote) {
      Benefit? created;
      final done = await _edit((api) async {
        created = await api.addBenefit(draft.cardId, _terms(draft));
      }, cardId: draft.cardId);
      if (!done) throw StateError(_problem ?? offlineMessage);
      return created!;
    }
    final now = _now;
    final benefit = Benefit(
      id: newId(),
      cardId: draft.cardId,
      name: draft.name,
      description: draft.description,
      category: draft.category,
      icon: draft.icon,
      merchant: draft.merchant,
      valueCents: draft.valueCents,
      cadence: draft.cadence,
      anchor: draft.anchor,
      intervalMonths: draft.intervalMonths,
      enrollmentRequired: draft.enrollmentRequired,
      enrolledAt: draft.enrolledAt,
      enrollmentNote: draft.enrollmentNote,
      enrollmentUrl: draft.enrollmentUrl,
      spendThresholdCents: draft.spendThresholdCents,
      spendMetAt: draft.spendMetAt,
      endsOn: draft.endsOn,
      redemptionSteps: draft.redemptionSteps,
      notes: draft.notes,
      active: draft.active,
      createdAt: now,
      updatedAt: now,
    );
    final data = _current;
    await _commit(data.copyWith(benefits: [...data.benefits, benefit]));
    return benefit;
  }

  Future<bool> updateBenefit(
    String id,
    Benefit Function(Benefit benefit) patch,
  ) async {
    final data = _current;
    if (remote) {
      final before = data.benefits.firstWhere((b) => b.id == id);
      final after = patch(before);
      final state = <String, Object?>{
        if (after.enrolledAt != before.enrolledAt)
          'enrolledAt': after.enrolledAt,
        if (after.enrollmentNote != before.enrollmentNote)
          'enrollmentNote': after.enrollmentNote,
        if (after.enrollmentUrl != before.enrollmentUrl)
          'enrollmentUrl': after.enrollmentUrl,
        if (after.spendMetAt != before.spendMetAt)
          'spendMetAt': after.spendMetAt,
        if (after.active != before.active) 'active': after.active,
        if (after.optedOutAt != before.optedOutAt)
          'optedOutAt': after.optedOutAt,
        if (after.trackedFrom != before.trackedFrom)
          'trackedFrom': after.trackedFrom,
      };
      final terms = _terms(after);
      final termsChanged = '$terms' != '${_terms(before)}';
      if (state.isEmpty && !termsChanged) return true;
      // A credit's state is usage, which a card shared to record allows;
      // its terms are the owner's.
      return _edit(
        (api) async {
          if (state.isNotEmpty) await api.putBenefitState(id, state);
          if (termsChanged) await api.putBenefit(id, terms);
        },
        cardId: before.cardId,
        usage: !termsChanged,
      );
    }
    await _commit(
      data.copyWith(
        benefits: [
          for (final benefit in data.benefits)
            benefit.id == id
                ? patch(benefit).copyWith(updatedAt: _now)
                : benefit,
        ],
      ),
    );
    return true;
  }

  /// A credit's terms as the api takes them: everything but its identity,
  /// its household state and its timestamps.
  static Map<String, Object?> _terms(Benefit benefit) =>
      benefitToJson(benefit)..removeWhere(
        (key, _) => const {
          'id',
          'cardId',
          'templateBenefitId',
          'enrolledAt',
          'enrollmentNote',
          'enrollmentUrl',
          'spendMetAt',
          'active',
          'optedOutAt',
          'trackedFrom',
          'createdAt',
          'updatedAt',
        }.contains(key),
      );

  /// Silences or unsilences one credit, for this member only.
  Future<void> toggleBenefitMute(String id) async {
    if (!remote) {
      _setPreferences(
        _preferences.copyWith(
          mutedBenefitIds: _toggled(_preferences.mutedBenefitIds, id),
        ),
      );
      return;
    }
    if (isMutePending(id)) return;
    final muted = !isBenefitMuted(id);
    _benefitMutesInFlight[id] = muted;
    notifyListeners();
    final done = await _edit((api) => api.setMute(benefitId: id, muted: muted));
    _benefitMutesInFlight.remove(id);
    if (done && _preferences.mutedBenefitIds.contains(id) != muted) {
      await _setPreferences(
        _preferences.copyWith(
          mutedBenefitIds: _toggled(_preferences.mutedBenefitIds, id),
        ),
      );
      return;
    }
    notifyListeners();
  }

  bool isBenefitMuted(String id) =>
      _shownPreferences.mutedBenefitIds.contains(id);

  /// This member's notification level for one credit: Silence when it or
  /// its card is muted, else Last chance or Periodically.
  NotificationLevel notificationLevel(String id) {
    final benefit = _data?.benefits.where((b) => b.id == id).firstOrNull;
    if (benefit == null) return NotificationLevel.periodically;
    return levelFor(benefit, _shownPreferences);
  }

  /// Sets one credit's notification level, for this member only. Against
  /// the api the requested level shows, pending, until it answers.
  Future<void> setNotificationLevel(String id, NotificationLevel level) async {
    if (!remote) {
      await _setPreferences(withLevel(_preferences, id, level));
      return;
    }
    if (isMutePending(id)) return;
    _levelsInFlight[id] = level;
    notifyListeners();
    final done = await _edit((api) => api.setNotificationLevel(id, level));
    _levelsInFlight.remove(id);
    // As for a mute: apply the request only if it landed and the refresh
    // after it did not bring it.
    final wanted = withLevel(_preferences, id, level);
    if (done &&
        (wanted.mutedBenefitIds.contains(id) !=
                _preferences.mutedBenefitIds.contains(id) ||
            wanted.lastCallBenefitIds.contains(id) !=
                _preferences.lastCallBenefitIds.contains(id))) {
      await _setPreferences(wanted);
      return;
    }
    notifyListeners();
  }

  static Set<String> _toggled(Set<String> ids, String id) =>
      ids.contains(id) ? ({...ids}..remove(id)) : {...ids, id};

  /// Takes a credit the household will never use off every list and total
  /// but its own ([BenefitStatus.optedOut]).
  Future<bool> optOutBenefit(String id) =>
      updateBenefit(id, (b) => b.copyWith(optedOutAt: _now));

  /// Tracks an opted-out credit again from today, so the windows that closed
  /// while it was opted out are never counted as missed. With [resume] false
  /// it only clears the opt-out, which is how an Undo takes one back.
  Future<bool> reactivateBenefit(String id, {bool resume = true}) =>
      updateBenefit(
        id,
        (b) => resume
            ? b.copyWith(optedOutAt: null, trackedFrom: today)
            : b.copyWith(optedOutAt: null),
      );

  /// Records that the user has ticked the issuer's enrollment box.
  Future<bool> confirmEnrollment(String id) =>
      updateBenefit(id, (b) => b.copyWith(enrolledAt: _now));

  Future<bool> revokeEnrollment(String id) =>
      updateBenefit(id, (b) => b.copyWith(enrolledAt: null));

  /// Records that this year's spend threshold has been reached.
  Future<bool> confirmSpend(String id) =>
      updateBenefit(id, (b) => b.copyWith(spendMetAt: _now));

  Future<bool> revokeSpend(String id) =>
      updateBenefit(id, (b) => b.copyWith(spendMetAt: null));

  /// Removes the benefit and its claims.
  Future<void> deleteBenefit(String id) async {
    if (remote) {
      final cardId = _current.benefits.firstWhere((b) => b.id == id).cardId;
      await _edit((api) => api.deleteBenefit(id), cardId: cardId);
      return;
    }
    final data = _current;
    return _commit(
      data.copyWith(
        benefits: data.benefits.where((b) => b.id != id).toList(),
        claims: data.claims.where((c) => c.benefitId != id).toList(),
      ),
    );
  }

  // Claims

  /// Logs a use of a credit. Without [amountCents] it claims what is left
  /// rather than the face value, so a second claim against a partly used
  /// credit cannot overshoot.
  Future<Claim> claim(
    BenefitInstance instance, {
    int? amountCents,
    String? note,
  }) async {
    final claim = Claim(
      id: newId(),
      benefitId: instance.benefit.id,
      cycleKey: instance.cycle.key,
      amountCents: amountCents ?? instance.remainingCents,
      claimedAt: _now,
      note: note,
    );
    if (remote) {
      final refused = refusal(instance.card.id, usage: true);
      if (refused != null) {
        _problem = refused;
        notifyListeners();
        throw StateError(refused);
      }
      // Shown at once as pending; sent when the network allows, under a
      // key made once so every retry is the same request.
      _pending = [..._pending, PendingClaim(key: newId(), claim: claim)];
      await _outbox.save(_pending);
      _rebuild();
      notifyListeners();
      unawaited(flush());
      return claim;
    }
    final data = _current;
    await _commit(data.copyWith(claims: [...data.claims, claim]));
    return claim;
  }

  /// Takes claims back: out of the outbox when they have not been sent,
  /// from the api when they have.
  Future<void> _withdraw(Iterable<Claim> claims) async {
    final ids = {for (final c in claims) c.id};
    final queued = {
      for (final p in _pending)
        if (ids.contains(p.claim.id)) p.claim.id,
    };
    if (queued.isNotEmpty) {
      _pending = _pending.where((p) => !queued.contains(p.claim.id)).toList();
      await _outbox.save(_pending);
      _rebuild();
      notifyListeners();
    }
    final sent = ids.difference(queued);
    if (sent.isEmpty) return;
    // The claims taken back together are one credit's.
    final benefitId = claims.firstWhere((c) => sent.contains(c.id)).benefitId;
    final cardId = _current.benefits
        .firstWhere((b) => b.id == benefitId)
        .cardId;
    await _edit(
      (api) async {
        for (final id in sent) {
          await api.deleteClaim(id);
        }
      },
      cardId: cardId,
      usage: true,
    );
  }

  /// Removes every claim recorded against one cycle.
  Future<void> unclaim(String benefitId, IsoDate cycleKey) async {
    final data = _current;
    if (remote) {
      return _withdraw(
        data.claims.where(
          (c) => c.benefitId == benefitId && c.cycleKey == cycleKey,
        ),
      );
    }
    return _commit(
      data.copyWith(
        claims: data.claims
            .where((c) => !(c.benefitId == benefitId && c.cycleKey == cycleKey))
            .toList(),
      ),
    );
  }

  /// Removes one claim, leaving the rest of the cycle's history alone.
  Future<void> removeClaim(String id) async {
    final data = _current;
    if (remote) return _withdraw(data.claims.where((c) => c.id == id));
    return _commit(
      data.copyWith(claims: data.claims.where((c) => c.id != id).toList()),
    );
  }

  // Settings

  Future<void> updateSettings(Settings Function(Settings settings) patch) {
    final data = _current;
    if (remote) {
      // The theme and the horizon are this device's, not the household's.
      final settings = patch(data.settings);
      _localSettings = settings;
      _rebuild();
      notifyListeners();
      return _store.save(emptyAppData().copyWith(settings: settings));
    }
    return _commit(data.copyWith(settings: patch(data.settings)));
  }

  /// Replaces this member's preferences, notifies once, then saves them
  /// apart from the household's snapshot.
  Future<void> updatePreferences(
    MemberPreferences Function(MemberPreferences preferences) patch,
  ) async {
    final next = patch(_preferences);
    if (remote && !await _edit((api) => api.putPreferences(next))) {
      return;
    }
    await _setPreferences(next);
  }

  Future<void> _setPreferences(MemberPreferences next) {
    _hasLocalPreferences = true;
    _preferences = next;
    notifyListeners();
    return _store.savePreferences(_preferences);
  }

  // Derived views

  /// Every tracked credit resolved against today, by urgency. Opted-out
  /// credits are left out: they appear on no list.
  List<BenefitInstance> get instances {
    final data = _data;
    if (data == null) return const [];
    return [
      for (final instance in currentInstances(data, today, _shownPreferences))
        if (instance.status != BenefitStatus.optedOut) instance,
    ];
  }

  /// One credit resolved against today, or null when it is not tracked.
  BenefitInstance? instanceFor(String benefitId) {
    for (final instance in instances) {
      if (instance.benefit.id == benefitId) return instance;
    }
    return null;
  }

  /// What has been logged against one cycle, newest first.
  List<Claim> claimsFor(String benefitId, IsoDate cycleKey) {
    final data = _data;
    if (data == null) return const [];
    return data.claims
        .where((c) => c.benefitId == benefitId && c.cycleKey == cycleKey)
        .toList()
      ..sort((a, b) => b.claimedAt.compareTo(a.claimedAt));
  }

  List<MissedCycle> get missed {
    final data = _data;
    return data == null ? const [] : missedCycles(data, today);
  }

  /// The five totals. Unlike [instances] they see the opted-out credits,
  /// which count only in their own figure.
  Totals get totals {
    final data = _data;
    return totalsFor(
      data == null
          ? const []
          : currentInstances(data, today, _shownPreferences),
      missed.fold(0, (sum, m) => sum + m.missedCents),
    );
  }

  List<BenefitInstance> get soon => byStatus(instances, BenefitStatus.useSoon);
  List<BenefitInstance> get locked => byStatus(instances, BenefitStatus.locked);
  List<BenefitInstance> get captured =>
      instances.where((i) => i.claimedCents > 0).toList();
  List<OverlapGroup> get overlaps => findOverlaps(instances);

  /// Per-card figures for the Cards and Value screens, one per active card,
  /// over every instance regardless of the household filter.
  List<CardSummary> get cardSummaries {
    final data = _data;
    if (data == null) return const [];
    final today = this.today;
    final all = currentInstances(data, today);
    final missed = missedCycles(data, today);
    return [
      for (final card in data.cards)
        if (!card.archived) summarizeCard(card, data, all, missed, today),
    ];
  }

  /// A card's value bar: its calendar year to date, over every credit
  /// regardless of the household filter ([cardYearToDateBreakdown]).
  ValueBreakdown cardValue(Card card) {
    final data = _data;
    if (data == null) return ValueBreakdown.zero;
    return cardYearToDateBreakdown(card, data, today);
  }

  /// Today's value bar: every active card's [cardValue] summed
  /// ([householdBreakdown]).
  ValueBreakdown get householdValue {
    final data = _data;
    if (data == null) return ValueBreakdown.zero;
    return householdBreakdown(data, today);
  }

  /// The overlap group with this label among the visible instances, or null
  /// once a claim or the filter has dissolved it.
  OverlapGroup? overlapFor(String label) {
    for (final overlap in overlaps) {
      if (overlap.label == label) return overlap;
    }
    return null;
  }

  IsoDate? get nextResetOn => nextReset(instances);

  /// The next day a credit window opens, which Today's "Next up" names.
  NextOpening? get nextOpening {
    final data = _data;
    return data == null ? null : domain.nextOpening(data, today);
  }

  bool get hasCards => _data?.cards.any((card) => !card.archived) ?? false;
  int get cardCount => _data?.cards.where((card) => !card.archived).length ?? 0;
}

/// What reading or accepting an invite came to.
enum JoinOutcome {
  accepted,
  used,
  expired,
  notFound,
  ownInvite,
  alreadyShared,
  offline,
  failed,
}
