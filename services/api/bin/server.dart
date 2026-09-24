import 'dart:io';

import 'package:api/api.dart';
import 'package:api/auth.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf_io.dart' as io;

/// Serves the api on `PORT` (Cloud Run injects it; 8080 otherwise), bound to
/// every interface so the container answers from outside. `DATABASE_URL`
/// opens a connection pool for the storage-backed routes; without it only
/// `/health` answers, which is what the container smoke test needs.
/// `FIREBASE_PROJECT_ID` names the project whose ID tokens sign people in;
/// without it the signed-in routes answer 503.
Future<void> main() async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final url = Platform.environment['DATABASE_URL'];
  final db = url == null || url.isEmpty ? null : Pool.withUrl(url);
  final firebaseProject = Platform.environment['FIREBASE_PROJECT_ID'] ?? '';
  final verifier = firebaseProject.isEmpty
      ? null
      : FirebaseTokenVerifier(
          projectId: firebaseProject,
          certificates: GoogleCertificates(),
        );
  final server = await io.serve(
    buildHandler(db: db, verifier: verifier),
    InternetAddress.anyIPv4,
    port,
  );
  stdout.writeln(
    'api $apiVersion listening on :${server.port}'
    '${db == null ? ' (no database)' : ''}'
    '${verifier == null ? ' (no sign-in)' : ''}',
  );
}
