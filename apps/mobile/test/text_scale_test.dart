import 'dart:convert';
import 'dart:io';

import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reward/data/snapshot_store.dart';
import 'package:reward/logic/app_store.dart';
import 'package:reward/screens/today_screen.dart';
import 'package:reward/theme/theme.dart';
import 'package:reward/widgets/credit_row.dart';

/// WCAG 1.4.4 in Flutter terms: text follows the platform size to 200%
/// without clipping or overlap (`mobile-architecture#Accessibility`).

AppData sampleHousehold() => appDataFromJson(
  jsonDecode(File('../pwa/samples/sample-household.json').readAsStringSync())
      as Map<String, dynamic>,
);

const viewport = Size(402, 6000);

Future<void> pumpTodayAt2x(WidgetTester tester) async {
  final store = AppStore(
    store: MemorySnapshotStore(sampleHousehold()),
    clock: () => DateTime(2026, 9, 16),
  );
  await store.load();
  tester.platformDispatcher.textScaleFactorTestValue = 2.0;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: nocturneTheme(Brightness.dark),
      home: Scaffold(body: TodayScreen(store: store)),
    ),
  );
  await tester.pumpAndSettle();
}

Iterable<File> dartFilesUnder(String dir) => Directory(dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

/// The painted rectangle of every text on screen.
List<Rect> textRects(WidgetTester tester) {
  final texts = find.byType(Text);
  return [
    for (var i = 0; i < texts.evaluate().length; i++)
      tester.getRect(texts.at(i)),
  ];
}

void main() {
  // @lat: [[mobile-tests#Text scaling#No widget overrides the platform text scale]]
  test('nothing under lib/ sets a text scaler or scale factor', () {
    for (final file in dartFilesUnder('lib')) {
      final source = file.readAsStringSync();
      expect(source, isNot(contains('textScaler')), reason: file.path);
      expect(source, isNot(contains('textScaleFactor')), reason: file.path);
    }
  });

  // @lat: [[mobile-tests#Text scaling#Today at 200% neither overflows nor clips]]
  testWidgets('today at 2.0 reports no overflow and clips no text', (
    tester,
  ) async {
    await pumpTodayAt2x(tester);
    expect(tester.takeException(), isNull);
    final paragraphs = tester.renderObjectList<RenderParagraph>(
      find.byType(RichText),
    );
    expect(paragraphs, isNotEmpty);
    for (final paragraph in paragraphs) {
      expect(
        paragraph.didExceedMaxLines,
        isFalse,
        reason: paragraph.text.toPlainText(),
      );
    }
    for (final rect in textRects(tester)) {
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(viewport.width));
    }
  });

  // @lat: [[mobile-tests#Text scaling#Controls and text do not overlap at 200%]]
  testWidgets('no two texts and no two rows overlap at 2.0', (tester) async {
    await pumpTodayAt2x(tester);
    final rows = find.byType(CreditRow);
    final boxes = [
      for (var i = 0; i < rows.evaluate().length; i++)
        tester.getRect(rows.at(i)),
      ...textRects(tester),
    ];
    for (var a = 0; a < boxes.length; a++) {
      for (var b = a + 1; b < boxes.length; b++) {
        final overlap = boxes[a].deflate(0.5).intersect(boxes[b].deflate(0.5));
        final nested =
            boxes[a].contains(boxes[b].topLeft) &&
            boxes[a].contains(boxes[b].bottomRight);
        final nestedBack =
            boxes[b].contains(boxes[a].topLeft) &&
            boxes[b].contains(boxes[a].bottomRight);
        if (nested || nestedBack) continue; // a text inside its row
        expect(
          overlap.isEmpty,
          isTrue,
          reason: '${boxes[a]} overlaps ${boxes[b]}',
        );
      }
    }
  });

  // @lat: [[mobile-tests#Text scaling#The headline shrinks to fit at 200%]]
  testWidgets('the headline number shrinks to its column at 2.0', (
    tester,
  ) async {
    await pumpTodayAt2x(tester);
    final amount = find.byKey(const Key('today-amount'));
    final painted = tester.getRect(amount);
    final natural = tester.getSize(amount);
    expect(painted.width, lessThan(natural.width));
    expect(painted.right, lessThanOrEqualTo(viewport.width - 20));
  });
}
