import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reward/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // @lat: [[mobile-tests#End to end#A fresh install launches to the first-run screen]]
  testWidgets('launches to the first-run screen on a fresh install', (
    tester,
  ) async {
    app.main();
    await tester.pumpAndSettle();
    expect(find.text('Start with one card'), findsOneWidget);
  });
}
