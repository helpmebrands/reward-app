import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reward/theme/theme.dart';
import 'package:reward/widgets/brand_lockup.dart';

/// The brand artwork in the app bar: the lockup when it fits the width it is
/// given, the wordmark when it does not, the file matching the theme.

const lockup = 'assets/logo/helpmereward-logo-horz-sanstag.png';
const lockupDark = 'assets/logo/helpmereward-logo-horz-sanstag-dark.png';
const wordmark = 'assets/logo/helpmereward-logotype-horz.png';
const wordmarkDark = 'assets/logo/helpmereward-logotype-horz-dark.png';

/// The width the app bar gives the logo in a window this wide.
double barWidth(double window) => window - 84;

Future<void> pumpLockup(
  WidgetTester tester, {
  required double width,
  required Brightness brightness,
  double textScale = 1.0,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: nocturneTheme(brightness),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: width, child: const BrandLockup()),
          ),
        ),
      ),
    ),
  );
}

String drawnAsset(WidgetTester tester) {
  final image = tester.widget<Image>(find.byType(Image));
  return (image.image as AssetImage).assetName;
}

Size drawnSize(WidgetTester tester) => tester.getSize(find.byType(Image));

void main() {
  // @lat: [[mobile-tests#Brand lockup#The lockup fits down to a 308 window]]
  testWidgets('the lockup is 224 x 32 at 402, 320 and 308', (tester) async {
    for (final b in Brightness.values) {
      for (final window in [402.0, 320.0, 308.0]) {
        await pumpLockup(tester, width: barWidth(window), brightness: b);
        expect(
          drawnAsset(tester),
          b == Brightness.dark ? lockupDark : lockup,
          reason: '$window, $b',
        );
        expect(drawnSize(tester), const Size(224, 32));
      }
    }
  });

  // @lat: [[mobile-tests#Brand lockup#Below that the wordmark]]
  testWidgets('at a 300 window the wordmark is 154 x 22', (tester) async {
    for (final b in Brightness.values) {
      await pumpLockup(tester, width: barWidth(300), brightness: b);
      expect(
        drawnAsset(tester),
        b == Brightness.dark ? wordmarkDark : wordmark,
      );
      expect(drawnSize(tester), const Size(154, 22));
    }
  });

  // @lat: [[mobile-tests#Brand lockup#A narrower bar scales the wordmark down]]
  testWidgets('at a 220 window the wordmark scales down', (tester) async {
    for (final b in Brightness.values) {
      await pumpLockup(tester, width: barWidth(220), brightness: b);
      expect(
        drawnAsset(tester),
        b == Brightness.dark ? wordmarkDark : wordmark,
      );
      final size = drawnSize(tester);
      expect(size.width, lessThan(154));
      expect(size.width, lessThanOrEqualTo(barWidth(220)));
      expect(size.width / size.height, closeTo(7, 0.01));
      expect(tester.takeException(), isNull);
    }
  });

  // @lat: [[mobile-tests#Brand lockup#The text scale leaves the size alone]]
  testWidgets('text scale 2.0 leaves the lockup at 224 x 32', (tester) async {
    for (final b in Brightness.values) {
      await pumpLockup(
        tester,
        width: barWidth(402),
        brightness: b,
        textScale: 2.0,
      );
      expect(drawnSize(tester), const Size(224, 32));
    }
  });

  // @lat: [[mobile-tests#Brand lockup#An image, not a heading]]
  testWidgets('one image node labelled HelpMe reward, no header', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    for (final b in Brightness.values) {
      await pumpLockup(tester, width: barWidth(402), brightness: b);
      final nodes = find.bySemanticsLabel('HelpMe reward');
      expect(nodes, findsOneWidget);
      final data = tester.getSemantics(nodes).getSemanticsData();
      expect(data.flagsCollection.isImage, isTrue);
      expect(data.flagsCollection.isHeader, isFalse);
    }
    handle.dispose();
  });
}
