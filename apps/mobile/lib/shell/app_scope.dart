import 'package:flutter/widgets.dart';

import '../logic/app_store.dart';

/// The one place a widget looks the [AppStore] up. Sits above the router so
/// every route builder can reach the store without threading it through
/// constructors; there is no global.
class AppScope extends InheritedNotifier<AppStore> {
  const AppScope({super.key, required AppStore store, required super.child})
    : super(notifier: store);

  static AppStore of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
