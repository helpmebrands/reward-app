/// Invites, and the shares they create from one person to another.
/// Documented in `lat.md/api/api-architecture.md#Owners and shares`.
library;

import 'dart:convert';
import 'dart:math';

import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'access.dart';
import 'auth.dart';
import 'src/database.dart';
import 'src/responses.dart';
import 'src/routes.dart';
import 'src/signed_in.dart';

/// How long an invite can be used.
const inviteLifetime = Duration(days: 7);

/// What a share lets the other person do, as the api spells it.
const _shareAccess = {'view', 'record'};

/// Codes are read aloud and typed on a phone, so the alphabet leaves out
/// what is easily confused: 0 and O, 1, I and L, and U.
const _codeAlphabet = 'ABCDEFGHJKMNPQRSTVWXYZ23456789';
const _codeLength = 8;
final _random = Random.secure();

String newInviteCode() => String.fromCharCodes([
  for (var i = 0; i < _codeLength; i++)
    _codeAlphabet.codeUnitAt(_random.nextInt(_codeAlphabet.length)),
]);

Response _conflict(String reason) =>
    jsonResponse({'error': reason}, status: 409);

Response _invalid(String field) =>
    jsonResponse({'error': 'invalid', 'field': field}, status: 400);

Response _notFound() => jsonResponse({'error': 'not found'}, status: 404);

Response _gone(String reason) => jsonResponse({'error': reason}, status: 410);

String _instant(Object? value) =>
    (value! as DateTime).toUtc().toIso8601String();

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

/// Adds the invite routes to [routes]. [inviteLinkBase] is the web address
/// an invite's link starts with; the code is appended.
void addShareRoutes(
  RouteTable routes,
  SignedIn signedIn, {
  required Uri inviteLinkBase,
}) {
  Future<Response> createInvite(
    Request request,
    Caller caller,
    Session db,
  ) async {
    final body = await _objectBody(request);
    if (body == null) return _invalid('body');
    final access = body['access'];
    if (access is! String || !_shareAccess.contains(access)) {
      return _invalid('access');
    }
    final allCards = body['allCards'] ?? false;
    if (allCards is! bool) return _invalid('allCards');
    final cardIds = body['cardIds'];
    final List<String> chosen;
    if (allCards) {
      if (cardIds != null) return _invalid('cardIds');
      chosen = const [];
    } else {
      if (cardIds is! List ||
          cardIds.isEmpty ||
          cardIds.any((id) => id is! String)) {
        return _invalid('cardIds');
      }
      chosen = cardIds.cast<String>().toSet().toList();
    }

    return inTransaction(db, (tx) async {
      for (final cardId in chosen) {
        if (await accessTo(tx, caller.userId, cardId) != Access.owner) {
          return _notFound();
        }
      }
      for (var attempt = 0; ; attempt++) {
        final code = newInviteCode();
        final rows = await tx.execute(
          Sql.named('''
            INSERT INTO invites (code, owner_id, access, all_cards, expires_at)
            VALUES (@code, @owner::uuid, @access, @all,
                    now() + make_interval(days => @days))
            ON CONFLICT (code) DO NOTHING
            RETURNING expires_at
          '''),
          parameters: {
            'code': code,
            'owner': caller.userId,
            'access': access,
            'all': allCards,
            'days': inviteLifetime.inDays,
          },
        );
        if (rows.isEmpty && attempt < 5) continue;
        for (final cardId in chosen) {
          await tx.execute(
            Sql.named(
              'INSERT INTO invite_cards (code, card_id) '
              'VALUES (@code, @card::uuid)',
            ),
            parameters: {'code': code, 'card': cardId},
          );
        }
        return jsonResponse({
          'code': code,
          'link': inviteLinkBase.resolve(code).toString(),
          'access': access,
          'allCards': allCards,
          if (!allCards) 'cardIds': chosen,
          'expiresAt': _instant(rows.single[0]),
        }, status: 201);
      }
    });
  }

  Future<Response> readInvite(
    Request request,
    Caller caller,
    Session db,
  ) async {
    final found = await db.execute(
      Sql.named('''
        SELECT i.owner_id::text, u.name, u.email, i.access, i.all_cards,
               i.used_at IS NOT NULL, i.expires_at <= now(), i.expires_at,
               (SELECT count(*) FROM invite_cards ic WHERE ic.code = i.code)
        FROM invites i JOIN users u ON u.id = i.owner_id
        WHERE i.code = @code
      '''),
      parameters: {'code': request.params['code']!},
    );
    if (found.isEmpty) return _notFound();
    final [
      owner,
      name,
      email,
      access,
      allCards,
      used,
      expired,
      expiresAt,
      count,
    ] = found.single;
    if (used! as bool) return _gone('invite used');
    if (expired! as bool) return _gone('invite expired');
    return jsonResponse({
      'owner': {'id': owner, 'name': name, 'email': email},
      'access': access,
      'allCards': allCards,
      if (allCards != true) 'cardCount': count,
      'expiresAt': _instant(expiresAt),
    });
  }

  Future<Response> accept(Request request, Caller caller, Session db) async {
    final code = request.params['code']!;
    return inTransaction(db, (tx) async {
      final found = await tx.execute(
        Sql.named('''
          SELECT owner_id::text, access, all_cards, used_at IS NOT NULL,
                 expires_at <= now()
          FROM invites WHERE code = @code FOR UPDATE
        '''),
        parameters: {'code': code},
      );
      if (found.isEmpty) return _notFound();
      final [owner, access, allCards, used, expired] = found.single;
      if (used! as bool) return _gone('invite used');
      if (expired! as bool) return _gone('invite expired');
      if (owner == caller.userId) return _conflict('own invite');
      final existing = await tx.execute(
        Sql.named(
          'SELECT 1 FROM shares '
          'WHERE owner_id = @o::uuid AND member_id = @m::uuid',
        ),
        parameters: {'o': owner, 'm': caller.userId},
      );
      if (existing.isNotEmpty) return _conflict('already shared');

      final parties = {'o': owner, 'm': caller.userId};
      await tx.execute(
        Sql.named('''
          INSERT INTO shares (owner_id, member_id, access, all_cards)
          VALUES (@o::uuid, @m::uuid, @access, @all)
        '''),
        parameters: {...parties, 'access': access, 'all': allCards},
      );
      // A chosen card that has since changed hands is not the owner's to
      // share any more.
      final cards = await tx.execute(
        Sql.named('''
          INSERT INTO shared_cards (owner_id, member_id, card_id)
          SELECT @o::uuid, @m::uuid, ic.card_id
          FROM invite_cards ic
          JOIN cards c ON c.id = ic.card_id AND c.owner_id = @o::uuid
          WHERE ic.code = @code
          RETURNING card_id::text
        '''),
        parameters: {...parties, 'code': code},
      );
      await tx.execute(
        Sql.named(
          'UPDATE invites SET used_by = @m::uuid, used_at = now() '
          'WHERE code = @code',
        ),
        parameters: {'m': caller.userId, 'code': code},
      );
      final [person] = await people(tx, [owner! as String]);
      return jsonResponse({
        ...person,
        'access': access,
        'allCards': allCards,
        if (allCards != true) 'cardIds': [for (final [id] in cards) id],
      });
    });
  }

  routes
    ..add('POST', '/v1/invites', signedIn(createInvite))
    ..add('GET', '/v1/invites/<code>', signedIn(readInvite))
    ..add('POST', '/v1/invites/<code>/accept', signedIn(accept));
}
