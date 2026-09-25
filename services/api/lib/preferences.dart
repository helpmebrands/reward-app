/// Each member's notification preferences and mutes. Documented in
/// `lat.md/api/api-architecture.md#Member preferences`.
library;

import 'dart:convert';

import 'package:domain/domain.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'auth.dart';
import 'src/responses.dart';
import 'src/routes.dart';
import 'src/signed_in.dart';

final _timeOfDay = RegExp(r'^([01][0-9]|2[0-3]):[0-5][0-9]$');
final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

/// [caller]'s preferences: their row or the defaults, with the mutes that
/// name cards and credits of their current household.
Future<MemberPreferences> preferencesOf(Session db, Caller caller) async {
  final row = await db.execute(
    Sql.named('''
      SELECT enabled, time_of_day, min_value_cents, annual_fee_reminder,
             enrollment_reminder
      FROM member_preferences WHERE user_id = @u::uuid
    '''),
    parameters: {'u': caller.userId},
  );
  final mutes = await db.execute(
    Sql.named('''
      SELECT m.card_id::text, m.benefit_id::text
      FROM member_mutes m
      LEFT JOIN cards c ON c.id = m.card_id
      LEFT JOIN benefits b ON b.id = m.benefit_id
      WHERE m.user_id = @u::uuid
        AND coalesce(c.household_id, b.household_id) = @h::uuid
    '''),
    parameters: {'u': caller.userId, 'h': caller.householdId},
  );
  final base = row.isEmpty
      ? defaultMemberPreferences
      : MemberPreferences(
          enabled: row.single[0]! as bool,
          timeOfDay: row.single[1]! as String,
          minValueCents: row.single[2]! as int,
          annualFeeReminder: row.single[3]! as bool,
          enrollmentReminder: row.single[4]! as bool,
        );
  return base.copyWith(
    mutedCardIds: {
      for (final m in mutes)
        if (m[0] != null) m[0]! as String,
    },
    mutedBenefitIds: {
      for (final m in mutes)
        if (m[1] != null) m[1]! as String,
    },
  );
}

Response _invalid(String field) =>
    jsonResponse({'error': 'invalid', 'field': field}, status: 400);

/// Adds `/v1/me/preferences` and the mute routes. None needs write access:
/// a reader's preferences change nothing shared.
void addPreferenceRoutes(RouteTable routes, SignedIn signedIn) {
  Future<Response> get(Request request, Caller caller, Session db) async =>
      jsonResponse(memberPreferencesToJson(await preferencesOf(db, caller)));

  Future<Response> put(Request request, Caller caller, Session db) async {
    final Object? body;
    try {
      body = jsonDecode(await request.readAsString());
    } on FormatException {
      return _invalid('body');
    }
    if (body is! Map<String, dynamic>) return _invalid('body');
    for (final key in ['enabled', 'annualFeeReminder', 'enrollmentReminder']) {
      if (body[key] is! bool) return _invalid(key);
    }
    final time = body['timeOfDay'];
    if (time is! String || !_timeOfDay.hasMatch(time)) {
      return _invalid('timeOfDay');
    }
    final floor = body['minValueCents'];
    if (floor is! int || floor < 0) return _invalid('minValueCents');
    await db.execute(
      Sql.named('''
        INSERT INTO member_preferences (user_id, enabled, time_of_day,
          min_value_cents, annual_fee_reminder, enrollment_reminder)
        VALUES (@u::uuid, @enabled, @time, @floor, @fee, @enrollment)
        ON CONFLICT (user_id) DO UPDATE SET
          enabled = EXCLUDED.enabled, time_of_day = EXCLUDED.time_of_day,
          min_value_cents = EXCLUDED.min_value_cents,
          annual_fee_reminder = EXCLUDED.annual_fee_reminder,
          enrollment_reminder = EXCLUDED.enrollment_reminder,
          updated_at = now()
      '''),
      parameters: {
        'u': caller.userId,
        'enabled': body['enabled'],
        'time': time,
        'floor': floor,
        'fee': body['annualFeeReminder'],
        'enrollment': body['enrollmentReminder'],
      },
    );
    return get(request, caller, db);
  }

  /// Mutes or unmutes a card (`card_id`) or a credit (`benefit_id`) of the
  /// caller's household; anything else is 404.
  SignedInHandler mute(
    String table,
    String column,
    String param, {
    required bool on,
  }) => (request, caller, db) async {
    final id = request.params[param]!;
    if (!_uuid.hasMatch(id)) {
      return jsonResponse({'error': 'not found'}, status: 404);
    }
    final found = await db.execute(
      Sql.named(
        'SELECT 1 FROM $table WHERE id = @id::uuid AND household_id = @h::uuid',
      ),
      parameters: {'id': id, 'h': caller.householdId},
    );
    if (found.isEmpty) {
      return jsonResponse({'error': 'not found'}, status: 404);
    }
    await db.execute(
      Sql.named(
        on
            ? 'INSERT INTO member_mutes (user_id, $column) '
                  'VALUES (@u::uuid, @id::uuid) ON CONFLICT DO NOTHING'
            : 'DELETE FROM member_mutes '
                  'WHERE user_id = @u::uuid AND $column = @id::uuid',
      ),
      parameters: {'u': caller.userId, 'id': id},
    );
    return Response(204);
  };

  routes
    ..add('GET', '/v1/me/preferences', signedIn(get))
    ..add('PUT', '/v1/me/preferences', signedIn(put))
    ..add(
      'PUT',
      '/v1/me/mutes/cards/<cardId>',
      signedIn(mute('cards', 'card_id', 'cardId', on: true)),
    )
    ..add(
      'DELETE',
      '/v1/me/mutes/cards/<cardId>',
      signedIn(mute('cards', 'card_id', 'cardId', on: false)),
    )
    ..add(
      'PUT',
      '/v1/me/mutes/benefits/<benefitId>',
      signedIn(mute('benefits', 'benefit_id', 'benefitId', on: true)),
    )
    ..add(
      'DELETE',
      '/v1/me/mutes/benefits/<benefitId>',
      signedIn(mute('benefits', 'benefit_id', 'benefitId', on: false)),
    );
}
