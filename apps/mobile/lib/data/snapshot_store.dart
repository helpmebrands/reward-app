import 'dart:convert';

import 'package:domain/domain.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The PWA's defaults: reminders off at 09:00, early enough to act on the day
/// and late enough not to wake anyone, a $1 floor, a 30-day use-soon horizon.
const Settings defaultSettings = Settings(
  notifications: NotificationSettings(
    enabled: false,
    timeOfDay: '09:00',
    minValueCents: 100,
    annualFeeReminder: true,
    enrollmentReminder: true,
  ),
  useSoonDays: 30,
  theme: ThemeSetting.system,
  holderFilter: '',
);

/// Bump when a migration is needed.
const int dataVersion = 1;

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
}

/// The snapshot as one JSON string in shared preferences, under the same key
/// the PWA uses for its record.
class SharedPreferencesSnapshotStore implements SnapshotStore {
  const SharedPreferencesSnapshotStore({this.key = 'app-data'});

  final String key;

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
}

/// A store that keeps the snapshot in memory: tests and previews.
class MemorySnapshotStore implements SnapshotStore {
  MemorySnapshotStore([this.data]);

  AppData? data;

  @override
  Future<AppData?> load() async => data;

  @override
  Future<void> save(AppData data) async => this.data = data;
}
