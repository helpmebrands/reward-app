import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reward/data/snapshot_store.dart';
import 'package:reward/logic/app_store.dart';
import 'package:reward/logic/ui_state.dart';
import 'package:reward/main.dart';
import 'package:reward/screens/settings_screen.dart';
import 'package:reward/shell/router.dart';

/// Settings: reminder preferences, the ladder table and the theme, with the
/// theme override driven by the store.

AppData sampleHousehold() => appDataFromJson(
  jsonDecode(File('../pwa/samples/sample-household.json').readAsStringSync())
      as Map<String, dynamic>,
);

final DateTime now = DateTime(2026, 9, 16, 8);

Future<AppStore> pumpSettings(
  WidgetTester tester, {
  AppData? data,
  MemorySnapshotStore? memory,
  Size size = const Size(402, 874),
  double textScale = 1,
  String location = Paths.settings,
}) async {
  final store = AppStore(
    store: memory ?? MemorySnapshotStore(data ?? sampleHousehold()),
    clock: () => now,
  );
  await store.load();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    RewardApp(store: store, ui: UiState(), initialLocation: location),
  );
  await tester.pumpAndSettle();
  return store;
}

NotificationSettings notifications(AppStore store) =>
    store.data!.settings.notifications;

Future<void> flip(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.bySemanticsLabel(label));
  await tester.pumpAndSettle();
  await tester.tap(find.bySemanticsLabel(label));
  await tester.pumpAndSettle();
}

void main() {
  // @lat: [[mobile-tests#Settings#Each reminder control writes its field and reflects it]]
  testWidgets('the reminder controls write the store and read it back', (
    tester,
  ) async {
    final memory = MemorySnapshotStore(sampleHousehold());
    final store = await pumpSettings(tester, memory: memory);
    expect(find.text('Settings'), findsOneWidget);
    expect(notifications(store).enabled, isFalse);
    expect(find.byKey(const Key('field-time')), findsNothing);

    await flip(tester, 'Send me reminders');
    expect(notifications(store).enabled, isTrue);
    expect(find.byKey(const Key('field-time')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('field-time')), '08:30');
    await tester.pumpAndSettle();
    expect(notifications(store).timeOfDay, '08:30');

    await flip(tester, 'Nudge me about locked credits');
    expect(notifications(store).enrollmentReminder, isFalse);

    // A fresh app over the same saved snapshot shows what was written.
    final again = await pumpSettings(tester, memory: memory);
    expect(notifications(again).enabled, isTrue);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('field-time')))
          .controller!
          .text,
      '08:30',
    );
    final handle = tester.ensureSemantics();
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Nudge me about locked credits'))
          .getSemanticsData()
          .flagsCollection
          .isToggled,
      Tristate.isFalse,
    );
    handle.dispose();
  });

  // @lat: [[mobile-tests#Settings#A bad minimum shows the error and writes nothing]]
  testWidgets('an invalid minimum shows the error on blur and is not written', (
    tester,
  ) async {
    final store = await pumpSettings(tester);
    await flip(tester, 'Send me reminders');

    await tester.enterText(find.byKey(const Key('field-min-value')), 'abc');
    await tester.pumpAndSettle();
    expect(find.text('Enter the amount as a number, like 695.'), findsNothing);
    await tester.tap(find.byKey(const Key('field-time')));
    await tester.pumpAndSettle();
    expect(
      find.text('Enter the amount as a number, like 695.'),
      findsOneWidget,
    );
    expect(notifications(store).minValueCents, 100);

    await tester.enterText(find.byKey(const Key('field-min-value')), '5');
    await tester.pumpAndSettle();
    expect(notifications(store).minValueCents, 500);
    expect(find.text('Enter the amount as a number, like 695.'), findsNothing);
  });

  // @lat: [[mobile-tests#Settings#Choosing Dark overrides the platform and System follows it again]]
  testWidgets('Dark switches the theme mode while the platform is light', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final store = await pumpSettings(tester);
    MaterialApp app() => tester.widget<MaterialApp>(find.byType(MaterialApp));
    Brightness shown() =>
        Theme.of(tester.element(find.text('Appearance'))).brightness;
    expect(app().themeMode, ThemeMode.system);
    expect(shown(), Brightness.light);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(store.data!.settings.theme, ThemeSetting.dark);
    expect(app().themeMode, ThemeMode.dark);
    expect(shown(), Brightness.dark);

    await tester.tap(find.text('System'));
    await tester.pumpAndSettle();
    expect(app().themeMode, ThemeMode.system);
    expect(shown(), Brightness.light);

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(app().themeMode, ThemeMode.light);
  });

  // @lat: [[mobile-tests#Settings#The ladder table lists the four cadences]]
  testWidgets('the ladder table shows each cadence with its rungs', (
    tester,
  ) async {
    await pumpSettings(tester, size: const Size(402, 2000));
    for (final cadence in [
      Cadence.monthly,
      Cadence.quarterly,
      Cadence.semiannual,
      Cadence.annual,
    ]) {
      final row = find.byKey(ValueKey('ladder-${cadence.name}'));
      expect(row, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.text(cadenceLabel(cadence))),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text(ladderSummary(cadence))),
        findsOneWidget,
      );
    }
    expect(find.byKey(const ValueKey('ladder-manual')), findsNothing);
  });

  // @lat: [[mobile-tests#Settings#Settings keeps one column and survives 200%]]
  testWidgets('one column at 1280 and nothing overflows at 2.0', (
    tester,
  ) async {
    final store = await pumpSettings(tester, size: const Size(1280, 800));
    await flip(tester, 'Send me reminders');
    expect(notifications(store).enabled, isTrue);
    expect(
      tester.getSize(find.byKey(const Key('field-min-value'))).width,
      720 - 2 * 28,
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('field-min-value'))).dy,
      greaterThan(
        tester.getBottomLeft(find.byKey(const Key('field-time'))).dy - 1,
      ),
    );

    await pumpSettings(tester, size: const Size(402, 4000), textScale: 2);
    await flip(tester, 'Send me reminders');
    expect(tester.takeException(), isNull);
    final texts = find.byType(Text, skipOffstage: false);
    for (var i = 0; i < texts.evaluate().length; i++) {
      expect(
        tester.getRect(texts.at(i)).right,
        lessThanOrEqualTo(402.5),
        reason: tester.widget<Text>(texts.at(i)).data,
      );
    }
  });

  // @lat: [[mobile-tests#Settings#Every switch and segment has a label and a state]]
  testWidgets('switches and theme segments carry labels and state', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpSettings(tester);
    await flip(tester, 'Send me reminders');

    for (final label in [
      'Send me reminders',
      'Nudge me about locked credits',
    ]) {
      final node = tester.getSemantics(find.bySemanticsLabel(label));
      expect(
        node.getSemanticsData().flagsCollection.isToggled,
        isNot(Tristate.none),
      );
    }
    expect(find.bySemanticsLabel('Appearance'), findsOneWidget);
    SemanticsNode segment(String text) => tester.getSemantics(find.text(text));
    expect(
      segment('System').getSemanticsData().flagsCollection.isSelected,
      Tristate.isTrue,
    );
    expect(
      segment('Dark').getSemanticsData().flagsCollection.isSelected,
      Tristate.isFalse,
    );
    handle.dispose();
  });

  // @lat: [[mobile-tests#Settings#Today leads to Settings]]
  testWidgets('the gear on Today opens Settings', (tester) async {
    await pumpSettings(tester, location: Paths.today);
    expect(find.byType(SettingsScreen), findsNothing);

    await tester.tap(find.bySemanticsLabel('Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  });
}
