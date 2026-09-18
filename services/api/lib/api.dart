/// The HelpMe Reward service tier: the routes, built on shelf over the
/// shared domain package. Written against the product spec in
/// `lat.md/product/` and documented in `lat.md/api/`.
library;

import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'devices.dart';
import 'src/responses.dart';

/// The version the health route reports, bumped with `pubspec.yaml`.
const String apiVersion = '0.1.0';

/// The api as a shelf handler: the router behind a JSON error for anything
/// that throws. [db] is the session the storage-backed routes use, a
/// `Connection` in tests and a `Pool` in the server; without one they
/// answer 503 while `/healthz` still serves.
Handler buildHandler({Session? db}) {
  final router = Router()..get('/healthz', _health);
  addDeviceRoutes(router, db);
  return const Pipeline().addMiddleware(_jsonErrors()).addHandler(router.call);
}

/// Liveness for Cloud Run and the smoke tests: always 200 while the process
/// serves, with the version so a deploy can be told apart from the last one.
Response _health(Request request) {
  return jsonResponse({'status': 'ok', 'version': apiVersion});
}

Middleware _jsonErrors() =>
    (inner) => (request) async {
      try {
        return await inner(request);
      } on Object {
        return jsonResponse({'error': 'internal'}, status: 500);
      }
    };
