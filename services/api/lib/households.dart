/// Households, memberships and invites. Documented in
/// `lat.md/api/api-architecture.md#Households`.
library;

import 'dart:convert';
import 'dart:math';

import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'auth.dart';
import 'src/database.dart';
import 'src/responses.dart';
import 'src/routes.dart';
import 'src/signed_in.dart';

/// How long an invite can be used.
const inviteLifetime = Duration(days: 7);

/// The role an invite grants, as the api spells it, and as a membership.
const _inviteRoles = {'read': Role.reader, 'edit': Role.editor};

/// Codes are read aloud and typed on a phone, so the alphabet leaves out
/// what is easily confused: 0 and O, 1, I and L, and U.
const _codeAlphabet = 'ABCDEFGHJKMNPQRSTVWXYZ23456789';
const _codeLength = 8;
final _random = Random.secure();

String newInviteCode() => String.fromCharCodes([
  for (var i = 0; i < _codeLength; i++)
    _codeAlphabet.codeUnitAt(_random.nextInt(_codeAlphabet.length)),
]);

Response forbidden() => jsonResponse({'error': 'forbidden'}, status: 403);

Response conflict(String reason) =>
    jsonResponse({'error': reason}, status: 409);

Response _invalid(String field) =>
    jsonResponse({'error': 'invalid', 'field': field}, status: 400);

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

/// Reads a JSON object body; an empty body is an empty object. Null when
/// the body is not an object.
Future<Map<String, dynamic>?> _objectBody(Request request) async {
  final text = await request.readAsString();
  if (text.trim().isEmpty) return const {};
  try {
    final json = jsonDecode(text);
    return json is Map<String, dynamic> ? json : null;
  } on FormatException {
    return null;
  }
}

/// The household as its members see it: who is in it, and the caller's
/// own role.
Future<Map<String, Object?>> householdView(
  Session db,
  String householdId,
  Role role,
) async {
  final rows = await db.execute(
    Sql.named('''
      SELECT m.user_id::text, u.email, m.role, m.joined_at
      FROM memberships m JOIN users u ON u.id = m.user_id
      WHERE m.household_id = @h::uuid
      ORDER BY m.joined_at, u.email
    '''),
    parameters: {'h': householdId},
  );
  return {
    'id': householdId,
    'role': role.name,
    'members': [
      for (final r in rows)
        {
          'userId': r[0],
          'email': r[1],
          'role': r[2],
          'joinedAt': (r[3]! as DateTime).toUtc().toIso8601String(),
        },
    ],
  };
}

/// Adds the household routes to [routes]. [inviteLinkBase] is the web
/// address an invite's link starts with; the code is appended.
void addHouseholdRoutes(
  RouteTable routes,
  SignedIn signedIn, {
  required Uri inviteLinkBase,
}) {
  Future<Response> household(
    Request request,
    Caller caller,
    Session db,
  ) async =>
      jsonResponse(await householdView(db, caller.householdId, caller.role));

  Future<Response> createInvite(
    Request request,
    Caller caller,
    Session db,
  ) async {
    if (caller.role != Role.owner) return forbidden();
    final body = await _objectBody(request);
    if (body == null) return _invalid('body');
    final roleName = body['role'];
    final role = _inviteRoles[roleName];
    if (role == null) return _invalid('role');
    for (var attempt = 0; ; attempt++) {
      final code = newInviteCode();
      final rows = await db.execute(
        Sql.named('''
          INSERT INTO invites (code, household_id, role, created_by, expires_at)
          VALUES (@code, @h::uuid, @role, @by::uuid,
                  now() + make_interval(days => @days))
          ON CONFLICT (code) DO NOTHING
          RETURNING expires_at
        '''),
        parameters: {
          'code': code,
          'h': caller.householdId,
          'role': role.name,
          'by': caller.userId,
          'days': inviteLifetime.inDays,
        },
      );
      if (rows.isEmpty && attempt < 5) continue;
      return jsonResponse({
        'code': code,
        'link': inviteLinkBase.resolve(code).toString(),
        'role': roleName,
        'expiresAt': (rows.single[0]! as DateTime).toUtc().toIso8601String(),
      }, status: 201);
    }
  }

  Future<Response> accept(Request request, Caller caller, Session db) async {
    final body = await _objectBody(request);
    if (body == null) return _invalid('body');
    final confirm = body['confirmLeave'] ?? false;
    if (confirm is! bool) return _invalid('confirmLeave');
    final code = request.params['code']!;

    return inTransaction(db, (tx) async {
      final found = await tx.execute(
        Sql.named('''
          SELECT household_id::text, role, used_at IS NOT NULL,
                 expires_at <= now()
          FROM invites WHERE code = @code FOR UPDATE
        '''),
        parameters: {'code': code},
      );
      if (found.isEmpty) {
        return jsonResponse({'error': 'not found'}, status: 404);
      }
      final [target, roleName, used, expired] = found.single;
      if (used! as bool) {
        return jsonResponse({'error': 'invite used'}, status: 410);
      }
      if (expired! as bool) {
        return jsonResponse({'error': 'invite expired'}, status: 410);
      }
      if (target == caller.householdId) return conflict('already a member');

      final current = (await tx.execute(
        Sql.named('''
          SELECT
            (SELECT count(*) FROM memberships
             WHERE household_id = @h::uuid AND user_id <> @u::uuid),
            (SELECT count(*) FROM cards WHERE household_id = @h::uuid)
        '''),
        parameters: {'h': caller.householdId, 'u': caller.userId},
      )).single;
      final others = current[0]! as int;
      final cards = current[1]! as int;
      if (caller.role == Role.owner && others > 0) {
        return conflict('owner has members');
      }
      if (cards > 0 && !confirm) return conflict('household holds cards');

      await tx.execute(
        Sql.named('DELETE FROM memberships WHERE user_id = @u::uuid'),
        parameters: {'u': caller.userId},
      );
      // The last one out takes the household, and so its data, with them.
      if (others == 0) {
        await tx.execute(
          Sql.named('DELETE FROM households WHERE id = @h::uuid'),
          parameters: {'h': caller.householdId},
        );
      }
      await tx.execute(
        Sql.named('''
          INSERT INTO memberships (household_id, user_id, role)
          VALUES (@h::uuid, @u::uuid, @role)
        '''),
        parameters: {'h': target, 'u': caller.userId, 'role': roleName},
      );
      await tx.execute(
        Sql.named(
          'UPDATE invites SET used_by = @u::uuid, used_at = now() '
          'WHERE code = @code',
        ),
        parameters: {'u': caller.userId, 'code': code},
      );
      final role = Role.values.byName(roleName! as String);
      return jsonResponse(await householdView(tx, target! as String, role));
    });
  }

  Future<Response> removeMember(
    Request request,
    Caller caller,
    Session db,
  ) async {
    if (caller.role != Role.owner) return forbidden();
    final userId = request.params['userId']!;
    if (userId == caller.userId) return conflict('owner cannot leave');
    if (!_uuid.hasMatch(userId)) {
      return jsonResponse({'error': 'not found'}, status: 404);
    }
    final removed = await db.execute(
      Sql.named(
        'DELETE FROM memberships '
        'WHERE household_id = @h::uuid AND user_id = @u::uuid',
      ),
      parameters: {'h': caller.householdId, 'u': userId},
    );
    return removed.affectedRows > 0
        ? Response(204)
        : jsonResponse({'error': 'not found'}, status: 404);
  }

  routes
    ..add('GET', '/v1/household', signedIn(household))
    ..add('POST', '/v1/household/invites', signedIn(createInvite))
    ..add('POST', '/v1/invites/<code>/accept', signedIn(accept))
    ..add('DELETE', '/v1/household/members/<userId>', signedIn(removeMember));
}
