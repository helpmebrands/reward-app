import 'package:flutter/widgets.dart';

import '../logic/ui_state.dart';

/// The one place a widget looks the [UiState] up. Sits beside [AppScope]
/// above the router, so a screen can open a sheet the shell renders.
class UiScope extends InheritedNotifier<UiState> {
  const UiScope({super.key, required UiState ui, required super.child})
    : super(notifier: ui);

  static UiState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<UiScope>()!.notifier!;
}
