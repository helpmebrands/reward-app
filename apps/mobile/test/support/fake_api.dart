import 'package:domain/domain.dart';
import 'package:reward/data/household_api.dart';
import 'package:reward/data/snapshot_store.dart';

/// A fake service tier for widget and store tests: an in-memory household
/// that dedupes claims by idempotency key as the real api does, and records
/// the household calls it is sent.

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
  lastCallOnly: false,
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
  FakeApi({AppData? data, this.role = MemberRole.editor})
    : data = data ?? serverHousehold();

  AppData data;
  MemberRole role;
  bool online = true;
  int claimPosts = 0;
  final _claimsByKey = <String, Claim>{};

  void _check() {
    if (!online) throw const ApiOffline();
  }

  @override
  Future<AppData> householdData() async {
    _check();
    return data;
  }

  final members = <HouseholdMember>[
    const HouseholdMember(
      userId: 'user-owner',
      email: 'ann@example.com',
      role: MemberRole.owner,
    ),
  ];

  @override
  Future<HouseholdView> household() async {
    _check();
    return HouseholdView(id: 'household-1', role: role, members: members);
  }

  /// Invites made, by role; what the next accept answers.
  final invites = <String>[];
  Object? acceptAnswer;
  final accepted = <({String code, bool confirmLeave})>[];
  final removed = <String>[];

  @override
  Future<Invite> createInvite(String role) async {
    _check();
    invites.add(role);
    return Invite(
      code: 'ABCD2345',
      link: 'https://api.test/invite/ABCD2345',
      role: role,
      expiresAt: '2026-09-23T10:00:00.000Z',
    );
  }

  @override
  Future<void> acceptInvite(String code, {bool confirmLeave = false}) async {
    _check();
    accepted.add((code: code, confirmLeave: confirmLeave));
    final answer = acceptAnswer;
    if (answer is ApiError &&
        !(answer.error == 'household holds cards' && confirmLeave)) {
      throw answer;
    }
    role = MemberRole.editor;
  }

  @override
  Future<void> removeMember(String userId) async {
    _check();
    removed.add(userId);
    members.removeWhere((m) => m.userId == userId);
  }

  @override
  Future<MemberPreferences> preferences() async {
    _check();
    return defaultMemberPreferences;
  }

  @override
  Future<void> putPreferences(MemberPreferences preferences) async => _check();

  @override
  Future<void> setMute({
    String? cardId,
    String? benefitId,
    required bool muted,
  }) async => _check();

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

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
