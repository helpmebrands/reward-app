import 'package:flutter/foundation.dart';

/// An async action the UI can watch: whether it is running and how it last
/// ended. The Command pattern from Flutter's architecture guide, with no
/// package. A second `execute` while one is running joins it rather than
/// starting another.
class Command0<T> extends ChangeNotifier {
  Command0(this._action);

  final Future<T> Function() _action;
  Future<T>? _running;
  Object? _error;

  bool get running => _running != null;

  /// How the last run failed, or null when it succeeded.
  Object? get error => _error;

  Future<T> execute() {
    final running = _running;
    if (running != null) return running;
    notifyListeners();
    final run = _run();
    _running = run;
    return run;
  }

  Future<T> _run() async {
    try {
      final result = await _action();
      _error = null;
      return result;
    } on Object catch (e) {
      _error = e;
      rethrow;
    } finally {
      _running = null;
      notifyListeners();
    }
  }
}
