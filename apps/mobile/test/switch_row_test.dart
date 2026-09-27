import 'package:flutter/material.dart';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reward/shell/router.dart';
import 'package:reward/theme/theme.dart';
import 'package:reward/widgets/switch_row.dart';

import 'credit_sheet_test.dart' as sheet;
import 'editors_test.dart' as editors;
import 'settings_screen_test.dart' as settings;

/// A switch row is one target: tapping anywhere on it, the title included,
/// flips it, and a screen reader hears its label and state as one node.

Future<void> tapTitle(WidgetTester tester, String title) async {
  final finder = find.text(title);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> pumpRow(WidgetTester tester, SwitchRow row) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: nocturneTheme(Brightness.light),
      home: Scaffold(body: row),
    ),
  );
}

void main() {
  group('tapping the title toggles', () {
    // @lat: [[mobile-tests#Switch rows#Tapping the title toggles on every screen]]
    testWidgets('Settings: Send me reminders', (tester) async {
      final store = await settings.pumpSettings(tester);
      expect(store.preferences.enabled, isFalse);
      await tapTitle(tester, 'Send me reminders');
      expect(store.preferences.enabled, isTrue);
    });

    testWidgets('credit sheet: Last call only and Silence this credit', (
      tester,
    ) async {
      final app = await sheet.openResy(tester, sheet.phone);
      final id = app.store.data!.benefits.first.id;
      await tapTitle(tester, 'Last call only');
      expect(app.store.data!.benefits.first.lastCallOnly, isTrue);
      await tapTitle(tester, 'Silence this credit');
      expect(app.store.isBenefitMuted(id), isTrue);
    });

    testWidgets('card editor: Silence every credit and Archive this card', (
      tester,
    ) async {
      final app = await editors.pumpAt(tester, cardPath(editors.jim));
      await tapTitle(tester, 'Silence every credit');
      expect(app.store.isCardMuted(editors.jim), isTrue);
      await tapTitle(tester, 'Archive this card');
      expect(editors.cardOf(app, editors.jim).archived, isTrue);
    });
  });

  // @lat: [[mobile-tests#Switch rows#A disabled row ignores taps]]
  testWidgets('a row without onChanged ignores a tap anywhere on it', (
    tester,
  ) async {
    await pumpRow(
      tester,
      const SwitchRow(
        title: 'Locked term',
        note: 'The catalogue owns it.',
        label: 'Locked term',
        value: false,
        onChanged: null,
      ),
    );
    await tester.tap(find.text('Locked term'));
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(
      tester.getSemantics(find.byType(SwitchRow)),
      containsSemantics(hasEnabledState: true, isEnabled: false),
    );
  });

  // @lat: [[mobile-tests#Switch rows#Each row is one semantics node]]
  testWidgets('a row is one node with its label, state and tap action', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var value = false;
    await pumpRow(
      tester,
      SwitchRow(
        title: 'Archive this card',
        note: 'Hides it everywhere and keeps its history.',
        label: 'Archive this card',
        value: value,
        onChanged: (next) => value = next,
      ),
    );
    final node = tester.getSemantics(find.byType(SwitchRow));
    expect(
      node,
      containsSemantics(
        label: 'Archive this card',
        hint: 'Hides it everywhere and keeps its history.',
        hasToggledState: true,
        isToggled: false,
        hasTapAction: true,
      ),
    );
    // Nothing inside the row is a node of its own.
    var children = 0;
    node.visitChildren((_) {
      children++;
      return true;
    });
    expect(children, 0);
    tester.semantics.tap(find.semantics.byLabel('Archive this card'));
    expect(value, isTrue);
    handle.dispose();
  });

  // @lat: [[mobile-tests#Switch rows#The credit sheet has no switch row of its own]]
  test('the credit sheet uses the shared switch row', () {
    expect(
      File('lib/widgets/credit_sheet.dart').readAsStringSync(),
      isNot(contains('class _SwitchRow')),
    );
  });
}
