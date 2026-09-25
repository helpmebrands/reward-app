import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/household_api.dart';
import '../data/push_messaging.dart';
import 'ids.dart';

/// Push on this device: the server decides and sends reminders, so the app
/// only asks permission, registers its token with the api, keeps that
/// registration current, and reads the server's summary for Settings.
class PushController extends ChangeNotifier {
  PushController({
    required this.messaging,
    required HouseholdApi api,
    required Future<String> Function() installationId,
  })
    // ignore: prefer_initializing_formals
    : _api = api,
       // ignore: prefer_initializing_formals
       _installationId = installationId;

  final PushMessaging messaging;
  final HouseholdApi _api;
  final Future<String> Function() _installationId;
  StreamSubscription<String>? _refreshes;

  /// The token the api holds for this installation, null when none.
  String? _registered;

  /// The server's summary, once read.
  ReminderSummary? summary;

  /// The PWA's words for a refusal.
  static const refused = 'Reminders stay off until notifications are allowed.';

  /// Re-registers whenever FCM replaces the token, while registered.
  void start() {
    _refreshes ??= messaging.tokenRefresh.listen((token) {
      if (_registered != null) _register(token).ignore();
    });
  }

  /// Asks permission and registers; null when done, or the sentence to show
  /// when the person refused.
  Future<String?> enable() async {
    if (await messaging.requestPermission() != PushPermission.granted) {
      return refused;
    }
    await register();
    return null;
  }

  /// Registers this installation's current token, as on launch once
  /// reminders are on, so the token and the zone stay current.
  Future<void> register() async {
    final token = await messaging.token();
    if (token != null) await _register(token);
  }

  Future<void> _register(String token) async {
    await _api.registerDevice(
      PushDevice(
        token: token,
        installationId: await _installationId(),
        platform: messaging.platform,
        timezone: await messaging.timezone(),
      ),
    );
    final old = _registered;
    _registered = token;
    if (old != null && old != token) {
      await _api.unregisterDevice(old).catchError((_) {});
    }
  }

  /// Removes the registration: the switch turned off, or signing out, which
  /// must happen while the ID token still works.
  Future<void> unregister() async {
    final token = _registered ?? await messaging.token();
    _registered = null;
    summary = null;
    notifyListeners();
    if (token == null) return;
    try {
      await _api.unregisterDevice(token);
    } on ApiError {
      // Not registered: nothing to remove.
    } on ApiOffline {
      // The server retires the token when FCM reports it dead.
    }
  }

  /// Reads the server's summary; left as it was when the api cannot say.
  Future<void> refreshSummary() async {
    try {
      summary = await _api.reminderSummary();
      notifyListeners();
    } on ApiOffline {
      // Shown again on the next visit.
    } on ApiError {
      // Likewise.
    }
  }

  /// How long the server waits before sending the test, so the tester can
  /// put the app in the background: a push that arrives while the app is
  /// open shows no banner.
  static const testDelaySeconds = 5;

  /// What to show while the test waits.
  static const testPending =
      'Sending in $testDelaySeconds seconds. '
      'Put the app in the background to see it.';

  /// Asks the server for a test notification in [testDelaySeconds]; the
  /// sentence to show when it has gone.
  Future<String> sendTest() async {
    try {
      final sent = await _api.sendTestReminder(delaySeconds: testDelaySeconds);
      return sent == 0
          ? 'No device took the test. Check that notifications are allowed.'
          : 'Test notification sent.';
    } on ApiOffline {
      return 'Offline. Try the test again when you are connected.';
    } on ApiError {
      return 'The test could not be sent.';
    }
  }

  @override
  void dispose() {
    _refreshes?.cancel();
    super.dispose();
  }
}

/// This installation's id, made once and kept in shared preferences.
Future<String> sharedPreferencesInstallationId() async {
  const key = 'installation-id';
  final prefs = await SharedPreferences.getInstance();
  final existing = prefs.getString(key);
  if (existing != null) return existing;
  final id = newId();
  await prefs.setString(key, id);
  return id;
}
