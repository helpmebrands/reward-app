import 'package:domain/domain.dart';
import 'package:flutter/foundation.dart';

/// Transient UI state: which sheet is open, and whether the nudge preview is
/// up. The counterpart of the PWA's `UiProvider`.
///
/// Held above the router rather than in a screen, because the shell renders
/// the sheets while the screens open them. Sheets track a benefit *id*, never
/// a resolved instance: the instance is recomputed on every claim, and holding
/// one would leave the sheet showing a balance that went stale the moment the
/// user logged something.
class UiState extends ChangeNotifier {
  String? _openBenefitId;
  String? _openOverlapLabel;
  Reminder? _nudge;

  /// The credit whose sheet is open, or null.
  String? get openBenefitId => _openBenefitId;

  /// The overlap group whose compare sheet is open, or null.
  String? get openOverlapLabel => _openOverlapLabel;

  /// The reminder shown as a nudge preview, or null.
  Reminder? get nudge => _nudge;

  void openCredit(String benefitId) {
    if (_openBenefitId == benefitId) return;
    _openBenefitId = benefitId;
    notifyListeners();
  }

  void closeCredit() {
    if (_openBenefitId == null) return;
    _openBenefitId = null;
    notifyListeners();
  }

  void openOverlap(String label) {
    if (_openOverlapLabel == label) return;
    _openOverlapLabel = label;
    notifyListeners();
  }

  void closeOverlap() {
    if (_openOverlapLabel == null) return;
    _openOverlapLabel = null;
    notifyListeners();
  }

  void showNudge(Reminder reminder) {
    _nudge = reminder;
    notifyListeners();
  }

  void dismissNudge() {
    if (_nudge == null) return;
    _nudge = null;
    notifyListeners();
  }
}
