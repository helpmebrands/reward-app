import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reward/data/push_messaging.dart';

/// The native half of push: what iOS needs declared to receive a remote
/// notification, and the channel both platforms answer with their IANA zone.
void main() {
  String read(String path) => File(path).readAsStringSync();

  // @lat: [[mobile-tests#Push#iOS declares push]]
  test('iOS has the push entitlement and the remote-notification mode', () {
    final entitlements = read('ios/Runner/Runner.entitlements');
    expect(entitlements, contains('<key>aps-environment</key>'));
    final plist = read('ios/Runner/Info.plist');
    expect(
      plist,
      matches(
        RegExp(
          r'<key>UIBackgroundModes</key>\s*<array>\s*'
          r'<string>remote-notification</string>',
        ),
      ),
    );
  });

  // @lat: [[mobile-tests#Push#Both platforms answer the zone channel]]
  test('both platforms answer the time zone channel', () {
    for (final path in [
      'ios/Runner/AppDelegate.swift',
      'android/app/src/main/kotlin/com/helpmebrands/reward/MainActivity.kt',
    ]) {
      final source = read(path);
      expect(source, contains('"$timezoneChannel"'), reason: path);
      expect(source, contains('"current"'), reason: path);
    }
  });
}
