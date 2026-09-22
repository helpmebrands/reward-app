import 'dart:convert';
import 'dart:io';

import 'package:domain/domain.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reward/data/snapshot_store.dart';
import 'package:reward/logic/app_store.dart';
import 'package:reward/logic/snackbar_state.dart';
import 'package:reward/logic/ui_state.dart';
import 'package:reward/main.dart';
import 'package:reward/theme/theme.dart';
import 'package:reward/widgets/snackbar_host.dart';

/// The snackbar: an undo stays up twenty seconds, its clock stops while the
/// Undo has focus or the pointer, and it centres on the content column.

Finder get bar => find.byKey(const Key('snackbar'));
Finder get undo => find.byKey(const Key('snackbar-action'));

Future<SnackbarState> pumpHost(WidgetTester tester) async {
  final snackbar = SnackbarState();
  addTearDown(snackbar.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: nocturneTheme(Brightness.dark),
      home: Scaffold(
        body: SnackbarHost(
          snackbar: snackbar,
          child: const Center(child: Text('screen')),
        ),
      ),
    ),
  );
  return snackbar;
}

SnackbarAction noop({String? semanticsLabel}) =>
    SnackbarAction(label: 'Undo', semanticsLabel: semanticsLabel, onAct: () {});

void main() {
  // @lat: [[mobile-tests#Snackbar#An undo stays up for twenty seconds]]
  testWidgets('an undo is still there at 19 seconds and gone at 21', (
    tester,
  ) async {
    final snackbar = await pumpHost(tester);
    snackbar.show('Logged \$10 on Uber Cash.', action: noop());
    await tester.pump();
    expect(bar, findsOneWidget);

    await tester.pump(const Duration(seconds: 19));
    expect(bar, findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(bar, findsNothing);
  });

  // @lat: [[mobile-tests#Snackbar#A plain message leaves sooner]]
  testWidgets('a message without an action leaves after 3.5 seconds', (
    tester,
  ) async {
    final snackbar = await pumpHost(tester);
    snackbar.show('That did not look like an amount.');
    await tester.pump();
    expect(undo, findsNothing);

    await tester.pump(const Duration(seconds: 3));
    expect(bar, findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(bar, findsNothing);
  });

  // @lat: [[mobile-tests#Snackbar#Focus pauses the timer and leaving restarts it]]
  testWidgets('focus on Undo holds the snackbar and blur restarts the 20', (
    tester,
  ) async {
    final snackbar = await pumpHost(tester);
    snackbar.show('Logged \$10 on Uber Cash.', action: noop());
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));

    final node = Focus.of(tester.element(find.text('Undo')));
    node.requestFocus();
    await tester.pump();
    await tester.pump(const Duration(seconds: 25)); // t = 30, past the limit
    expect(bar, findsOneWidget);

    node.unfocus();
    await tester.pump();
    await tester.pump(const Duration(seconds: 19)); // t = 49
    expect(bar, findsOneWidget);
    await tester.pump(const Duration(seconds: 2)); // t = 51
    expect(bar, findsNothing);
  });

  // @lat: [[mobile-tests#Snackbar#The pointer pauses the timer too]]
  testWidgets('a pointer over the snackbar holds it and leaving restarts', (
    tester,
  ) async {
    final snackbar = await pumpHost(tester);
    snackbar.show('Logged \$10 on Uber Cash.', action: noop());
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(bar));
    await tester.pump();
    await tester.pump(const Duration(seconds: 25));
    expect(bar, findsOneWidget);

    await mouse.moveTo(const Offset(1, 1));
    await tester.pump();
    await tester.pump(const Duration(seconds: 19));
    expect(bar, findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(bar, findsNothing);
  });

  // @lat: [[mobile-tests#Snackbar#The undo button says what it undoes]]
  testWidgets('the Undo button carries the action label and acts once', (
    tester,
  ) async {
    final snackbar = await pumpHost(tester);
    var acted = 0;
    snackbar.show(
      'Logged \$10 on Uber Cash.',
      action: SnackbarAction(
        label: 'Undo',
        semanticsLabel: 'Undo logging Uber Cash',
        onAct: () => acted++,
      ),
    );
    await tester.pump();

    expect(find.bySemanticsLabel('Undo logging Uber Cash'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    expect(find.text('Logged \$10 on Uber Cash.'), findsOneWidget);

    await tester.tap(undo);
    await tester.pump();
    expect(acted, 1);
    expect(bar, findsNothing);
  });

  // @lat: [[mobile-tests#Snackbar#A newer message replaces the older]]
  testWidgets('a second message replaces the first and restarts the clock', (
    tester,
  ) async {
    final snackbar = await pumpHost(tester);
    snackbar.show('First.', action: noop());
    await tester.pump();
    await tester.pump(const Duration(seconds: 15));
    snackbar.show('Second.', action: noop());
    await tester.pump();

    expect(find.text('First.'), findsNothing);
    expect(find.text('Second.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 15)); // 30 since the first
    expect(find.text('Second.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    expect(bar, findsNothing);
  });

  group('in the shell', () {
    AppData sampleHousehold() => appDataFromJson(
      jsonDecode(
            File('../pwa/samples/sample-household.json').readAsStringSync(),
          )
          as Map<String, dynamic>,
    );

    Future<UiState> pumpApp(WidgetTester tester, Size size) async {
      final store = AppStore(
        store: MemorySnapshotStore(sampleHousehold()),
        clock: () => DateTime(2026, 9, 16),
      );
      await store.load();
      final ui = UiState();
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(RewardApp(store: store, ui: ui));
      await tester.pumpAndSettle();
      ui.snackbar.show('Logged \$15 on Uber Cash.', action: noop());
      await tester.pump();
      return ui;
    }

    // @lat: [[mobile-tests#Snackbar#The snackbar centres on the content column]]
    testWidgets('at 1280 it centres on the column, not the window', (
      tester,
    ) async {
      await pumpApp(tester, const Size(1280, 800));

      final column = tester.getRect(find.byKey(const Key('content-column')));
      final rect = tester.getRect(bar);
      expect(column.center.dx, isNot(closeTo(640, 1)));
      expect(rect.center.dx, closeTo(column.center.dx, 1));
      expect(rect.width, lessThanOrEqualTo(column.width));
    });

    // @lat: [[mobile-tests#Snackbar#The snackbar sits above the bar on a phone]]
    testWidgets('at 402 it sits above the navigation bar', (tester) async {
      await pumpApp(tester, const Size(402, 874));

      final rect = tester.getRect(bar);
      final nav = tester.getRect(find.byType(NavigationBar));
      expect(rect.bottom, lessThanOrEqualTo(nav.top));
      expect(rect.center.dx, closeTo(201, 1));
    });
  });
}
