import 'dart:convert';

import 'package:api/api.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  // @lat: [[api-tests#Health#GET healthz answers 200 with the version]]
  test(
    'GET /healthz answers 200 with a JSON body carrying the version',
    () async {
      final handler = buildHandler();
      final response = await handler(
        Request('GET', Uri.parse('http://localhost/healthz')),
      );
      expect(response.statusCode, 200);
      expect(response.headers['content-type'], startsWith('application/json'));
      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['status'], 'ok');
      expect(body['version'], apiVersion);
    },
  );

  // @lat: [[api-tests#Health#Unknown routes answer 404]]
  test('an unknown route answers 404', () async {
    final response = await buildHandler()(
      Request('GET', Uri.parse('http://localhost/nope')),
    );
    expect(response.statusCode, 404);
  });
}
