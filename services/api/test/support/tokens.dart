/// Firebase-shaped ID tokens for tests, signed with a throwaway RSA key made
/// by `openssl` at run time, so no private key is ever committed.
library;

import 'dart:io';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

const testProject = 'reward-test';

/// One key pair: the private key to sign with and its certificate, which is
/// what Google publishes for Firebase's signing keys.
class TestKey {
  TestKey._(this.privatePem, this.certPem);

  final String privatePem;
  final String certPem;

  static Future<TestKey> generate() async {
    final dir = await Directory.systemTemp.createTemp('jwt-key-');
    try {
      final result = await Process.run('openssl', [
        'req',
        '-x509',
        '-newkey',
        'rsa:2048',
        '-nodes',
        '-keyout',
        '${dir.path}/key.pem',
        '-out',
        '${dir.path}/cert.pem',
        '-days',
        '1',
        '-subj',
        '/CN=reward-api test',
      ]);
      if (result.exitCode != 0) throw StateError('openssl: ${result.stderr}');
      return TestKey._(
        File('${dir.path}/key.pem').readAsStringSync(),
        File('${dir.path}/cert.pem').readAsStringSync(),
      );
    } finally {
      await dir.delete(recursive: true);
    }
  }

  /// A token as Firebase would issue it for [uid], with any claim or header
  /// overridden to make it wrong.
  String sign({
    String uid = 'firebase-uid-1',
    String? email = 'jim@example.com',
    String kid = 'key-1',
    Map<String, Object?> claims = const {},
    Duration expiresIn = const Duration(hours: 1),
  }) {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final payload = <String, Object?>{
      'iss': 'https://securetoken.google.com/$testProject',
      'aud': testProject,
      'auth_time': now - 60,
      'sub': uid,
      'user_id': uid,
      'iat': now - 60,
      'exp': now + expiresIn.inSeconds,
      'email': ?email,
      ...claims,
    };
    return JWT(payload, header: {'kid': kid}).sign(
      RSAPrivateKey(privatePem),
      algorithm: JWTAlgorithm.RS256,
      noIssueAt: true,
    );
  }
}
