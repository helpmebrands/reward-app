import 'dart:async';

import 'package:domain/domain.dart';
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

/// Said when a reader tries to change the household.
const readOnlyMessage = 'You can view this household but not change it.';

/// The app store: the household's `AppData`, this member's preferences,
/// today's date, the derived views the screens read, and the mutations.
///
/// Two modes. Without a [HouseholdApi] (tests, previews) the snapshot is
/// local: every mutation replaces it, notifies once and writes it through
/// the [SnapshotStore]. With one, the service tier holds the household: the
/// store serves the last answer from a versioned [HouseholdCache] while it
/// fetches, sends an edit and fetches again, refuses edits offline and to a
/// reader, and queues claims in a [ClaimOutbox] that is flushed in order.
/// Screens never touch storage or the network.
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
  MemberRole _role = MemberRole.editor;
  HouseholdView? _household;
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

  /// The household's members and this member's role, once fetched.
  HouseholdView? get household => _household;

  /// Whether this member may change the household at all.
  bool get canWrite => !remote || _role.canWrite;

  /// Whether an edit other than a claim can be made now.
  bool get canEdit => canWrite && !offline;

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
    _household = null;
    _pending = const [];
    _role = MemberRole.editor;
    await _cache.clear();
    await _outbox.save(const []);
    _rebuild();
    notifyListeners();
  }

  /// Whether the claim is still waiting in the outbox.
  bool isPending(String claimId) => _pending.any((p) => p.claim.id == claimId);

  /// Fetches the household, the role and the preferences, then sends any
  /// queued claims. A second call while one is running joins it.
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

  /// The instant, for the schedule and the nudge preview.
  DateTime get now => _clock();

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
      _role = cached.role;
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
      final data = await api.householdData();
      final household = await api.household();
      final role = household.role;
      final preferences = await api.preferences();
      _catalog = await api.catalog();
      _server = data;
      _household = household;
      _role = role;
      _preferences = preferences;
      _offline = false;
      await _cache.save(
        CachedHousehold(version: householdCacheVersion, data: data, role: role),
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
  /// with [problem] set, when it cannot be made.
  Future<bool> _edit(
    Future<void> Function(HouseholdApi api) call, {
    bool needsWrite = true,
  }) async {
    if (needsWrite && !canWrite) {
      _problem = readOnlyMessage;
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
          'This card follows the catalogue. Change the terms to make it '
              'your own first.',
        'label taken' => 'Another card is already called that.',
        'forbidden' => readOnlyMessage,
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

  // The household

  /// Makes an invite with `read` or `edit`; null, with [problem] set, when
  /// it cannot be made.
  Future<Invite?> createInvite(String role) async {
    Invite? invite;
    final done = await _edit((api) async {
      invite = await api.createInvite(role);
    });
    return done ? invite : null;
  }

  /// Joins the household of [code]. Leaving a household that holds cards
  /// needs [confirmLeave]; the answer says which case this is.
  Future<JoinOutcome> joinHousehold(
    String code, {
    bool confirmLeave = false,
  }) async {
    // Claims logged in this household are sent to it before leaving; if
    // they cannot be, neither can the join.
    await flush();
    if (hasPending) return JoinOutcome.offline;
    try {
      await _api!.acceptInvite(code, confirmLeave: confirmLeave);
    } on ApiOffline {
      _offline = true;
      notifyListeners();
      return JoinOutcome.offline;
    } on ApiError catch (e) {
      return switch (e.error) {
        'household holds cards' => JoinOutcome.holdsCards,
        'owner has members' => JoinOutcome.ownerHasMembers,
        'already a member' => JoinOutcome.alreadyMember,
        'invite used' => JoinOutcome.used,
        'invite expired' => JoinOutcome.expired,
        'not found' => JoinOutcome.notFound,
        _ => JoinOutcome.failed,
      };
    }
    // The old household's cache is not this one's.
    await _cache.clear();
    try {
      await refresh();
    } on Object {
      // Joined; the next refresh shows it.
    }
    return JoinOutcome.joined;
  }

  /// Turns a card the catalogue keeps up to date into one the household
  /// maintains: claims, history, enrolment and every member's silences go
  /// with it. The new card's id, or null with [problem] set.
  Future<String?> convertCard(String id) async {
    String? newId;
    final done = await _edit((api) async {
      newId = await api.convertCard(id);
    });
    return done ? newId : null;
  }

  /// The owner removes a member, who loses access at once.
  Future<bool> removeMember(String userId) =>
      _edit((api) => api.removeMember(userId));

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
      return _edit((api) => api.patchCard(id, body));
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
    if (remote &&
        !await _edit(
          (api) => api.setMute(cardId: id, muted: !isCardMuted(id)),
          needsWrite: false,
        )) {
      return;
    }
    _setPreferences(
      _preferences.copyWith(
        mutedCardIds: _toggled(_preferences.mutedCardIds, id),
      ),
    );
  }

  bool isCardMuted(String id) => _preferences.mutedCardIds.contains(id);

  Future<bool> archiveCard(String id) =>
      updateCard(id, (card) => card.copyWith(archived: true));

  /// Removes the card, its benefits and every claim on them.
  Future<void> deleteCard(String id) async {
    if (remote) {
      await _edit((api) => api.deleteCard(id));
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
      });
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
      lastCallOnly: draft.lastCallOnly,
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
        if (after.lastCallOnly != before.lastCallOnly)
          'lastCallOnly': after.lastCallOnly,
        if (after.active != before.active) 'active': after.active,
        if (after.optedOutAt != before.optedOutAt)
          'optedOutAt': after.optedOutAt,
        if (after.trackedFrom != before.trackedFrom)
          'trackedFrom': after.trackedFrom,
      };
      final terms = _terms(after);
      final termsChanged = '$terms' != '${_terms(before)}';
      if (state.isEmpty && !termsChanged) return true;
      return _edit((api) async {
        if (state.isNotEmpty) await api.putBenefitState(id, state);
        if (termsChanged) await api.putBenefit(id, terms);
      });
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
          'lastCallOnly',
          'active',
          'optedOutAt',
          'trackedFrom',
          'createdAt',
          'updatedAt',
        }.contains(key),
      );

  /// Silences or unsilences one credit, for this member only.
  Future<void> toggleBenefitMute(String id) async {
    if (remote &&
        !await _edit(
          (api) => api.setMute(benefitId: id, muted: !isBenefitMuted(id)),
          needsWrite: false,
        )) {
      return;
    }
    _setPreferences(
      _preferences.copyWith(
        mutedBenefitIds: _toggled(_preferences.mutedBenefitIds, id),
      ),
    );
  }

  bool isBenefitMuted(String id) => _preferences.mutedBenefitIds.contains(id);

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

  /// Records that the user has ticked the issuer's enrolment box.
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
      await _edit((api) => api.deleteBenefit(id));
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
      if (!canWrite) throw StateError(readOnlyMessage);
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
    await _edit((api) async {
      for (final id in sent) {
        await api.deleteClaim(id);
      }
    });
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
    if (remote &&
        !await _edit((api) => api.putPreferences(next), needsWrite: false)) {
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
      for (final instance in currentInstances(data, today, _preferences))
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

  Totals get totals =>
      totalsFor(instances, missed.fold(0, (sum, m) => sum + m.missedCents));

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

  /// The overlap group with this label among the visible instances, or null
  /// once a claim or the filter has dissolved it.
  OverlapGroup? overlapFor(String label) {
    for (final overlap in overlaps) {
      if (overlap.label == label) return overlap;
    }
    return null;
  }

  IsoDate? get nextResetOn => nextReset(instances);
  bool get hasCards => _data?.cards.any((card) => !card.archived) ?? false;
  int get cardCount => _data?.cards.where((card) => !card.archived).length ?? 0;
}

/// What joining a household by code came to.
enum JoinOutcome {
  joined,
  holdsCards,
  ownerHasMembers,
  alreadyMember,
  used,
  expired,
  notFound,
  offline,
  failed,
}
