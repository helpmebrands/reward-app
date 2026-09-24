import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reward/firebase_options.dart';

/// The staging Firebase apps, as the Pulumi stack registered them, are the
/// options a build without defines signs in with.
void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  // @lat: [[mobile-tests#Sign-in#Staging Firebase options are built in]]
  test('iOS and Android carry the staging Firebase apps', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final ios = FirebaseConfig.currentPlatform!;
    expect(ios.appId, '1:133269731559:ios:40cae6fc6e557ad9a38a42');
    expect(ios.apiKey, 'AIzaSyAzJMzkT8NEivP1U-Vwn5I1rNyjyjO2S2o');
    expect(ios.projectId, 'helpme-reward-staging');
    expect(ios.iosBundleId, 'com.helpmebrands.reward');

    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final android = FirebaseConfig.currentPlatform!;
    expect(android.appId, '1:133269731559:android:ecc28dcb9ef24847a38a42');
    expect(android.apiKey, 'AIzaSyDTYAeCUtpiqfIrvR5OCkM3ctomeouGtgI');

    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(FirebaseConfig.currentPlatform, isNull);
  });
}
