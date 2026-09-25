import 'package:api/auth.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:test/test.dart';

import 'support/tokens.dart';

/// The Firebase ID token verifier, against a throwaway key published the way
/// Google publishes Firebase's: certificates by key id.
void main() {
  late TestKey key;
  late TestKey forger;
  late FirebaseTokenVerifier verifier;

  setUpAll(() async {
    key = await TestKey.generate();
    forger = await TestKey.generate();
    verifier = FirebaseTokenVerifier(
      projectId: testProject,
      certificates: GoogleCertificates(
        fetch: () async => (certs: {'key-1': key.certPem}, maxAge: _hour),
      ),
    );
  });

  // @lat: [[api-tests#Sign-in#A Firebase ID token is verified against Google's keys]]
  test('accepts a token Firebase would issue and names its user', () async {
    final token = await verifier.verify(key.sign(uid: 'u-1'));
    expect(token.uid, 'u-1');
    expect(token.email, 'jim@example.com');
  });

  // @lat: [[api-tests#Sign-in#Expired, misaddressed and forged tokens are refused]]
  group('refuses', () {
    Future<void> refused(String token) =>
        expectLater(verifier.verify(token), throwsA(isA<InvalidToken>()));

    test('an expired token', () => refused(key.sign(expiresIn: -_hour)));

    test('a token for another project', () async {
      await refused(key.sign(claims: {'aud': 'someone-else'}));
      await refused(
        key.sign(
          claims: {'iss': 'https://securetoken.google.com/someone-else'},
        ),
      );
    });

    test('a token signed by another key under the same id', () {
      return refused(forger.sign());
    });

    test('a token naming a key Google does not publish', () {
      return refused(key.sign(kid: 'key-2'));
    });

    test('a token without a subject', () {
      return refused(key.sign(uid: ''));
    });

    test('a token issued in the future', () {
      final later = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
      return refused(key.sign(claims: {'iat': later}));
    });

    test('a token not signed with RS256', () {
      final hs = JWT(
        {'sub': 'u-1', 'aud': testProject},
        header: {'kid': 'key-1'},
      ).sign(SecretKey(key.certPem));
      return refused(hs);
    });

    test('something that is not a token', () => refused('not-a-token'));
  });

  // @lat: [[api-tests#Sign-in#Google's certificates are cached for their max-age]]
  test('fetches the certificates once per max-age', () async {
    var fetches = 0;
    var now = DateTime.utc(2026, 9, 24, 12);
    final certificates = GoogleCertificates(
      fetch: () async {
        fetches++;
        return (certs: {'key-1': 'pem'}, maxAge: _hour);
      },
      clock: () => now,
    );
    await certificates.current();
    await certificates.current();
    expect(fetches, 1);
    now = now.add(const Duration(minutes: 61));
    await certificates.current();
    expect(fetches, 2);
  });

  test('reads max-age from Cache-Control', () {
    expect(
      maxAgeOf('public, max-age=19302, must-revalidate, no-transform'),
      const Duration(seconds: 19302),
    );
    expect(maxAgeOf(null), Duration.zero);
  });
}

const _hour = Duration(hours: 1);
