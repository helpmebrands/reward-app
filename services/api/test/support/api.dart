/// The api under test with a verifier that trusts a throwaway key, and
/// requests made as named users: `as('jim').post('/v1/…', body)`.
library;

import 'dart:convert';

import 'package:api/api.dart';
import 'package:api/auth.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';

import 'tokens.dart';

/// A verifier that accepts tokens signed by [key] for [testProject].
TokenVerifier verifierFor(TestKey key) => FirebaseTokenVerifier(
  projectId: testProject,
  certificates: GoogleCertificates(
    fetch: () async =>
        (certs: {'key-1': key.certPem}, maxAge: const Duration(hours: 1)),
  ),
);

/// A status and a decoded JSON body (null when there is none).
typedef Reply = ({int status, Object? body});

class TestApi {
  TestApi(this.key, Session? db)
    : handler = buildHandler(db: db, verifier: verifierFor(key));

  final TestKey key;
  final Handler handler;

  /// Requests signed in as the Firebase user [uid].
  Caller as(String uid) => Caller._(this, uid);

  Future<Reply> send(
    String method,
    String path, {
    String? uid,
    Object? body,
  }) async {
    final response = await handler(
      Request(
        method,
        Uri.parse('http://localhost$path'),
        body: body == null ? null : jsonEncode(body),
        headers: {
          if (body != null) 'content-type': 'application/json',
          if (uid != null)
            'authorization':
                'Bearer ${key.sign(uid: uid, email: '$uid@x.test')}',
        },
      ),
    );
    final text = await response.readAsString();
    return (
      status: response.statusCode,
      body: text.isEmpty ? null : jsonDecode(text),
    );
  }
}

class Caller {
  Caller._(this._api, this.uid);

  final TestApi _api;
  final String uid;

  Future<Reply> get(String path) => _api.send('GET', path, uid: uid);
  Future<Reply> post(String path, [Object? body]) =>
      _api.send('POST', path, uid: uid, body: body ?? const {});
  Future<Reply> put(String path, Object body) =>
      _api.send('PUT', path, uid: uid, body: body);
  Future<Reply> delete(String path) => _api.send('DELETE', path, uid: uid);

  /// The caller's user id, from `GET /v1/me`.
  Future<String> id() async =>
      ((await get('/v1/me')).body! as Map<String, dynamic>)['id'] as String;
}
