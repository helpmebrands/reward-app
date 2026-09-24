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
  Map<String, String> headers = const {},
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
        ...headers,
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
  ...adminCases,
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
  ...dataCases,
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

const _nobody = '00000000-0000-4000-8000-000000000000';
const _card = '/v1/cards/{cardId}';
const _benefit = '/v1/benefits/{benefitId}';
const _state = '/v1/benefits/{benefitId}/state';
const _claim = '/v1/claims/{claimId}';
const _gold = {'templateId': 'amex-gold', 'anniversaryOn': '2024-05-01'};
const _terms = {
  'name': 'Dining',
  'category': 'dining',
  'valueCents': 1000,
  'cadence': 'monthly',
  'anchor': 'calendar',
};
Map<String, Object?> _claimBody() => {
  'benefitId': saved['linkedBenefit'],
  'cycleKey': '2026-09-01',
  'amountCents': 500,
  'claimedAt': '2026-09-10T12:00:00.000Z',
};

/// The household data routes, as the owner and as the reader who joined.
final dataCases = <Case>[
  call(
    'POST',
    '/v1/cards',
    201,
    as: 'owner',
    body: _gold,
    capture: (body) {
      saved['linkedCard'] = (body['card'] as Map)['id'] as String;
      saved['linkedBenefit'] = (body['benefits'] as List).first['id'] as String;
    },
  ),
  call(
    'POST',
    '/v1/cards',
    201,
    as: 'owner',
    body: {
      'issuer': 'Chase',
      'product': 'Freedom',
      'network': 'visa',
      'annualFeeCents': 0,
      'anniversaryOn': '2023-01-15',
    },
    capture: (body) => saved['ownCard'] = (body['card'] as Map)['id'] as String,
  ),
  call('POST', '/v1/cards', 400, as: 'owner', body: {'anniversaryOn': 'x'}),
  call(
    'POST',
    '/v1/cards',
    409,
    as: 'owner',
    body: {..._gold, 'label': 'American Express Gold'},
  ),
  call('POST', '/v1/cards', 403, as: 'reader', body: _gold),
  call('GET', '/v1/household/data', 200, as: 'reader'),
  call(
    'PATCH',
    _card,
    200,
    as: 'owner',
    url: () => '/v1/cards/${saved['ownCard']}',
    body: {'label': 'Everyday'},
  ),
  call(
    'PATCH',
    _card,
    400,
    as: 'owner',
    url: () => '/v1/cards/${saved['ownCard']}',
    body: {'kind': 'corporate'},
  ),
  call(
    'PATCH',
    _card,
    403,
    as: 'reader',
    url: () => '/v1/cards/${saved['ownCard']}',
    body: {'label': 'x'},
  ),
  call('PATCH', _card, 404, as: 'owner', url: '/v1/cards/$_nobody', body: {}),
  call(
    'PATCH',
    _card,
    409,
    as: 'owner',
    url: () => '/v1/cards/${saved['linkedCard']}',
    body: {'annualFeeCents': 1},
  ),
  call(
    'POST',
    '/v1/cards/{cardId}/benefits',
    201,
    as: 'owner',
    url: () => '/v1/cards/${saved['ownCard']}/benefits',
    body: _terms,
    capture: keep('ownBenefit', 'id'),
  ),
  call(
    'POST',
    '/v1/cards/{cardId}/benefits',
    400,
    as: 'owner',
    url: () => '/v1/cards/${saved['ownCard']}/benefits',
    body: {'name': 'No value'},
  ),
  call(
    'POST',
    '/v1/cards/{cardId}/benefits',
    403,
    as: 'reader',
    url: () => '/v1/cards/${saved['ownCard']}/benefits',
    body: _terms,
  ),
  call(
    'POST',
    '/v1/cards/{cardId}/benefits',
    404,
    as: 'owner',
    url: '/v1/cards/$_nobody/benefits',
    body: _terms,
  ),
  call(
    'POST',
    '/v1/cards/{cardId}/benefits',
    409,
    as: 'owner',
    url: () => '/v1/cards/${saved['linkedCard']}/benefits',
    body: _terms,
  ),
  call(
    'PUT',
    _benefit,
    200,
    as: 'owner',
    url: () => '/v1/benefits/${saved['ownBenefit']}',
    body: {..._terms, 'valueCents': 1500},
  ),
  call(
    'PUT',
    _benefit,
    400,
    as: 'owner',
    url: () => '/v1/benefits/${saved['ownBenefit']}',
    body: {..._terms, 'cadence': 'rolling'},
  ),
  call(
    'PUT',
    _benefit,
    403,
    as: 'reader',
    url: () => '/v1/benefits/${saved['ownBenefit']}',
    body: _terms,
  ),
  call(
    'PUT',
    _benefit,
    404,
    as: 'owner',
    url: '/v1/benefits/$_nobody',
    body: _terms,
  ),
  call(
    'PUT',
    _benefit,
    409,
    as: 'owner',
    url: () => '/v1/benefits/${saved['linkedBenefit']}',
    body: _terms,
  ),
  call(
    'PUT',
    _state,
    200,
    as: 'owner',
    url: () => '/v1/benefits/${saved['linkedBenefit']}/state',
    body: {'enrolledAt': '2026-09-01T00:00:00.000Z'},
  ),
  call(
    'PUT',
    _state,
    400,
    as: 'owner',
    url: () => '/v1/benefits/${saved['linkedBenefit']}/state',
    body: {'active': 'yes'},
  ),
  call(
    'PUT',
    _state,
    403,
    as: 'reader',
    url: () => '/v1/benefits/${saved['linkedBenefit']}/state',
    body: const {},
  ),
  call(
    'PUT',
    _state,
    404,
    as: 'owner',
    url: '/v1/benefits/$_nobody/state',
    body: const {},
  ),
  call(
    'POST',
    '/v1/claims',
    201,
    as: 'owner',
    headers: {'idempotency-key': 'contract-1'},
    body: _claimBody,
    capture: keep('claim', 'id'),
  ),
  call('POST', '/v1/claims', 400, as: 'owner', body: _claimBody),
  call(
    'POST',
    '/v1/claims',
    403,
    as: 'reader',
    headers: {'idempotency-key': 'contract-2'},
    body: _claimBody,
  ),
  call(
    'POST',
    '/v1/claims',
    404,
    as: 'owner',
    headers: {'idempotency-key': 'contract-3'},
    body: () => {..._claimBody(), 'benefitId': _nobody},
  ),
  call(
    'POST',
    '/v1/claims',
    409,
    as: 'owner',
    headers: {'idempotency-key': 'contract-1'},
    body: () => {..._claimBody(), 'amountCents': 700},
  ),
  call(
    'DELETE',
    _claim,
    403,
    as: 'reader',
    url: () => '/v1/claims/${saved['claim']}',
  ),
  call(
    'DELETE',
    _claim,
    204,
    as: 'owner',
    url: () => '/v1/claims/${saved['claim']}',
  ),
  call(
    'DELETE',
    _claim,
    404,
    as: 'owner',
    url: () => '/v1/claims/${saved['claim']}',
  ),
  call(
    'DELETE',
    _benefit,
    409,
    as: 'owner',
    url: () => '/v1/benefits/${saved['linkedBenefit']}',
  ),
  call(
    'DELETE',
    _benefit,
    403,
    as: 'reader',
    url: () => '/v1/benefits/${saved['ownBenefit']}',
  ),
  call(
    'DELETE',
    _benefit,
    204,
    as: 'owner',
    url: () => '/v1/benefits/${saved['ownBenefit']}',
  ),
  call(
    'DELETE',
    _benefit,
    404,
    as: 'owner',
    url: () => '/v1/benefits/${saved['ownBenefit']}',
  ),
  call(
    'DELETE',
    _card,
    403,
    as: 'reader',
    url: () => '/v1/cards/${saved['ownCard']}',
  ),
  call(
    'DELETE',
    _card,
    204,
    as: 'owner',
    url: () => '/v1/cards/${saved['ownCard']}',
  ),
  call(
    'DELETE',
    _card,
    404,
    as: 'owner',
    url: () => '/v1/cards/${saved['ownCard']}',
  ),
];

const _draft = '/v1/admin/catalog/{templateId}/drafts/{version}';
const _publish = '/v1/admin/catalog/{templateId}/drafts/{version}/publish';
const _source = {
  'effectiveFrom': '2020-01-01',
  'sourceUrl': 'https://example.com/terms',
};

/// The catalogue admin routes, as `admin` (made an admin before the cases
/// run) and as `owner`, who is not one.
final adminCases = <Case>[
  call(
    'POST',
    '/v1/admin/catalog',
    201,
    as: 'admin',
    body: {
      'id': 'contract-card',
      'issuer': 'Test Bank',
      'product': 'Card',
      'network': 'visa',
      'kind': 'personal',
      'annualFeeCents': 0,
      'credits': <Object>[],
    },
  ),
  call('POST', '/v1/admin/catalog', 400, as: 'admin', body: {'id': 'x y'}),
  call('POST', '/v1/admin/catalog', 403, as: 'owner', body: {'id': 'x'}),
  call(
    'POST',
    '/v1/admin/catalog',
    409,
    as: 'admin',
    body: {
      'id': 'amex-gold',
      'issuer': 'American Express',
      'product': 'Gold',
      'network': 'amex',
      'kind': 'personal',
      'annualFeeCents': 0,
      'credits': <Object>[],
    },
  ),
  call(
    'POST',
    '/v1/admin/catalog/{templateId}/drafts',
    201,
    as: 'admin',
    url: '/v1/admin/catalog/amex-gold/drafts',
    capture: (body) => saved['draft'] = jsonEncode(body),
  ),
  call(
    'POST',
    '/v1/admin/catalog/{templateId}/drafts',
    403,
    as: 'owner',
    url: '/v1/admin/catalog/amex-gold/drafts',
  ),
  call(
    'POST',
    '/v1/admin/catalog/{templateId}/drafts',
    404,
    as: 'admin',
    url: '/v1/admin/catalog/nope/drafts',
  ),
  call(
    'POST',
    '/v1/admin/catalog/{templateId}/drafts',
    409,
    as: 'admin',
    url: '/v1/admin/catalog/amex-gold/drafts',
  ),
  call(
    'PUT',
    _draft,
    200,
    as: 'admin',
    url: '/v1/admin/catalog/amex-gold/drafts/2',
    body: () => jsonDecode(saved['draft']!),
  ),
  call(
    'PUT',
    _draft,
    400,
    as: 'admin',
    url: '/v1/admin/catalog/amex-gold/drafts/2',
    body: {'annualFeeCents': 'free'},
  ),
  call(
    'PUT',
    _draft,
    403,
    as: 'owner',
    url: '/v1/admin/catalog/amex-gold/drafts/2',
    body: const {},
  ),
  call(
    'PUT',
    _draft,
    404,
    as: 'admin',
    url: '/v1/admin/catalog/amex-gold/drafts/99',
    body: () => jsonDecode(saved['draft']!),
  ),
  call(
    'PUT',
    _draft,
    409,
    as: 'admin',
    url: '/v1/admin/catalog/amex-gold/drafts/1',
    body: () => jsonDecode(saved['draft']!),
  ),
  call(
    'POST',
    _publish,
    400,
    as: 'admin',
    url: '/v1/admin/catalog/amex-gold/drafts/2/publish',
    body: {'effectiveFrom': '2020-01-01'},
  ),
  call(
    'POST',
    _publish,
    403,
    as: 'owner',
    url: '/v1/admin/catalog/amex-gold/drafts/2/publish',
    body: _source,
  ),
  call(
    'POST',
    _publish,
    404,
    as: 'admin',
    url: '/v1/admin/catalog/amex-gold/drafts/99/publish',
    body: _source,
  ),
  call(
    'POST',
    _publish,
    200,
    as: 'admin',
    url: '/v1/admin/catalog/amex-gold/drafts/2/publish',
    body: _source,
  ),
  call(
    'POST',
    _publish,
    409,
    as: 'admin',
    url: '/v1/admin/catalog/amex-gold/drafts/2/publish',
    body: _source,
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

      setUpAll(() async {
        db = await openMigratedSchema(url!, 'contract');
        await db.execute('''
          WITH admin AS (
            INSERT INTO users (firebase_uid) VALUES ('admin') RETURNING id
          )
          INSERT INTO admins (user_id) SELECT id FROM admin
        ''');
      });

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
