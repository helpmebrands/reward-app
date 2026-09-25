import 'package:flutter/widgets.dart';

import 'snackbar_state.dart';

/// Transient UI state: which sheet is open. The counterpart of the PWA's `UiProvider`.
///
/// Held above the router rather than in a screen, because the shell renders
/// the sheets while the screens open them. Sheets track a benefit *id*, never
/// a resolved instance: the instance is recomputed on every claim, and holding
/// one would leave the sheet showing a balance that went stale the moment the
/// user logged something.
class UiState extends ChangeNotifier {
  /// The one snackbar, owned here so the shell draws it and any screen or
  /// sheet can show one. Its own notifier, so a message does not rebuild
  /// whatever listens for the sheets.
  final SnackbarState snackbar = SnackbarState();

  String? _openBenefitId;
  String? _openOverlapLabel;

  /// Each mounted screen's heading focus node by its location, so the app
  /// can move focus to the new screen on navigation. Not a notification:
  /// nothing renders from it.
  final Map<String, FocusNode> headings = {};

  /// Set by the bar or the rail before it switches branch: focus then stays
  /// on the destination the user pressed, as in the PWA.
  bool keepFocusOnDestination = false;

  /// The location whose heading takes focus once it is built, set by the
  /// app on navigation and consumed by that screen's title.
  String? pendingHeadingFocus;

  /// The credit whose sheet is open, or null.
  String? get openBenefitId => _openBenefitId;

  /// The overlap group whose compare sheet is open, or null.
  String? get openOverlapLabel => _openOverlapLabel;

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

  @override
  void dispose() {
    snackbar.dispose();
    super.dispose();
  }
}
