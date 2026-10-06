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

/// What the caller may do with a card, as the api names it: everything as
/// its owner; claims and a credit's state with [record]; read it, and keep
/// their own preferences on it, with [view].
enum CardAccess {
  owner,
  record,
  view;

  /// Whether this access logs usage: claims, enrollment, spend and opting
  /// out.
  bool get records => this != view;
}

/// Someone whose cards are shared with the caller.
class Person {
  const Person({required this.id, this.name, this.email});

  factory Person.fromJson(Map<String, dynamic> json) => Person(
    id: json['id']! as String,
    name: json['name'] as String?,
    email: json['email'] as String?,
  );

  final String id;

  /// The name on their sign-in, when it carries one.
  final String? name;
  final String? email;

  /// What the app calls them: their name, or their email without one.
  String get displayName => name ?? email ?? 'Someone';

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'email': email};
}

/// `GET /v1/household/data`: the cards the caller can see as the domain's
/// snapshot, what they may do with each, and the owners of the ones shared
/// with them.
class HouseholdSnapshot {
  const HouseholdSnapshot({
    required this.data,
    this.access = const {},
    this.people = const {},
  });

  final AppData data;

  /// By card id.
  final Map<String, CardAccess> access;

  /// By user id.
  final Map<String, Person> people;
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
  Future<HouseholdSnapshot> householdData();

  /// Every template as it stands today, without `blank`.
  Future<List<CardTemplate>> catalog();

  /// Replaces a linked card with one its owner maintains; the new id.
  Future<String> convertCard(String cardId);
  Future<void> acceptInvite(String code, {bool confirmLeave = false});
  Future<MemberPreferences> preferences();
  Future<void> putPreferences(MemberPreferences preferences);
  Future<void> setMute({
    String? cardId,
    String? benefitId,
    required bool muted,
  });

  /// Sets one credit's notification level for this member only.
  Future<void> setNotificationLevel(String benefitId, NotificationLevel level);

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

  /// Sends a test notification to each of the member's devices after
  /// [delaySeconds] (at most 10); how many took it.
  Future<int> sendTestReminder({int delaySeconds = 0});
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
  Future<HouseholdSnapshot> householdData() async {
    final json =
        (await _send('GET', '/v1/household/data'))! as Map<String, dynamic>;
    return HouseholdSnapshot(
      data: appDataFromJson(json),
      access: {
        for (final MapEntry(:key, :value)
            in ((json['access'] as Map?) ?? const {}).entries)
          key as String: CardAccess.values.byName(value as String),
      },
      people: {
        for (final p in ((json['people'] as List?) ?? const []))
          (p as Map<String, dynamic>)['id']! as String: Person.fromJson(p),
      },
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
  Future<void> acceptInvite(String code, {bool confirmLeave = false}) => _send(
    'POST',
    '/v1/invites/${Uri.encodeComponent(code)}/accept',
    body: {'confirmLeave': confirmLeave},
  );

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
  Future<int> sendTestReminder({int delaySeconds = 0}) async =>
      ((await _send(
                'POST',
                '/v1/me/reminders/test',
                body: {'delaySeconds': delaySeconds},
              ))!
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
  Future<void> setNotificationLevel(
    String benefitId,
    NotificationLevel level,
  ) => _send(
    'PUT',
    '/v1/me/benefits/$benefitId/level',
    body: {'level': level.name},
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
