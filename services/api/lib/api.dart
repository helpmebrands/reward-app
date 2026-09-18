/// The HelpMe Reward service tier: the routes, built on shelf over the
/// shared domain package. Written against the product spec in
/// `lat.md/product/` and documented in `lat.md/api/`.
library;

import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

/// The version the health route reports, bumped with `pubspec.yaml`.
const String apiVersion = '0.1.0';

/// The api as a shelf handler: the router behind request logging and a
/// JSON error for anything that throws.
Handler buildHandler() {
  final router = Router()..get('/healthz', _health);
  return const Pipeline().addMiddleware(_jsonErrors()).addHandler(router.call);
}

/// Liveness for Cloud Run and the smoke tests: always 200 while the process
/// serves, with the version so a deploy can be told apart from the last one.
Response _health(Request request) {
  return _json({'status': 'ok', 'version': apiVersion});
}

Response _json(Object body, {int status = 200}) => Response(
  status,
  body: jsonEncode(body),
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

Middleware _jsonErrors() =>
    (inner) => (request) async {
      try {
        return await inner(request);
      } on Object {
        return _json({'error': 'internal'}, status: 500);
      }
    };
