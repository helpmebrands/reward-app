import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:domain/domain.dart';

/// The api could not be reached: no network, a timeout, or the host is
/// down. Claims wait in the outbox; every other edit waits for the network.
class ApiOffline implements Exception {
  const ApiOffline();

  @override
  String toString() => 'the api could not be reached';
}

/// The api answered, and said no.
class ApiError implements Exception {
  const ApiError(this.status, this.error);

  final int status;

  /// The body's `error`, e.g. `system maintained` or `label taken`.
  final String error;

  @override
  String toString() => 'api $status: $error';
}

/// The caller's role in their household, as the api names it.
enum MemberRole {
  owner,
  editor,
  reader;

  bool get canWrite => this != reader;
}

/// The service tier as the app uses it; `ApiClient` is the real one, tests
/// stand in their own. Bodies are the domain's JSON spelling.
abstract interface class HouseholdApi {
  Future<AppData> householdData();
  Future<MemberRole> memberRole();
  Future<MemberPreferences> preferences();
  Future<void> putPreferences(MemberPreferences preferences);
  Future<void> setMute({
    String? cardId,
    String? benefitId,
    required bool muted,
  });

  /// `{card, benefits}` of the card created.
  Future<Card> addCard(Map<String, Object?> body);
  Future<void> patchCard(String id, Map<String, Object?> body);
  Future<void> deleteCard(String id);
  Future<Benefit> addBenefit(String cardId, Map<String, Object?> terms);
  Future<void> putBenefit(String id, Map<String, Object?> terms);
  Future<void> putBenefitState(String id, Map<String, Object?> state);
  Future<void> deleteBenefit(String id);
  Future<Claim> postClaim(String idempotencyKey, Map<String, Object?> body);
  Future<void> deleteClaim(String id);
}

/// A request and its answer, as the client needs them: a seam so the
/// client is tested without a socket.
typedef ApiResponse = ({int status, Object? body});
typedef ApiTransport =
    Future<ApiResponse> Function(
      String method,
      Uri url,
      Map<String, String> headers,
      Object? body,
    );

/// The api over HTTP, on `dart:io`'s `HttpClient` with no package. Every
/// request carries the signed-in user's Firebase ID token.
class ApiClient implements HouseholdApi {
  ApiClient({
    required this.baseUrl,
    required Future<String?> Function() token,
    ApiTransport? transport,
  }) : _transport = transport ?? httpTransport,
       // ignore: prefer_initializing_formals
       _token = token;

  final String baseUrl;
  final Future<String?> Function() _token;
  final ApiTransport _transport;

  Future<Object?> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String> headers = const {},
  }) async {
    final token = await _token();
    final ApiResponse response;
    try {
      response = await _transport(method, Uri.parse('$baseUrl$path'), {
        ...headers,
        'authorization': ?(token == null ? null : 'Bearer $token'),
        if (body != null) 'content-type': 'application/json',
      }, body);
    } on SocketException {
      throw const ApiOffline();
    } on TimeoutException {
      throw const ApiOffline();
    } on HttpException {
      throw const ApiOffline();
    }
    if (response.status >= 200 && response.status < 300) return response.body;
    final error = response.body;
    throw ApiError(
      response.status,
      error is Map && error['error'] is String
          ? error['error'] as String
          : 'unknown',
    );
  }

  @override
  Future<AppData> householdData() async => appDataFromJson(
    (await _send('GET', '/v1/household/data'))! as Map<String, dynamic>,
  );

  @override
  Future<MemberRole> memberRole() async {
    final household =
        (await _send('GET', '/v1/household'))! as Map<String, dynamic>;
    return MemberRole.values.byName(household['role']! as String);
  }

  @override
  Future<MemberPreferences> preferences() async => memberPreferencesFromJson(
    (await _send('GET', '/v1/me/preferences'))! as Map<String, dynamic>,
  );

  @override
  Future<void> putPreferences(MemberPreferences preferences) => _send(
    'PUT',
    '/v1/me/preferences',
    body: memberPreferencesToJson(preferences)
      ..remove('mutedCardIds')
      ..remove('mutedBenefitIds'),
  );

  @override
  Future<void> setMute({
    String? cardId,
    String? benefitId,
    required bool muted,
  }) => _send(
    muted ? 'PUT' : 'DELETE',
    cardId != null
        ? '/v1/me/mutes/cards/$cardId'
        : '/v1/me/mutes/benefits/$benefitId',
    body: muted ? const <String, Object?>{} : null,
  );

  @override
  Future<Card> addCard(Map<String, Object?> body) async {
    final created =
        (await _send('POST', '/v1/cards', body: body))! as Map<String, dynamic>;
    return cardFromJson(created['card']! as Map<String, dynamic>);
  }

  @override
  Future<void> patchCard(String id, Map<String, Object?> body) =>
      _send('PATCH', '/v1/cards/$id', body: body);

  @override
  Future<void> deleteCard(String id) => _send('DELETE', '/v1/cards/$id');

  @override
  Future<Benefit> addBenefit(String cardId, Map<String, Object?> terms) async =>
      benefitFromJson(
        (await _send('POST', '/v1/cards/$cardId/benefits', body: terms))!
            as Map<String, dynamic>,
      );

  @override
  Future<void> putBenefit(String id, Map<String, Object?> terms) =>
      _send('PUT', '/v1/benefits/$id', body: terms);

  @override
  Future<void> putBenefitState(String id, Map<String, Object?> state) =>
      _send('PUT', '/v1/benefits/$id/state', body: state);

  @override
  Future<void> deleteBenefit(String id) => _send('DELETE', '/v1/benefits/$id');

  @override
  Future<Claim> postClaim(
    String idempotencyKey,
    Map<String, Object?> body,
  ) async => claimFromJson(
    (await _send(
          'POST',
          '/v1/claims',
          body: body,
          headers: {'idempotency-key': idempotencyKey},
        ))!
        as Map<String, dynamic>,
  );

  @override
  Future<void> deleteClaim(String id) => _send('DELETE', '/v1/claims/$id');
}

/// The real transport: one `HttpClient` request with a timeout, the body
/// JSON both ways.
Future<ApiResponse> httpTransport(
  String method,
  Uri url,
  Map<String, String> headers,
  Object? body,
) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client.openUrl(method, url);
    headers.forEach(request.headers.set);
    if (body != null) request.write(jsonEncode(body));
    final response = await request.close().timeout(const Duration(seconds: 20));
    final text = await response.transform(utf8.decoder).join();
    return (
      status: response.statusCode,
      body: text.isEmpty ? null : jsonDecode(text),
    );
  } finally {
    client.close();
  }
}
