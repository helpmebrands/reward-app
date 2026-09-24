import 'dart:convert';
import 'dart:io';

import 'package:api/api.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'support/database.dart';
import 'support/openapi.dart';

/// The contract test: `openapi.yaml` and the router agree on which routes
/// exist, and every documented status of every operation is driven through
/// the handler and its body checked against the documented schema.

/// One request the contract drives, and the status it must produce.
typedef Case = ({
  Operation op,
  int status,
  Request Function() request,
  bool needsDatabase,
});

Case call(
  String method,
  String path,
  int status, {
  String? url,
  Object? body,
  bool needsDatabase = true,
}) => (
  op: (method: method, path: path),
  status: status,
  needsDatabase: needsDatabase,
  request: () => Request(
    method,
    Uri.parse('http://localhost${url ?? path}'),
    body: body == null ? null : (body is String ? body : jsonEncode(body)),
    headers: body == null ? null : {'content-type': 'application/json'},
  ),
);

const device = {
  'token': 'contract-token',
  'installationId': 'inst-1',
  'platform': 'android',
  'timezone': 'America/New_York',
};

/// Every case, in the order they run: a later case may rely on an earlier
/// one's writes (the delete after the registration).
final cases = <Case>[
  call('GET', '/health', 200, needsDatabase: false),
  call('POST', '/v1/devices', 200, body: device),
  call('POST', '/v1/devices', 400, body: {...device}..remove('platform')),
  call('POST', '/v1/devices', 400, body: 'not json'),
  call('POST', '/v1/devices', 503, body: device, needsDatabase: false),
  call('DELETE', '/v1/devices/{token}', 204, url: '/v1/devices/contract-token'),
  call('DELETE', '/v1/devices/{token}', 404, url: '/v1/devices/nobody'),
  call(
    'DELETE',
    '/v1/devices/{token}',
    503,
    url: '/v1/devices/nobody',
    needsDatabase: false,
  ),
];

/// Statuses no request can produce on purpose, documented for honesty.
const undriven = {500};

Future<List<String>> check(
  Map<String, dynamic> spec,
  Case c,
  Response response,
) async {
  final label = '${describe(c.op)} → ${c.status}';
  if (response.statusCode != c.status) {
    return ['$label: answered ${response.statusCode}'];
  }
  final documented = responseFor(spec, c.op, c.status);
  if (documented == null) return ['$label: status not documented'];
  final text = await response.readAsString();
  final content = documented['content'] as Map<String, dynamic>?;
  if (content == null) {
    return text.isEmpty ? const [] : ['$label: body where none is documented'];
  }
  if (!(response.headers['content-type'] ?? '').startsWith(
    'application/json',
  )) {
    return ['$label: not JSON'];
  }
  final schema =
      (content['application/json'] as Map)['schema'] as Map<String, dynamic>;
  return [
    for (final e in validate(spec, schema, jsonDecode(text))) '$label: $e',
  ];
}

void main() {
  final spec = loadSpec();

  group('the spec and the router', () {
    // @lat: [[api-tests#Contract#The spec is OpenAPI 3.1]]
    test('is an OpenAPI 3.1 document with info and paths', () {
      expect(spec['openapi'], startsWith('3.1'));
      expect((spec['info'] as Map)['title'], isNotEmpty);
      expect(documentedOperations(spec), isNotEmpty);
    });

    // @lat: [[api-tests#Contract#Every route is documented and every operation served]]
    test('document exactly the routes the router serves', () {
      final routes = buildApi().routes;
      expect(undocumentedRoutes(spec, routes), isEmpty);
      expect(unservedOperations(spec, routes), isEmpty);
    });

    // @lat: [[api-tests#Contract#An undocumented route fails the contract]]
    test('an undocumented route is reported', () {
      final routes = [
        ...buildApi().routes,
        const ApiRoute('GET', '/v1/secret/<id>'),
      ];
      expect(undocumentedRoutes(spec, routes), ['GET /v1/secret/{id}']);
    });

    // @lat: [[api-tests#Contract#Every documented status is driven]]
    test('every documented status of every operation has a case', () {
      final driven = {for (final c in cases) '${describe(c.op)} ${c.status}'};
      final missing = [
        for (final op in documentedOperations(spec))
          for (final status in documentedStatuses(spec, op))
            if (!undriven.contains(status) &&
                !driven.contains('${describe(op)} $status'))
              '${describe(op)} $status',
      ];
      expect(missing, isEmpty);
    });

    // @lat: [[api-tests#Contract#The schema check catches a wrong body]]
    test('the schema check reports a body that breaks the schema', () {
      final schema = {r'$ref': '#/components/schemas/Device'};
      expect(validate(spec, schema, device), isEmpty);
      expect(
        validate(spec, schema, {...device, 'platform': 'web'}),
        isNotEmpty,
      );
      expect(validate(spec, schema, {...device}..remove('token')), isNotEmpty);
    });
  });

  // @lat: [[api-tests#Contract#Responses match the documented schemas]]
  test('the cases without a database answer as documented', () async {
    final handler = buildHandler();
    final errors = <String>[];
    for (final c in cases.where((c) => !c.needsDatabase)) {
      errors.addAll(await check(spec, c, await handler(c.request())));
    }
    expect(errors, isEmpty);
  });

  final url = Platform.environment['DATABASE_URL'];
  group(
    'responses against DATABASE_URL',
    () {
      late Connection db;

      setUpAll(() async => db = await openMigratedSchema(url!, 'contract'));

      tearDownAll(() => dropSchema(db, 'contract'));

      test('every case with a database answers as documented', () async {
        final handler = buildHandler(db: db);
        final errors = <String>[];
        for (final c in cases.where((c) => c.needsDatabase)) {
          errors.addAll(await check(spec, c, await handler(c.request())));
        }
        expect(errors, isEmpty);
      });
    },
    skip: url == null ? 'DATABASE_URL is not set' : false,
  );
}
