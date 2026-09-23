import 'dart:convert';
import 'dart:io';

import 'package:domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reward/data/snapshot_store.dart';
import 'package:reward/logic/app_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

AppData sampleHousehold() => appDataFromJson(
  jsonDecode(File('../pwa/samples/sample-household.json').readAsStringSync())
      as Map<String, dynamic>,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // @lat: [[mobile-tests#Store#A snapshot round-trips through shared preferences]]
  test('round-trips the sample household through shared preferences', () async {
    SharedPreferences.setMockInitialValues({});
    const store = SharedPreferencesSnapshotStore();
    expect(await store.load(), isNull);

    final data = sampleHousehold();
    await store.save(data);
    final loaded = await store.load();
    expect(loaded, isNotNull);
    expect(appDataToJson(loaded!), appDataToJson(data));
    expect(
      (await SharedPreferences.getInstance()).getString('app-data'),
      isNotNull,
    );
  });

  // @lat: [[mobile-tests#Store#A corrupt snapshot starts the app empty]]
  test('starts empty rather than crashing on a corrupt record', () async {
    SharedPreferences.setMockInitialValues({'app-data': '{"hello":'});
    expect(await const SharedPreferencesSnapshotStore().load(), isNull);
  });

  // @lat: [[mobile-tests#Store#The app store resolves today's instances]]
  test(
    'the app store loads the snapshot and resolves instances for today',
    () async {
      final store = AppStore(
        store: MemorySnapshotStore(sampleHousehold()),
        clock: () => DateTime(2026, 9, 16),
      );
      expect(store.loading, isTrue);
      await store.load();
      expect(store.loading, isFalse);
      expect(store.hasCards, isTrue);
      expect(store.cardCount, 2);
      expect(store.soon.first.benefit.name, 'Resy Dining Credit');
      expect(store.totals.claimableCents, 189890);
      expect(store.nextResetOn, '2026-09-30');
    },
  );
}
