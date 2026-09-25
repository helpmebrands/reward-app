import 'dart:io';

import 'package:api/api.dart';
import 'package:api/app_links.dart';
import 'package:api/auth.dart';
import 'package:api/push.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf_io.dart' as io;

/// Serves the api on `PORT` (Cloud Run injects it; 8080 otherwise), bound to
/// every interface so the container answers from outside. `DATABASE_URL`
/// opens a connection pool for the storage-backed routes; without it only
/// `/health` answers, which is what the container smoke test needs.
/// `FIREBASE_PROJECT_ID` names the project whose ID tokens sign people in;
/// without it the signed-in routes answer 503, and it is also the project
/// FCM sends the test notification through. `INVITE_LINK_BASE` is where
/// invite links point, `https://helpmereward.com/invite/` by default.
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
    buildHandler(
      db: db,
      verifier: verifier,
      inviteLinkBase: Uri.tryParse(
        Platform.environment['INVITE_LINK_BASE'] ?? '',
      )?.takeIf((u) => u.hasScheme),
      appLinks: AppLinks.fromEnvironment(Platform.environment),
      push: firebaseProject.isEmpty ? null : FcmSender(firebaseProject),
    ),
    InternetAddress.anyIPv4,
    port,
  );
  stdout.writeln(
    'api $apiVersion listening on :${server.port}'
    '${db == null ? ' (no database)' : ''}'
    '${verifier == null ? ' (no sign-in)' : ''}',
  );
}

extension<T extends Object> on T {
  T? takeIf(bool Function(T value) test) => test(this) ? this : null;
}
