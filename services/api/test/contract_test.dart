import 'dart:convert';
import 'dart:io';

import 'package:api/api.dart';
import 'package:api/auth.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'support/database.dart';
import 'support/openapi.dart';
import 'support/tokens.dart';

/// Signs the contract's tokens; made in `main`'s `setUpAll`.
late TestKey key;
late TokenVerifier verifier;

/// The contract test: `openapi.yaml` and the router agree on which routes
/// exist, and every documented status of every operation is driven through
/// the handler and its body checked against the documented schema.

/// One request the contract drives, the status it must produce, and what
/// to keep from its body for later cases.
typedef Case = ({
  Operation op,
  int status,
  Request Function() request,
  bool needsDatabase,
  void Function(Map<String, dynamic> body)? capture,
});

/// Ids and codes earlier cases captured, for later cases' URLs.
final saved = <String, String>{};

/// [url] and [body] may be functions, read when the case runs, so a case can
/// use what an earlier one [capture]d. [as] signs the request in as that
/// Firebase uid.
Case call(
  String method,
  String path,
  int status, {
  Object? url,
  Object? body,
  String? as,
  bool needsDatabase = true,
  void Function(Map<String, dynamic> body)? capture,
}) => (
  op: (method: method, path: path),
  status: status,
  needsDatabase: needsDatabase,
  capture: capture,
  request: () {
    final u = url is String Function() ? url() : (url as String? ?? path);
    final b = body is Object? Function() ? body() : body;
    return Request(
      method,
      Uri.parse('http://localhost$u'),
      body: b == null ? null : (b is String ? b : jsonEncode(b)),
      headers: {
        if (b != null) 'content-type': 'application/json',
        if (as != null) 'authorization': 'Bearer ${key.sign(uid: as)}',
      },
    );
  },
);

void Function(Map<String, dynamic>) keep(String name, String field) =>
    (body) => saved[name] = body[field] as String;

const device = {
  'token': 'contract-token',
  'installationId': 'inst-1',
  'platform': 'android',
  'timezone': 'America/New_York',
};

/// Every hand-written case, in the order they run: a later case may rely on
/// an earlier one's writes. The 401 and 503 of every signed-in operation are
/// generated ([signedInCases]).
final cases = <Case>[
  call('GET', '/health', 200, needsDatabase: false),
  call('GET', '/v1/me', 200, as: 'owner', capture: keep('owner', 'id')),
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
  call('GET', '/v1/catalog', 200, as: 'owner'),
  call(
    'GET',
    '/v1/catalog/{templateId}',
    200,
    as: 'owner',
    url: '/v1/catalog/amex-gold',
  ),
  call(
    'GET',
    '/v1/catalog/{templateId}',
    404,
    as: 'owner',
    url: '/v1/catalog/nope',
  ),
  call('GET', '/v1/household', 200, as: 'owner'),
  call(
    'POST',
    '/v1/household/invites',
    201,
    as: 'owner',
    body: {'role': 'read'},
    capture: keep('readCode', 'code'),
  ),
  call(
    'POST',
    '/v1/household/invites',
    400,
    as: 'owner',
    body: {'role': 'admin'},
  ),
  call(
    'POST',
    '/v1/invites/{code}/accept',
    400,
    as: 'reader',
    url: () => '/v1/invites/${saved['readCode']}/accept',
    body: {'confirmLeave': 'yes'},
  ),
  call(
    'POST',
    '/v1/invites/{code}/accept',
    200,
    as: 'reader',
    url: () => '/v1/invites/${saved['readCode']}/accept',
  ),
  call('GET', '/v1/me', 200, as: 'reader', capture: keep('reader', 'id')),
  call(
    'POST',
    '/v1/invites/{code}/accept',
    410,
    as: 'third',
    url: () => '/v1/invites/${saved['readCode']}/accept',
  ),
  call(
    'POST',
    '/v1/invites/{code}/accept',
    404,
    as: 'third',
    url: '/v1/invites/NOSUCH/accept',
  ),
  call(
    'POST',
    '/v1/household/invites',
    403,
    as: 'reader',
    body: {'role': 'read'},
  ),
  call(
    'DELETE',
    '/v1/household/members/{userId}',
    403,
    as: 'reader',
    url: () => '/v1/household/members/${saved['owner']}',
  ),
  call(
    'POST',
    '/v1/household/invites',
    201,
    as: 'third',
    body: {'role': 'edit'},
    capture: keep('thirdCode', 'code'),
  ),
  call(
    'POST',
    '/v1/invites/{code}/accept',
    409,
    as: 'owner',
    url: () => '/v1/invites/${saved['thirdCode']}/accept',
  ),
  call(
    'DELETE',
    '/v1/household/members/{userId}',
    409,
    as: 'owner',
    url: () => '/v1/household/members/${saved['owner']}',
  ),
  call(
    'DELETE',
    '/v1/household/members/{userId}',
    204,
    as: 'owner',
    url: () => '/v1/household/members/${saved['reader']}',
  ),
  call(
    'DELETE',
    '/v1/household/members/{userId}',
    404,
    as: 'owner',
    url: () => '/v1/household/members/${saved['reader']}',
  ),
];

/// For every operation that documents them, the 401 of a request with no
/// token and the 503 of a signed-in request to a process without a
/// database; neither reaches the route, so any path parameter will do.
List<Case> signedInCases(Map<String, dynamic> spec) => [
  for (final op in documentedOperations(spec))
    for (final status in documentedStatuses(spec, op))
      if (status == 401 || (status == 503 && requiresSignIn(spec, op)))
        call(
          op.method,
          op.path,
          status,
          url: op.path.replaceAll(RegExp(r'\{\w+\}'), 'x'),
          body: op.method == 'POST' || op.method == 'PUT' ? const {} : null,
          as: status == 503 ? 'owner' : null,
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
  final body = jsonDecode(text);
  final errors = [for (final e in validate(spec, schema, body)) '$label: $e'];
  if (errors.isEmpty && body is Map<String, dynamic>) c.capture?.call(body);
  return errors;
}

void main() {
  final spec = loadSpec();

  setUpAll(() async {
    key = await TestKey.generate();
    verifier = FirebaseTokenVerifier(
      projectId: testProject,
      certificates: GoogleCertificates(
        fetch: () async =>
            (certs: {'key-1': key.certPem}, maxAge: const Duration(hours: 1)),
      ),
    );
  });

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
      final driven = {
        for (final c in [...cases, ...signedInCases(spec)])
          '${describe(c.op)} ${c.status}',
      };
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
    final handler = buildHandler(verifier: verifier);
    final errors = <String>[];
    for (final c in [
      ...cases.where((c) => !c.needsDatabase),
      ...signedInCases(spec),
    ]) {
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
        final handler = buildHandler(db: db, verifier: verifier);
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
