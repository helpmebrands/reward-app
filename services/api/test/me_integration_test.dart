import 'dart:convert';
import 'dart:io';

import 'package:api/api.dart';
import 'package:api/auth.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'support/database.dart';
import 'support/tokens.dart';

/// Sign-in through the handler: a verified caller becomes a user row on the
/// first call, and `GET /v1/me` names them. Against `DATABASE_URL`, in the
/// suite's own schema; skipped without one.
void main() {
  final url = Platform.environment['DATABASE_URL'];

  late TestKey key;
  late TestKey forger;
  late TokenVerifier verifier;

  setUpAll(() async {
    key = await TestKey.generate();
    forger = await TestKey.generate();
    verifier = FirebaseTokenVerifier(
      projectId: testProject,
      certificates: GoogleCertificates(
        fetch: () async =>
            (certs: {'key-1': key.certPem}, maxAge: const Duration(hours: 1)),
      ),
    );
  });

  Request me([String? token]) => Request(
    'GET',
    Uri.parse('http://localhost/v1/me'),
    headers: {'authorization': ?(token == null ? null : 'Bearer $token')},
  );

  Future<Map<String, dynamic>> json(Response r) async =>
      jsonDecode(await r.readAsString()) as Map<String, dynamic>;

  // @lat: [[api-tests#Sign-in#Without a token the caller gets 401]]
  test('GET /v1/me without a usable token answers 401', () async {
    final handler = buildHandler(verifier: verifier);
    for (final request in [
      me(),
      me('garbage'),
      Request(
        'GET',
        Uri.parse('http://localhost/v1/me'),
        headers: {'authorization': 'Basic abc'},
      ),
    ]) {
      final response = await handler(request);
      expect(response.statusCode, 401);
      expect(await json(response), {'error': 'unauthenticated'});
    }
  });

  group(
    'users against DATABASE_URL',
    () {
      late Connection db;
      late Handler handler;

      setUpAll(() async {
        db = await openMigratedSchema(url!, 'sign_in');
        handler = buildHandler(db: db, verifier: verifier);
      });

      tearDownAll(() => dropSchema(db, 'sign_in'));

      setUp(() => db.execute('TRUNCATE users CASCADE'));

      Future<int> users() async =>
          (await db.execute('SELECT count(*) FROM users')).single[0] as int;

      // @lat: [[api-tests#Sign-in#The first call creates the user and later calls reuse it]]
      test('a new uid gets one user row, reused on the next call', () async {
        final first = await handler(me(key.sign(uid: 'u-new')));
        expect(first.statusCode, 200);
        final body = await json(first);
        expect(body['email'], 'jim@example.com');
        expect(body['id'], isA<String>());
        expect(await users(), 1);

        final second = await json(await handler(me(key.sign(uid: 'u-new'))));
        expect(second['id'], body['id']);
        expect(await users(), 1);

        await handler(me(key.sign(uid: 'u-other', email: null)));
        expect(await users(), 2);
      });

      // @lat: [[api-tests#Sign-in#Bad tokens create nobody]]
      test('expired, misaddressed and forged tokens get 401', () async {
        for (final token in [
          key.sign(expiresIn: const Duration(hours: -1)),
          key.sign(claims: {'aud': 'someone-else'}),
          forger.sign(),
        ]) {
          expect((await handler(me(token))).statusCode, 401);
        }
        expect(await users(), 0);
      });
    },
    skip: url == null ? 'DATABASE_URL is not set' : false,
  );
}
