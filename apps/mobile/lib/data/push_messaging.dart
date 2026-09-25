import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What the person answered when asked to allow notifications.
enum PushPermission { granted, denied }

/// A push that arrived while the app was open, which the system does not
/// show; the app shows it in the snackbar instead.
@immutable
class PushNotice {
  const PushNotice({required this.title, required this.body});

  final String title;
  final String body;
}

/// The method channel both platforms answer with the device's IANA zone
/// (`Europe/London`), which Dart cannot read: `DateTime.timeZoneName` is
/// an abbreviation such as `BST`.
const timezoneChannel = 'com.helpmebrands.reward/timezone';

/// The device's side of push, behind an interface so tests need no
/// Firebase: permission, the FCM token, the zone, and what the person does
/// with a notification.
abstract interface class PushMessaging {
  /// `ios` or `android`, as the api names them.
  String get platform;

  /// Asks the system; it prompts the first time and answers from memory
  /// after that.
  Future<PushPermission> requestPermission();

  /// This installation's FCM token, or null when there is none yet.
  Future<String?> token();

  Future<String> timezone();

  /// A new token, when FCM replaces the old one.
  Stream<String> get tokenRefresh;

  /// The data of the notification whose tap launched the app, if one did.
  Future<Map<String, Object?>?> initialTap();

  /// The data of each notification tapped while the app was in the
  /// background.
  Stream<Map<String, Object?>> get taps;

  /// Pushes that arrive while the app is in the foreground.
  Stream<PushNotice> get foreground;
}

/// [PushMessaging] on `firebase_messaging`, which reaches APNs on iOS.
class FirebasePushMessaging implements PushMessaging {
  FirebasePushMessaging({FirebaseMessaging? messaging})
    : _messaging = messaging ?? FirebaseMessaging.instance;

  final FirebaseMessaging _messaging;
  static const _zone = MethodChannel(timezoneChannel);

  @override
  String get platform =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  @override
  Future<PushPermission> requestPermission() async {
    final settings = await _messaging.requestPermission();
    return switch (settings.authorizationStatus) {
      AuthorizationStatus.authorized ||
      AuthorizationStatus.provisional => PushPermission.granted,
      _ => PushPermission.denied,
    };
  }

  @override
  Future<String?> token() async {
    try {
      // On iOS the FCM token needs the APNs token, which arrives a moment
      // after permission is granted.
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        for (
          var i = 0;
          i < 10 && await _messaging.getAPNSToken() == null;
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }
      return await _messaging.getToken();
    } on FirebaseException {
      return null;
    }
  }

  @override
  Future<String> timezone() async =>
      await _zone.invokeMethod<String>('current') ?? 'UTC';

  @override
  Stream<String> get tokenRefresh => _messaging.onTokenRefresh;

  @override
  Future<Map<String, Object?>?> initialTap() async =>
      (await _messaging.getInitialMessage())?.data;

  @override
  Stream<Map<String, Object?>> get taps =>
      FirebaseMessaging.onMessageOpenedApp.map((m) => m.data);

  @override
  Stream<PushNotice> get foreground => FirebaseMessaging.onMessage
      .where((m) => m.notification != null)
      .map(
        (m) => PushNotice(
          title: m.notification!.title ?? '',
          body: m.notification!.body ?? '',
        ),
      );
}
