import 'dart:io';

import 'package:api/api.dart';
import 'package:shelf/shelf_io.dart' as io;

/// Serves the api on `PORT` (Cloud Run injects it; 8080 otherwise), bound to
/// every interface so the container answers from outside.
Future<void> main() async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final server = await io.serve(buildHandler(), InternetAddress.anyIPv4, port);
  stdout.writeln('api $apiVersion listening on :${server.port}');
}
