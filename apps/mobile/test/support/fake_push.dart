import 'dart:async';

import 'package:reward/data/push_messaging.dart';

/// The device's push side without Firebase: a permission answer, a token,
/// and streams a test drives for refreshes, taps and foreground messages.
class FakeMessaging implements PushMessaging {
  FakeMessaging({this.answer = PushPermission.granted});

  /// What the permission prompt answers.
  PushPermission answer;

  /// How many times the app asked.
  int prompts = 0;

  String currentToken = 'fcm-1';
  Map<String, Object?>? launchTap;

  final refreshes = StreamController<String>.broadcast();
  final tapped = StreamController<Map<String, Object?>>.broadcast();
  final shown = StreamController<PushNotice>.broadcast();

  @override
  String get platform => 'ios';

  @override
  Future<PushPermission> requestPermission() async {
    prompts++;
    return answer;
  }

  @override
  Future<String?> token() async => currentToken;

  @override
  Future<String> timezone() async => 'Europe/London';

  @override
  Stream<String> get tokenRefresh => refreshes.stream;

  @override
  Future<Map<String, Object?>?> initialTap() async => launchTap;

  @override
  Stream<Map<String, Object?>> get taps => tapped.stream;

  @override
  Stream<PushNotice> get foreground => shown.stream;
}
