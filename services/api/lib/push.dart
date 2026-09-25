/// Sending a push to one device through FCM HTTP v1, which also reaches
/// APNs. Documented in `lat.md/api/api-architecture.md#Reminder sender`.
library;

import 'dart:convert';
import 'dart:io';

/// What a push says, and how the device groups it: a newer push with the
/// same [tag] replaces the older one on the lock screen.
class PushMessage {
  const PushMessage({
    required this.title,
    required this.body,
    required this.tag,
    this.data = const {},
  });

  final String title;
  final String body;
  final String tag;

  /// Handed to the app with the notification, e.g. the route a tap opens.
  final Map<String, String> data;
}

enum PushResult {
  sent,

  /// FCM no longer knows the token: the app was uninstalled or the token
  /// was replaced. Its device row should go.
  unregistered,

  /// Anything else; the device is kept and the push may be retried.
  failed,
}

/// Sends one push to one device token. The real one is [FcmSender]; tests
/// record instead.
abstract interface class PushSender {
  Future<PushResult> send(String token, PushMessage message);
}

/// The FCM HTTP v1 request for [token].
Map<String, Object?> fcmRequestBody(String token, PushMessage message) => {
  'message': {
    'token': token,
    'notification': {'title': message.title, 'body': message.body},
    'data': message.data,
    'android': {
      'notification': {'tag': message.tag},
    },
    'apns': {
      'headers': {'apns-collapse-id': message.tag},
    },
  },
};

/// What FCM's answer means for the device: only an `UNREGISTERED` error
/// code retires a token, so a malformed request never deletes devices.
PushResult fcmResult(int status, String body) {
  if (status >= 200 && status < 300) return PushResult.sent;
  try {
    final details =
        ((jsonDecode(body) as Map)['error'] as Map)['details'] as List? ?? [];
    if (details.any((d) => d is Map && d['errorCode'] == 'UNREGISTERED')) {
      return PushResult.unregistered;
    }
  } on Object {
    // Not FCM's JSON error: a plain failure.
  }
  return PushResult.failed;
}

/// FCM HTTP v1 for [projectId], authorised as the runtime's own service
/// account through the metadata server, so no key file exists anywhere.
class FcmSender implements PushSender {
  FcmSender(this.projectId, {HttpClient? client})
    : _client = client ?? HttpClient();

  final String projectId;
  final HttpClient _client;
  String? _token;
  DateTime _expires = DateTime.fromMillisecondsSinceEpoch(0);

  Future<String> _accessToken() async {
    if (_token != null && DateTime.now().isBefore(_expires)) return _token!;
    final request = await _client.getUrl(
      Uri.parse(
        'http://metadata.google.internal/computeMetadata/v1/instance/'
        'service-accounts/default/token',
      ),
    );
    request.headers.set('Metadata-Flavor', 'Google');
    final response = await request.close();
    final json =
        jsonDecode(await response.transform(utf8.decoder).join())
            as Map<String, dynamic>;
    _token = json['access_token'] as String;
    // A minute's margin, so a token never expires mid-request.
    _expires = DateTime.now().add(
      Duration(seconds: (json['expires_in'] as int) - 60),
    );
    return _token!;
  }

  @override
  Future<PushResult> send(String token, PushMessage message) async {
    final request = await _client.postUrl(
      Uri.parse(
        'https://fcm.googleapis.com/v1/projects/$projectId/messages:send',
      ),
    );
    request.headers
      ..set('authorization', 'Bearer ${await _accessToken()}')
      ..contentType = ContentType.json;
    request.write(jsonEncode(fcmRequestBody(token, message)));
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    final result = fcmResult(response.statusCode, body);
    if (result == PushResult.failed) {
      stderr.writeln('fcm ${response.statusCode}: $body');
    }
    return result;
  }
}
