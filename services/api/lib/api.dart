/// The HelpMe Reward service tier: the routes, built on shelf over the
/// shared domain package. Written against the product spec in
/// `lat.md/product/` and documented in `lat.md/api/`.
library;

import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';

import 'app_links.dart';
import 'auth.dart';
import 'catalog.dart';
import 'catalog_admin.dart';
import 'devices.dart';
import 'household_data.dart';
import 'households.dart';
import 'preferences.dart';
import 'push.dart';
import 'reminder_sender.dart';
import 'src/responses.dart';
import 'src/routes.dart';
import 'src/signed_in.dart';

export 'src/routes.dart' show ApiRoute;

/// The version the health route reports, bumped with `pubspec.yaml`.
const String apiVersion = '0.1.0';

/// The api: its handler, and the routes it serves, which the contract test
/// holds against `openapi.yaml`.
class Api {
  const Api(this.handler, this.routes);

  final Handler handler;
  final List<ApiRoute> routes;
}

/// The api as a shelf handler: the router behind a JSON error for anything
/// that throws. [db] is the session the storage-backed routes use, a
/// `Connection` in tests and a `Pool` in the server; without one they
/// answer 503 while `/health` still serves. [verifier] checks the bearer
/// token on every signed-in route; without one those answer 503 too.
/// [push] sends the test notification; without one that answers 503.
Api buildApi({
  Session? db,
  TokenVerifier? verifier,
  Uri? inviteLinkBase,
  AppLinks? appLinks,
  PushSender? push,
}) {
  final signedIn = SignedIn(verifier, db);
  final table = RouteTable()
    ..add('GET', '/health', _health)
    ..add('GET', '/v1/me', signedIn(_me));
  addDeviceRoutes(table, signedIn);
  addAppLinkRoutes(table, appLinks ?? AppLinks.fromEnvironment(const {}));
  addCatalogRoutes(table, signedIn);
  addCatalogAdminRoutes(table, signedIn);
  addHouseholdDataRoutes(table, signedIn);
  addPreferenceRoutes(table, signedIn);
  addReminderRoutes(table, signedIn, push);
  addHouseholdRoutes(
    table,
    signedIn,
    inviteLinkBase: inviteLinkBase ?? defaultInviteLinkBase,
  );
  return Api(
    const Pipeline().addMiddleware(_jsonErrors()).addHandler(table.router.call),
    List.unmodifiable(table.routes),
  );
}

/// Where an invite's link points unless the server is told otherwise.
final Uri defaultInviteLinkBase = Uri.parse('https://helpmereward.com/invite/');

/// [buildApi]'s handler.
Handler buildHandler({
  Session? db,
  TokenVerifier? verifier,
  Uri? inviteLinkBase,
  AppLinks? appLinks,
  PushSender? push,
}) => buildApi(
  db: db,
  verifier: verifier,
  inviteLinkBase: inviteLinkBase,
  appLinks: appLinks,
  push: push,
).handler;

/// The signed-in caller, as the api knows them.
Future<Response> _me(Request request, Caller caller, Session db) async =>
    jsonResponse(caller.toJson());

/// Liveness for Cloud Run and the smoke tests: always 200 while the process
/// serves, with the version so a deploy can be told apart from the last one.
/// Not `/healthz`: Google's frontend answers that path itself on `run.app`
/// hosts, so the request would never reach this process.
Response _health(Request request) {
  return jsonResponse({'status': 'ok', 'version': apiVersion});
}

Middleware _jsonErrors() =>
    (inner) => (request) async {
      try {
        return await inner(request);
      } on Object catch (error, stack) {
        // The client gets no detail; the log gets all of it, or a 500 on
        // Cloud Run is undiagnosable.
        stderr.writeln(
          '${request.method} ${request.requestedUri.path}: $error\n$stack',
        );
        return jsonResponse({'error': 'internal'}, status: 500);
      }
    };
