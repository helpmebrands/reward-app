import 'dart:convert';

import 'package:domain/domain.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A claim logged on the device and not yet accepted by the api, with the
/// idempotency key it is sent under every time, so a retry can never make a
/// second claim.
class PendingClaim {
  const PendingClaim({required this.key, required this.claim});

  final String key;

  /// As shown until the api answers; its id is local.
  final Claim claim;

  /// What the api is sent.
  Map<String, Object?> get body => {
    'benefitId': claim.benefitId,
    'cycleKey': claim.cycleKey,
    'amountCents': claim.amountCents,
    'claimedAt': claim.claimedAt,
    'note': ?claim.note,
  };
}

/// The claims waiting for the network, in the order they were logged. Kept
/// apart from the household cache, so discarding the cache never loses one.
abstract interface class ClaimOutbox {
  Future<List<PendingClaim>> load();
  Future<void> save(List<PendingClaim> pending);
}

class SharedPreferencesClaimOutbox implements ClaimOutbox {
  const SharedPreferencesClaimOutbox({this.key = 'claim-outbox'});

  final String key;

  @override
  Future<List<PendingClaim>> load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(key);
      if (raw == null) return [];
      return [
        for (final entry in jsonDecode(raw) as List)
          PendingClaim(
            key: (entry as Map)['key'] as String,
            claim: claimFromJson(entry['claim'] as Map<String, dynamic>),
          ),
      ];
    } on Object {
      return [];
    }
  }

  @override
  Future<void> save(List<PendingClaim> pending) async =>
      (await SharedPreferences.getInstance()).setString(
        key,
        jsonEncode([
          for (final p in pending)
            {'key': p.key, 'claim': claimToJson(p.claim)},
        ]),
      );
}

/// The outbox in memory: tests.
class MemoryClaimOutbox implements ClaimOutbox {
  List<PendingClaim> _pending = [];

  @override
  Future<List<PendingClaim>> load() async => List.of(_pending);

  @override
  Future<void> save(List<PendingClaim> pending) async =>
      _pending = List.of(pending);
}
