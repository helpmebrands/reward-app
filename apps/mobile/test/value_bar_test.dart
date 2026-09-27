import 'package:domain/domain.dart' hide Tone;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reward/theme/nocturne_tokens.dart';
import 'package:reward/theme/theme.dart';
import 'package:reward/widgets/value_bar.dart';

/// The value bar: Earned · Available · Missed · Opt out, drawn from a
/// [ValueBreakdown] (`mobile-architecture#Value bar`).

const _segments = ['earned', 'available', 'missed', 'optOut'];

const fourSegments = ValueBreakdown(
  earnedCents: 54000,
  availableCents: 77000,
  missedCents: 18000,
  optOutCents: 36000,
);

Future<void> pumpBar(
  WidgetTester tester,
  ValueBreakdown breakdown, {
  double width = 360,
  double textScale = 1,
  Brightness brightness = Brightness.dark,
}) async {
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    MaterialApp(
      theme: nocturneTheme(brightness),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: ValueBar(breakdown: breakdown),
          ),
        ),
      ),
    ),
  );
}

Finder segment(String name) => find.byKey(Key('value-bar-segment-$name'));
Finder label(String name) => find.byKey(Key('value-bar-label-$name'));

void main() {
  // @lat: [[mobile-tests#Value bar#The four colours are tokens in both themes]]
  test('the bar colours are tokens with the designed values', () {
    const dark = NocturneTokens.dark;
    const light = NocturneTokens.light;
    expect(dark.valueEarned, const Color(0xFF6CC18E));
    expect(dark.valueAvailable, const Color(0xFFD16F84));
    expect(dark.valueMissed, const Color(0xFFE3C25B));
    expect(dark.valueOptOut, const Color(0xFF595D6C));
    expect(light.valueEarned, const Color(0xFF2E7D4F));
    expect(light.valueAvailable, const Color(0xFFB7576D));
    expect(light.valueMissed, const Color(0xFFA87F12));
    expect(light.valueOptOut, const Color(0xFFB9BBC5));
  });

  // @lat: [[mobile-tests#Value bar#Segments run in order, sized by amount]]
  testWidgets('segments run in order, proportional, 8 high with 2 gaps', (
    tester,
  ) async {
    await pumpBar(tester, fourSegments);
    final rects = [for (final s in _segments) tester.getRect(segment(s))];
    // 360 wide less three 2-pixel gaps, shared by amount.
    const drawn = 360 - 3 * 2;
    const total = 54000 + 77000 + 18000 + 36000;
    final amounts = [54000, 77000, 18000, 36000];
    for (var i = 0; i < 4; i++) {
      expect(rects[i].height, 8);
      expect(rects[i].width, moreOrLessEquals(amounts[i] / total * drawn));
      if (i > 0) expect(rects[i].left - rects[i - 1].right, moreOrLessEquals(2));
    }
    expect(rects.first.left, 0);
    expect(rects.last.right, moreOrLessEquals(360));

    final colours = [
      for (final s in _segments)
        (tester.widget<ColoredBox>(
          find.descendant(of: segment(s), matching: find.byType(ColoredBox)),
        )).color,
    ];
    const t = NocturneTokens.dark;
    expect(colours, [
      t.valueEarned,
      t.valueAvailable,
      t.valueMissed,
      t.valueOptOut,
    ]);
  });

  // @lat: [[mobile-tests#Value bar#A zero segment is not drawn]]
  testWidgets('a zero segment has no bar and no label', (tester) async {
    await pumpBar(
      tester,
      const ValueBreakdown(earnedCents: 3000, availableCents: 7000),
    );
    expect(segment('missed'), findsNothing);
    expect(segment('optOut'), findsNothing);
    expect(label('missed'), findsNothing);
    expect(tester.getRect(segment('earned')).width, moreOrLessEquals(358 * .3));
    expect(find.text('\$30'), findsOneWidget);
    expect(find.text('Earned'), findsOneWidget);
    expect(find.text('\$70'), findsOneWidget);
    expect(find.text('Available'), findsOneWidget);
  });

  // @lat: [[mobile-tests#Value bar#Labels sit centred under their segments]]
  testWidgets('each amount and label is centred under its segment', (
    tester,
  ) async {
    await pumpBar(
      tester,
      const ValueBreakdown(earnedCents: 50000, availableCents: 50000),
    );
    for (final s in ['earned', 'available']) {
      expect(
        tester.getCenter(label(s)).dx,
        moreOrLessEquals(tester.getCenter(segment(s)).dx, epsilon: 0.5),
      );
      expect(
        tester.getRect(label(s)).top,
        greaterThan(tester.getRect(segment(s)).bottom),
      );
    }
  });

  // @lat: [[mobile-tests#Value bar#Narrow neighbours never overlap]]
  testWidgets('narrow segments slide or wrap without overlap at 320 and 2x', (
    tester,
  ) async {
    await pumpBar(
      tester,
      const ValueBreakdown(
        earnedCents: 100000,
        availableCents: 500,
        missedCents: 500,
        optOutCents: 500,
      ),
      width: 320,
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
    final rects = [for (final s in _segments) tester.getRect(label(s))];
    for (final r in rects) {
      expect(r.left, greaterThanOrEqualTo(0));
      expect(r.right, lessThanOrEqualTo(320));
    }
    for (var i = 0; i < rects.length; i++) {
      for (var j = i + 1; j < rects.length; j++) {
        expect(
          rects[i].overlaps(rects[j]),
          isFalse,
          reason: '${_segments[i]} overlaps ${_segments[j]}',
        );
      }
    }
    // Everything the bar draws lies inside the widget.
    final bar = tester.getRect(find.byType(ValueBar));
    for (final r in rects) {
      expect(bar.contains(r.bottomRight - const Offset(0.01, 0.01)), isTrue);
    }
  });

  // @lat: [[mobile-tests#Value bar#The bar reads as one sentence]]
  testWidgets('the bar is one semantics node read as a sentence', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpBar(tester, fourSegments);
    expect(
      find.bySemanticsLabel(
        r'$540 earned, $770 available, $180 missed, $360 opt out',
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Earned'), findsNothing);
    expect(find.bySemanticsLabel(r'$540'), findsNothing);
    expect(
      valueBarSentence(
        const ValueBreakdown(earnedCents: 3000, availableCents: 7000),
      ),
      r'$30 earned, $70 available',
    );
    handle.dispose();
  });

  // @lat: [[mobile-tests#Value bar#An empty breakdown draws only the track]]
  testWidgets('an all-zero breakdown draws the track and no labels', (
    tester,
  ) async {
    await pumpBar(tester, ValueBreakdown.zero, brightness: Brightness.light);
    expect(find.byKey(const Key('value-bar-track')), findsOneWidget);
    expect(tester.getSize(find.byKey(const Key('value-bar-track'))).height, 8);
    for (final s in _segments) {
      expect(segment(s), findsNothing);
    }
    expect(find.byType(Text), findsNothing);
  });
}
