import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reward/theme/theme.dart';
import 'package:reward/widgets/field.dart';

/// The form field pattern: a labelled control with a hint and an error slot,
/// where the error shows once the field has been left or the form submitted,
/// never on the first keystroke.

const error = 'Enter whose card this is.';

class _Harness extends StatefulWidget {
  const _Harness({this.submitted = false});

  final bool submitted;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  final FocusNode node = FocusNode();
  final FocusNode other = FocusNode();
  String value = '';

  @override
  void dispose() {
    node.dispose();
    other.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Field(
        label: 'Whose card is it?',
        hint: 'The name is how their credits stay apart.',
        required: true,
        error: requiredError(value, error),
        submitted: widget.submitted,
        focusNode: node,
        builder: (context, control) => TextField(
          key: const Key('holder'),
          focusNode: control.focusNode,
          decoration: control.decoration,
          onChanged: (next) => setState(() => value = next),
        ),
      ),
      TextField(key: const Key('other'), focusNode: other),
    ],
  );
}

Future<void> pump(WidgetTester tester, {bool submitted = false}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: nocturneTheme(Brightness.dark),
      home: Scaffold(body: _Harness(submitted: submitted)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // @lat: [[mobile-tests#Field#The error waits for blur]]
  testWidgets('shows no error until the field has been left', (tester) async {
    await pump(tester);
    expect(find.text(error), findsNothing);

    await tester.tap(find.byKey(const Key('holder')));
    await tester.enterText(find.byKey(const Key('holder')), 'K');
    await tester.enterText(find.byKey(const Key('holder')), '');
    await tester.pumpAndSettle();
    expect(find.text(error), findsNothing);

    await tester.tap(find.byKey(const Key('other')));
    await tester.pumpAndSettle();
    expect(find.text(error), findsOneWidget);

    await tester.enterText(find.byKey(const Key('holder')), 'Kathy');
    await tester.pumpAndSettle();
    expect(find.text(error), findsNothing);
  });

  // @lat: [[mobile-tests#Field#Submitting forces the error into view]]
  testWidgets('a submitted form shows the error at once', (tester) async {
    await pump(tester, submitted: true);
    expect(find.text(error), findsOneWidget);
  });

  // @lat: [[mobile-tests#Field#The label, the mark, the hint and the error reach the screen reader]]
  testWidgets('labels the control and announces the error', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, submitted: true);

    final field = tester.getSemantics(find.byKey(const Key('holder')));
    expect(field.label, contains('Whose card is it?'));
    expect(find.text('Fields marked * are required.'), findsNothing);
    expect(find.textContaining('*'), findsWidgets);
    expect(
      find.text('The name is how their credits stay apart.'),
      findsOneWidget,
    );
    final announced = tester.getSemantics(find.text(error));
    expect(announced.label, error);
    expect(announced.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
    handle.dispose();
  });
}
