import 'dart:convert';

import 'package:domain/domain.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'household_api.dart';

/// The shape of the cache on the device. Bump it when the cached JSON
/// changes: a cache of another version is discarded and fetched again,
/// with no migration chain on the device, because the server holds the
/// truth.
const householdCacheVersion = 1;

/// The last household the api served, kept for viewing offline.
class CachedHousehold {
  const CachedHousehold({
    required this.version,
    required this.data,
    required this.role,
  });

  final int version;
  final AppData data;
  final MemberRole role;
}

abstract interface class HouseholdCache {
  /// The cached household, or null when there is none or it cannot be read.
  Future<CachedHousehold?> load();
  Future<void> save(CachedHousehold cached);
  Future<void> clear();
}

class SharedPreferencesHouseholdCache implements HouseholdCache {
  const SharedPreferencesHouseholdCache({this.key = 'household-cache'});

  final String key;

  @override
  Future<CachedHousehold?> load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(key);
      if (raw == null) return null;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final version = json['version'] as int;
      // Another version's data may not even parse; only the number is read.
      if (version != householdCacheVersion) {
        return CachedHousehold(
          version: version,
          data: emptyHousehold,
          role: MemberRole.reader,
        );
      }
      return CachedHousehold(
        version: version,
        data: appDataFromJson(json['data'] as Map<String, dynamic>),
        role: MemberRole.values.byName(json['role'] as String),
      );
    } on Object {
      return null;
    }
  }

  @override
  Future<void> save(CachedHousehold cached) async =>
      (await SharedPreferences.getInstance()).setString(
        key,
        jsonEncode({
          'version': cached.version,
          'role': cached.role.name,
          'data': appDataToJson(cached.data),
        }),
      );

  @override
  Future<void> clear() async =>
      (await SharedPreferences.getInstance()).remove(key);
}

/// The cache in memory: tests.
class MemoryHouseholdCache implements HouseholdCache {
  CachedHousehold? saved;

  @override
  Future<CachedHousehold?> load() async => saved;

  @override
  Future<void> save(CachedHousehold cached) async => saved = cached;

  @override
  Future<void> clear() async => saved = null;
}

const emptyHousehold = AppData(
  version: 2,
  cards: [],
  benefits: [],
  claims: [],
  settings: Settings(useSoonDays: 30, theme: ThemeSetting.system),
);
