import 'package:domain/domain.dart';
import 'package:flutter/foundation.dart';

import '../data/snapshot_store.dart';
import 'ids.dart';

/// The app store: the one `AppData` snapshot, today's date, the derived views
/// the screens read, and the PWA's mutations. Every mutation replaces the
/// snapshot, notifies once, then writes it through the [SnapshotStore];
/// screens never touch storage.
class AppStore extends ChangeNotifier {
  AppStore({required SnapshotStore store, DateTime Function()? clock})
    // ignore: prefer_initializing_formals
    : _store = store,
      _clock = clock ?? DateTime.now;

  final SnapshotStore _store;
  final DateTime Function() _clock;

  AppData? _data;
  bool _loading = true;

  /// Set by any mutation. In the app the UI is gated on [loading], but a
  /// caller that writes before the snapshot arrives must not have its change
  /// discarded when the read resolves: the user's action wins, as in the PWA.
  bool _hasLocalChanges = false;

  /// The snapshot, or null before [load] completes or on a fresh install.
  AppData? get data => _data;
  bool get loading => _loading;

  /// The user's local calendar date. Re-read on every access so an app
  /// resumed the next morning shows that morning's deadlines.
  IsoDate get today => todayIso(_clock());

  IsoInstant get _now => _clock().toUtc().toIso8601String();

  Future<void> load() async {
    final loaded = await _store.load();
    if (!_hasLocalChanges) _data = loaded;
    _loading = false;
    notifyListeners();
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
    required String holder,
    String? nickname,
    String? last4,
    IsoDate? anniversaryOn,
    String? issuer,
    String? product,
  }) async {
    final now = _now;
    final card = Card(
      id: newId(),
      issuer: issuer ?? template.issuer,
      product: product ?? template.product,
      holder: holder,
      nickname: nickname,
      network: template.network,
      last4: last4,
      annualFeeCents: template.annualFeeCents,
      anniversaryOn: anniversaryOn ?? today,
      muted: false,
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

  Future<void> updateCard(String id, Card Function(Card card) patch) {
    final data = _current;
    return _commit(
      data.copyWith(
        cards: [
          for (final card in data.cards)
            card.id == id ? patch(card).copyWith(updatedAt: _now) : card,
        ],
      ),
    );
  }

  Future<void> toggleCardMute(String id) =>
      updateCard(id, (card) => card.copyWith(muted: !card.muted));

  Future<void> archiveCard(String id) =>
      updateCard(id, (card) => card.copyWith(archived: true));

  /// Removes the card, its benefits and every claim on them.
  Future<void> deleteCard(String id) {
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
      enrollmentRequired: draft.enrollmentRequired,
      enrolledAt: draft.enrolledAt,
      enrollmentNote: draft.enrollmentNote,
      enrollmentUrl: draft.enrollmentUrl,
      redemptionSteps: draft.redemptionSteps,
      notes: draft.notes,
      muted: draft.muted,
      lastCallOnly: draft.lastCallOnly,
      active: draft.active,
      createdAt: now,
      updatedAt: now,
    );
    final data = _current;
    await _commit(data.copyWith(benefits: [...data.benefits, benefit]));
    return benefit;
  }

  Future<void> updateBenefit(
    String id,
    Benefit Function(Benefit benefit) patch,
  ) {
    final data = _current;
    return _commit(
      data.copyWith(
        benefits: [
          for (final benefit in data.benefits)
            benefit.id == id
                ? patch(benefit).copyWith(updatedAt: _now)
                : benefit,
        ],
      ),
    );
  }

  Future<void> toggleBenefitMute(String id) =>
      updateBenefit(id, (b) => b.copyWith(muted: !b.muted));

  /// Records that the user has ticked the issuer's enrolment box.
  Future<void> confirmEnrollment(String id) =>
      updateBenefit(id, (b) => b.copyWith(enrolledAt: _now));

  Future<void> revokeEnrollment(String id) =>
      updateBenefit(id, (b) => b.copyWith(enrolledAt: null));

  /// Removes the benefit and its claims.
  Future<void> deleteBenefit(String id) {
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
    final data = _current;
    await _commit(data.copyWith(claims: [...data.claims, claim]));
    return claim;
  }

  /// Removes every claim recorded against one cycle.
  Future<void> unclaim(String benefitId, IsoDate cycleKey) {
    final data = _current;
    return _commit(
      data.copyWith(
        claims: data.claims
            .where((c) => !(c.benefitId == benefitId && c.cycleKey == cycleKey))
            .toList(),
      ),
    );
  }

  /// Removes one claim, leaving the rest of the cycle's history alone.
  Future<void> removeClaim(String id) {
    final data = _current;
    return _commit(
      data.copyWith(claims: data.claims.where((c) => c.id != id).toList()),
    );
  }

  // Settings

  Future<void> updateSettings(Settings Function(Settings settings) patch) {
    final data = _current;
    return _commit(data.copyWith(settings: patch(data.settings)));
  }

  Future<void> updateNotificationSettings(
    NotificationSettings Function(NotificationSettings notifications) patch,
  ) => updateSettings((s) => s.copyWith(notifications: patch(s.notifications)));

  // Derived views

  /// Every active credit resolved against today, narrowed by the household
  /// filter, by urgency.
  List<BenefitInstance> get instances {
    final data = _data;
    if (data == null) return const [];
    final all = currentInstances(data, today);
    final holder = data.settings.holderFilter;
    return holder.isEmpty
        ? all
        : all.where((i) => i.card.holder == holder).toList();
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
  IsoDate? get nextResetOn => nextReset(instances);
  bool get hasCards => _data?.cards.any((card) => !card.archived) ?? false;
  int get cardCount => _data?.cards.where((card) => !card.archived).length ?? 0;
}
