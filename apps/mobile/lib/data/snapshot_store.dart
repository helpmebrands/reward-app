import 'dart:convert';

import 'package:domain/domain.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The PWA's defaults: a 30-day use-soon horizon. Reminder settings are the
/// member's, from `defaultMemberPreferences`.
const Settings defaultSettings = Settings(
  useSoonDays: 30,
  theme: ThemeSetting.system,
);

/// Bump when a migration is needed. 1: the launch shape. 2: `Card.kind`,
/// which `cardFromJson` defaults to personal on an older record.
const int dataVersion = 2;

/// A fresh install's household: nothing but the defaults.
AppData emptyAppData() => const AppData(
  version: dataVersion,
  cards: [],
  benefits: [],
  claims: [],
  settings: defaultSettings,
);

/// Where the one `AppData` snapshot lives. A household's cards, benefits and
/// claims are measured in kilobytes, so one record is cheaper and simpler
/// than per-entity stores, as in the PWA's single IndexedDB record.
abstract interface class SnapshotStore {
  /// The saved snapshot, or null on a fresh install. Never throws: a
  /// corrupt record starts the app empty, because empty is recoverable and a
  /// crash is not.
  Future<AppData?> load();

  Future<void> save(AppData data);

  /// This member's saved preferences, or null when none are saved yet.
  /// Never throws, for the same reason as [load].
  Future<MemberPreferences?> loadPreferences();

  /// Kept apart from the snapshot: the household's data is shared, a
  /// member's reminder settings and mutes are not.
  Future<void> savePreferences(MemberPreferences preferences);
}

/// The snapshot as one JSON string in shared preferences, under the same key
/// the PWA uses for its record.
class SharedPreferencesSnapshotStore implements SnapshotStore {
  const SharedPreferencesSnapshotStore({
    this.key = 'app-data',
    this.preferencesKey = 'member-preferences',
  });

  final String key;
  final String preferencesKey;

  @override
  Future<AppData?> load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(key);
      if (raw == null) return null;
      return appDataFromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> save(AppData data) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(key, jsonEncode(appDataToJson(data)));
  }

  @override
  Future<MemberPreferences?> loadPreferences() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(preferencesKey);
      if (raw == null) return null;
      return memberPreferencesFromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> savePreferences(MemberPreferences member) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      preferencesKey,
      jsonEncode(memberPreferencesToJson(member)),
    );
  }
}

/// A store that keeps the snapshot in memory: tests and previews.
class MemorySnapshotStore implements SnapshotStore {
  MemorySnapshotStore([this.data, this.preferences]);

  AppData? data;
  MemberPreferences? preferences;

  @override
  Future<AppData?> load() async => data;

  @override
  Future<void> save(AppData data) async => this.data = data;

  @override
  Future<MemberPreferences?> loadPreferences() async => preferences;

  @override
  Future<void> savePreferences(MemberPreferences preferences) async =>
      this.preferences = preferences;
}
