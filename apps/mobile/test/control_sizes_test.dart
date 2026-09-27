import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reward/theme/theme.dart';

/// Apple's HIG floor: every control is drawn 44 high, never more, and its
/// touch area is padded to 48 so Android's rule holds too. Chips are drawn
/// 40. The drawn part is the control's own [Material]; the widget's box
/// includes the tap padding.

const _brightnesses = {'light': Brightness.light, 'dark': Brightness.dark};

Future<void> _pump(
  WidgetTester tester,
  Brightness brightness,
  Widget child,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: nocturneTheme(brightness),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

/// The painted surface of the control [control] finds.
Size drawn(WidgetTester tester, Finder control) => tester.getSize(
  find.descendant(of: control, matching: find.byType(Material)).first,
);

void main() {
  // @lat: [[mobile-tests#Control sizes#Buttons are drawn 44 and respond to 48]]
  testWidgets('every kind of button is drawn 44 high and touches 48', (
    tester,
  ) async {
    final buttons = <String, Widget>{
      'filled': FilledButton(onPressed: () {}, child: const Text('Go')),
      'filled.icon': FilledButton.icon(
        onPressed: () {},
        icon: const Icon(Icons.add),
        label: const Text('Go'),
      ),
      'outlined': OutlinedButton(onPressed: () {}, child: const Text('Go')),
      'outlined.icon': OutlinedButton.icon(
        onPressed: () {},
        icon: const Icon(Icons.add),
        label: const Text('Go'),
      ),
      'text': TextButton(onPressed: () {}, child: const Text('Go')),
      'text.icon': TextButton.icon(
        onPressed: () {},
        icon: const Icon(Icons.add),
        label: const Text('Go'),
      ),
    };
    for (final MapEntry(key: theme, value: brightness)
        in _brightnesses.entries) {
      for (final MapEntry(key: name, value: button) in buttons.entries) {
        await _pump(
          tester,
          brightness,
          KeyedSubtree(key: Key(name), child: button),
        );
        final control = find.byKey(Key(name));
        expect(drawn(tester, control).height, 44, reason: '$theme $name');
        expect(
          tester.getSize(control).height,
          greaterThanOrEqualTo(48),
          reason: '$theme $name',
        );
      }
    }
  });

  // @lat: [[mobile-tests#Control sizes#Icon buttons are drawn 44 square]]
  testWidgets('an icon button is drawn 44 x 44 and touches 48 x 48', (
    tester,
  ) async {
    for (final brightness in _brightnesses.values) {
      await _pump(
        tester,
        brightness,
        IconButton(onPressed: () {}, icon: const Icon(Icons.settings)),
      );
      final control = find.byType(IconButton);
      expect(drawn(tester, control), const Size(44, 44));
      final target = tester.getSize(control);
      expect(target.width, greaterThanOrEqualTo(48));
      expect(target.height, greaterThanOrEqualTo(48));
      expect(tester.getSize(find.byType(Icon)), const Size(24, 24));
    }
  });

  // @lat: [[mobile-tests#Control sizes#Segmented buttons are drawn 44]]
  testWidgets('a segmented button is drawn 44 high and touches 48', (
    tester,
  ) async {
    for (final brightness in _brightnesses.values) {
      await _pump(
        tester,
        brightness,
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 1, label: Text('One')),
            ButtonSegment(value: 2, label: Text('Two')),
          ],
          selected: const {1},
          onSelectionChanged: (_) {},
        ),
      );
      // The segments fill the touch area; the outline is what is drawn.
      final control = find.byType(SegmentedButton<int>);
      final outline = <Rect>[];
      expect(
        tester.renderObject(
          find.descendant(
            of: control,
            matching: find.byWidgetPredicate(
              (w) => '${w.runtimeType}'.startsWith('_SegmentedButtonRender'),
            ),
          ),
        ),
        paints..something((method, args) {
          if (method != #drawRRect) return false;
          outline.add((args.first as RRect).outerRect);
          return true;
        }),
      );
      // The stroke is 1 wide and centred on the rounded rectangle.
      expect(outline.single.height + 1, 44);
      expect(tester.getSize(control).height, greaterThanOrEqualTo(48));
    }
  });

  // @lat: [[mobile-tests#Control sizes#Chips are drawn 40 and respond to 48]]
  testWidgets('choice and filter chips are drawn 40 high and touch 48', (
    tester,
  ) async {
    for (final brightness in _brightnesses.values) {
      for (final chip in <Widget>[
        ChoiceChip(
          label: const Text('Soon'),
          selected: true,
          onSelected: (_) {},
        ),
        ChoiceChip(
          label: const Text('Soon'),
          selected: false,
          onSelected: (_) {},
        ),
        FilterChip(
          label: const Text('Soon'),
          selected: true,
          onSelected: (_) {},
        ),
      ]) {
        await _pump(
          tester,
          brightness,
          KeyedSubtree(key: const Key('c'), child: chip),
        );
        final control = find.byKey(const Key('c'));
        expect(drawn(tester, control).height, 40);
        expect(tester.getSize(control).height, greaterThanOrEqualTo(48));
      }
    }
  });

  // @lat: [[mobile-tests#Control sizes#A selected chip shows a check mark]]
  testWidgets('a selected chip shows a check mark', (tester) async {
    for (final brightness in _brightnesses.values) {
      await _pump(
        tester,
        brightness,
        ChoiceChip(
          label: const Text('Soon'),
          selected: true,
          onSelected: (_) {},
        ),
      );
      await tester.pumpAndSettle();
      final selected = tester.getSize(find.byType(ChoiceChip));
      // The check mark widens the chip past its label and padding alone.
      await _pump(
        tester,
        brightness,
        ChoiceChip(
          label: const Text('Soon'),
          selected: false,
          onSelected: (_) {},
        ),
      );
      await tester.pumpAndSettle();
      final plain = tester.getSize(find.byType(ChoiceChip));
      expect(selected.width, greaterThan(plain.width));
      final theme = nocturneTheme(brightness);
      expect(theme.chipTheme.showCheckmark, isNot(false));
      expect(theme.chipTheme.checkmarkColor, isNotNull);
    }
  });
}
