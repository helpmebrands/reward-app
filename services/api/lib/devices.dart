/// Push-device registration: the body a device sends, its row in `devices`,
/// and the two routes. Documented in `lat.md/api/api-architecture.md#Devices`.
library;

import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'src/responses.dart';

/// A registration body that fails validation, naming the field at fault.
class InvalidField implements Exception {
  const InvalidField(this.field);

  final String field;

  @override
  String toString() => 'invalid field: $field';
}

const platforms = {'ios', 'android'};

/// The shape of an IANA zone name (`Europe/London`, `Etc/GMT+1`, `UTC`).
/// Whether the name exists is Postgres's call ([isKnownTimezone]).
final _zoneShape = RegExp(r'^[A-Za-z0-9_+\-]+(/[A-Za-z0-9_+\-]+)*$');

/// One installation's push identity: the FCM token it registers under, the
/// id the app generated for itself, its platform and its zone.
class Device {
  const Device({
    required this.token,
    required this.installationId,
    required this.platform,
    required this.timezone,
  });

  /// Parses a request body, throwing [InvalidField] for the first field that
  /// is missing, blank or malformed. A body that is not an object is `body`.
  factory Device.parse(Object? json) {
    if (json is! Map<String, dynamic>) throw const InvalidField('body');
    String field(String name) {
      final value = json[name];
      if (value is! String || value.trim().isEmpty) throw InvalidField(name);
      return value.trim();
    }

    final token = field('token');
    final installationId = field('installationId');
    final platform = field('platform');
    if (!platforms.contains(platform)) throw const InvalidField('platform');
    final timezone = field('timezone');
    if (!_zoneShape.hasMatch(timezone)) throw const InvalidField('timezone');
    return Device(
      token: token,
      installationId: installationId,
      platform: platform,
      timezone: timezone,
    );
  }

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

/// Whether Postgres's own tz database knows [name], so the api never ships
/// a zone list of its own.
Future<bool> isKnownTimezone(Session db, String name) async {
  final rows = await db.execute(
    Sql.named('SELECT 1 FROM pg_timezone_names WHERE name = @name'),
    parameters: {'name': name},
  );
  return rows.isNotEmpty;
}

/// Inserts the device or, when the token is already registered, replaces
/// its installation, platform and zone and bumps `updated_at`.
Future<void> upsertDevice(Session db, Device device) => db.execute(
  Sql.named('''
    INSERT INTO devices (token, installation_id, platform, timezone)
    VALUES (@token, @installationId, @platform, @timezone)
    ON CONFLICT (token) DO UPDATE SET
      installation_id = EXCLUDED.installation_id,
      platform        = EXCLUDED.platform,
      timezone        = EXCLUDED.timezone,
      updated_at      = now()
  '''),
  parameters: device.toJson(),
);

/// Removes the token; false when nothing was registered under it.
Future<bool> deleteDevice(Session db, String token) async {
  final result = await db.execute(
    Sql.named('DELETE FROM devices WHERE token = @token'),
    parameters: {'token': token},
  );
  return result.affectedRows > 0;
}

/// Adds `POST /v1/devices` and `DELETE /v1/devices/<token>` to [router].
/// Without a [db] both answer 503, so a health-only process (the container
/// smoke test, a misconfigured deploy) says so instead of pretending.
void addDeviceRoutes(Router router, Session? db) {
  Response invalid(String field) =>
      jsonResponse({'error': 'invalid', 'field': field}, status: 400);

  Future<Response> register(Request request) async {
    if (db == null) return _noDatabase;
    final Device device;
    try {
      device = Device.parse(jsonDecode(await request.readAsString()));
    } on InvalidField catch (e) {
      return invalid(e.field);
    } on FormatException {
      return invalid('body');
    }
    if (!await isKnownTimezone(db, device.timezone)) {
      return invalid('timezone');
    }
    await upsertDevice(db, device);
    return jsonResponse(device.toJson());
  }

  Future<Response> unregister(Request request, String token) async {
    if (db == null) return _noDatabase;
    return await deleteDevice(db, token)
        ? Response(204)
        : jsonResponse({'error': 'not found'}, status: 404);
  }

  router
    ..post('/v1/devices', register)
    ..delete('/v1/devices/<token>', unregister);
}

final _noDatabase = jsonResponse({'error': 'no database'}, status: 503);
