import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';

import '../auth.dart';
import 'responses.dart';

/// A route that needs a verified caller and the database. Path parameters
/// are read from `request.params`.
typedef SignedInHandler =
    Future<Response> Function(Request request, Caller caller, Session db);

/// Wraps protected routes: no verifier configured is 503 `no auth`, a
/// missing or unverifiable bearer token is 401 `unauthenticated`, no
/// database is 503 `no database`; otherwise the caller's user row is found
/// or created and [handler] runs as them.
class SignedIn {
  const SignedIn(this.verifier, this.db);

  final TokenVerifier? verifier;
  final Session? db;

  Handler call(SignedInHandler handler) => (request) async {
    final verifier = this.verifier;
    if (verifier == null) return serviceUnavailable('no auth');
    final header = request.headers['authorization'] ?? '';
    if (!header.startsWith('Bearer ')) return unauthenticated();
    final VerifiedToken token;
    try {
      token = await verifier.verify(header.substring(7).trim());
    } on InvalidToken {
      return unauthenticated();
    }
    final db = this.db;
    if (db == null) return serviceUnavailable('no database');
    return handler(request, await callerFor(db, token), db);
  };
}

Response unauthenticated() =>
    jsonResponse({'error': 'unauthenticated'}, status: 401);

Response serviceUnavailable(String reason) =>
    jsonResponse({'error': reason}, status: 503);
