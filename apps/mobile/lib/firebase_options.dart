import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// The Firebase app of this build's environment, per platform. Written by
/// hand from the Pulumi stack's outputs rather than by `flutterfire`, so no
/// CLI or generated file sits in the build; a release build for another
/// environment passes its own values as `--dart-define`s. None of these is
/// a secret: they are in every copy of the app.
///
/// Null for a platform with no Firebase app, which then runs signed out
/// with `UnconfiguredAuth`.
abstract final class FirebaseConfig {
  static const _projectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: 'helpme-reward-staging',
  );
  static const _senderId = String.fromEnvironment(
    'FIREBASE_SENDER_ID',
    defaultValue: '133269731559',
  );
  // Staging's, from `pulumi stack output` (firebaseIosAppId, …).
  static const _iosAppId = String.fromEnvironment(
    'FIREBASE_IOS_APP_ID',
    defaultValue: '1:133269731559:ios:40cae6fc6e557ad9a38a42',
  );
  static const _iosApiKey = String.fromEnvironment(
    'FIREBASE_IOS_API_KEY',
    defaultValue: 'AIzaSyAzJMzkT8NEivP1U-Vwn5I1rNyjyjO2S2o',
  );
  static const _androidAppId = String.fromEnvironment(
    'FIREBASE_ANDROID_APP_ID',
    defaultValue: '1:133269731559:android:ecc28dcb9ef24847a38a42',
  );
  static const _androidApiKey = String.fromEnvironment(
    'FIREBASE_ANDROID_API_KEY',
    defaultValue: 'AIzaSyDTYAeCUtpiqfIrvR5OCkM3ctomeouGtgI',
  );

  static FirebaseOptions? get currentPlatform {
    if (kIsWeb) return null;
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS when _iosAppId.isNotEmpty => const FirebaseOptions(
        apiKey: _iosApiKey,
        appId: _iosAppId,
        messagingSenderId: _senderId,
        projectId: _projectId,
        authDomain: '$_projectId.firebaseapp.com',
        iosBundleId: 'com.helpmebrands.reward',
      ),
      TargetPlatform.android when _androidAppId.isNotEmpty =>
        const FirebaseOptions(
          apiKey: _androidApiKey,
          appId: _androidAppId,
          messagingSenderId: _senderId,
          projectId: _projectId,
          authDomain: '$_projectId.firebaseapp.com',
        ),
      _ => null,
    };
  }
}
