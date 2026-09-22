import 'dart:async';

import 'package:flutter/foundation.dart';

/// What a snackbar offers, usually an undo.
class SnackbarAction {
  const SnackbarAction({
    required this.label,
    this.semanticsLabel,
    required this.onAct,
  });

  final String label;

  /// The accessible name when the label alone ("Undo") does not say what it
  /// undoes.
  final String? semanticsLabel;
  final VoidCallback onAct;
}

class SnackbarMessage {
  const SnackbarMessage({required this.id, required this.text, this.action});

  final int id;
  final String text;
  final SnackbarAction? action;
}

/// The one snackbar, with an undo affordance.
///
/// Logging a credit is the app's main destructive-feeling action and far more
/// common than correcting one, so the flow is optimistic: the claim is written
/// at once and the snackbar offers to take it back, rather than asking "are
/// you sure?" every time. An undo stays up for twenty seconds, not Material's
/// six, because WCAG 2.2.1 wants a time limit the user cannot adjust to be
/// generous; the clock stops while the pointer or focus is on the snackbar
/// and restarts in full when they leave.
class SnackbarState extends ChangeNotifier {
  static const Duration withAction = Duration(seconds: 20);
  static const Duration plain = Duration(milliseconds: 3500);

  SnackbarMessage? _current;
  Timer? _timer;
  int _nextId = 0;

  SnackbarMessage? get current => _current;

  /// Shows a message, replacing any that is up, and starts its clock.
  void show(String text, {SnackbarAction? action}) {
    _current = SnackbarMessage(id: _nextId++, text: text, action: action);
    notifyListeners();
    resume();
  }

  void dismiss() {
    _timer?.cancel();
    _timer = null;
    if (_current == null) return;
    _current = null;
    notifyListeners();
  }

  /// Stops the clock while the user is on the snackbar.
  void pause() {
    _timer?.cancel();
    _timer = null;
  }

  /// Restarts the full duration when they leave.
  void resume() {
    _timer?.cancel();
    final message = _current;
    if (message == null) return;
    _timer = Timer(message.action == null ? plain : withAction, dismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
