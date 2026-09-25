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

/// One person in the household.
class HouseholdMember {
  const HouseholdMember({
    required this.userId,
    required this.email,
    required this.role,
  });

  final String userId;
  final String? email;
  final MemberRole role;
}

/// The caller's household: who is in it and the caller's own role.
class HouseholdView {
  const HouseholdView({
    required this.id,
    required this.role,
    required this.members,
  });

  final String id;
  final MemberRole role;
  final List<HouseholdMember> members;
}

/// An invite just made: the code to read out and the link to share.
class Invite {
  const Invite({
    required this.code,
    required this.link,
    required this.role,
    required this.expiresAt,
  });

  final String code;
  final String link;

  /// `read` or `edit`.
  final String role;
  final String expiresAt;
}

/// One installation as the api registers it for push: its FCM token, an
/// id the app made for itself, `ios` or `android`, and its IANA zone.
class PushDevice {
  const PushDevice({
    required this.token,
    required this.installationId,
    required this.platform,
    required this.timezone,
  });

  final String token;
  final String installationId;
  final String platform;
  final String timezone;

  Map<String, Object?> toJson() => {
    'token': token,
    'installationId': installationId,
    'platform': platform,
    'timezone': timezone,
  };
}

/// How many reminders the server has scheduled for this member, and the
/// next one.
class ReminderSummary {
  const ReminderSummary({required this.count, this.next});

  factory ReminderSummary.fromJson(Map<String, dynamic> json) {
    final next = json['next'] as Map<String, dynamic>?;
    return ReminderSummary(
      count: json['count'] as int,
      next: next == null
          ? null
          : (
              fireAt: DateTime.parse(next['fireAt'] as String),
              title: next['title'] as String,
              body: next['body'] as String,
            ),
    );
  }

  final int count;
  final ({DateTime fireAt, String title, String body})? next;
}

/// The service tier as the app uses it; `ApiClient` is the real one, tests
/// stand in their own. Bodies are the domain's JSON spelling.
abstract interface class HouseholdApi {
  Future<AppData> householdData();
  Future<HouseholdView> household();

  /// Every template as it stands today, without `blank`.
  Future<List<CardTemplate>> catalog();

  /// Replaces a linked card with one the household maintains; the new id.
  Future<String> convertCard(String cardId);
  Future<Invite> createInvite(String role);
  Future<void> acceptInvite(String code, {bool confirmLeave = false});
  Future<void> removeMember(String userId);
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

  /// Registers this installation for push, or updates its token and zone.
  Future<void> registerDevice(PushDevice device);
  Future<void> unregisterDevice(String token);
  Future<ReminderSummary> reminderSummary();

  /// Sends a test notification to each of the member's devices; how many
  /// took it.
  Future<int> sendTestReminder();
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
  Future<HouseholdView> household() async {
    final json = (await _send('GET', '/v1/household'))! as Map<String, dynamic>;
    return HouseholdView(
      id: json['id']! as String,
      role: MemberRole.values.byName(json['role']! as String),
      members: [
        for (final m in (json['members']! as List).cast<Map<String, dynamic>>())
          HouseholdMember(
            userId: m['userId']! as String,
            email: m['email'] as String?,
            role: MemberRole.values.byName(m['role']! as String),
          ),
      ],
    );
  }

  @override
  Future<List<CardTemplate>> catalog() async => [
    for (final v in (await _send('GET', '/v1/catalog'))! as List)
      templateVersionFromJson(v as Map<String, dynamic>).template,
  ];

  @override
  Future<String> convertCard(String cardId) async {
    final json =
        (await _send('POST', '/v1/cards/$cardId/convert'))!
            as Map<String, dynamic>;
    return (json['card']! as Map<String, dynamic>)['id']! as String;
  }

  @override
  Future<Invite> createInvite(String role) async {
    final json =
        (await _send('POST', '/v1/household/invites', body: {'role': role}))!
            as Map<String, dynamic>;
    return Invite(
      code: json['code']! as String,
      link: json['link']! as String,
      role: json['role']! as String,
      expiresAt: json['expiresAt']! as String,
    );
  }

  @override
  Future<void> acceptInvite(String code, {bool confirmLeave = false}) => _send(
    'POST',
    '/v1/invites/${Uri.encodeComponent(code)}/accept',
    body: {'confirmLeave': confirmLeave},
  );

  @override
  Future<void> removeMember(String userId) =>
      _send('DELETE', '/v1/household/members/$userId');

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
  Future<void> registerDevice(PushDevice device) =>
      _send('POST', '/v1/devices', body: device.toJson());

  @override
  Future<void> unregisterDevice(String token) =>
      _send('DELETE', '/v1/devices/${Uri.encodeComponent(token)}');

  @override
  Future<ReminderSummary> reminderSummary() async => ReminderSummary.fromJson(
    (await _send('GET', '/v1/me/reminders/summary'))! as Map<String, dynamic>,
  );

  @override
  Future<int> sendTestReminder() async =>
      ((await _send('POST', '/v1/me/reminders/test', body: const {}))!
              as Map<String, dynamic>)['sent']
          as int;

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
