import 'package:flutter_test/flutter_test.dart';
import 'package:reward/logic/ui_state.dart';

void main() {
  // @lat: [[mobile-tests#UI state#Sheets track an id and notify once]]
  test('opening and closing the credit sheet notifies once each', () {
    final ui = UiState();
    var notifications = 0;
    ui.addListener(() => notifications++);

    expect(ui.openBenefitId, isNull);
    ui.openCredit('ben-1');
    expect(ui.openBenefitId, 'ben-1');
    expect(notifications, 1);

    ui.openCredit('ben-2');
    expect(ui.openBenefitId, 'ben-2');
    expect(notifications, 2);

    ui.closeCredit();
    expect(ui.openBenefitId, isNull);
    expect(notifications, 3);

    ui.closeCredit();
    expect(notifications, 3, reason: 'closing a closed sheet is not a change');
  });

  // @lat: [[mobile-tests#UI state#The compare sheet is the other one]]
  test('the compare label is held the same way', () {
    final ui = UiState();
    var notifications = 0;
    ui.addListener(() => notifications++);

    ui.openOverlap('Uber');
    expect(ui.openOverlapLabel, 'Uber');
    ui.openOverlap('Uber');
    ui.closeOverlap();
    expect(ui.openOverlapLabel, isNull);
    ui.closeOverlap();
    expect(notifications, 2);
  });
}
