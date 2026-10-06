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
import 'devices.dart' show InvalidField;
import 'src/database.dart';
import 'src/responses.dart';
import 'src/routes.dart';
import 'src/signed_in.dart';

/// How long an invite can be used.
const inviteLifetime = Duration(days: 7);

/// What a share lets the other person do, as the api spells it.
const _shareAccess = {'view', 'record'};

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

/// The cards a body shares: all of them (`allCards: true`, which includes
/// cards added later) or the chosen `cardIds`, deduplicated; null when it
/// names neither. `allCards: false` needs `cardIds`, and `cardIds` must be a
/// non-empty list of strings beside no `allCards: true`.
({bool allCards, List<String> cardIds})? _scope(Map<String, dynamic> body) {
  final allCards = body['allCards'];
  if (allCards != null && allCards is! bool) {
    throw const InvalidField('allCards');
  }
  final cardIds = body['cardIds'];
  if (cardIds == null) {
    if (allCards == true) return (allCards: true, cardIds: const []);
    if (allCards == false) throw const InvalidField('cardIds');
    return null;
  }
  if (allCards == true ||
      cardIds is! List ||
      cardIds.isEmpty ||
      cardIds.any((id) => id is! String)) {
    throw const InvalidField('cardIds');
  }
  return (allCards: false, cardIds: cardIds.cast<String>().toSet().toList());
}

/// The shares [userId] gives, or receives when not [given], each as the
/// other person's `{id, name, email}` with the access and all cards or the
/// chosen card ids; only the one with [otherId] when it is given.
Future<List<Map<String, Object?>>> _shares(
  Session db,
  String userId, {
  required bool given,
  String? otherId,
}) async {
  final (mine, theirs) = given
      ? ('owner_id', 'member_id')
      : ('member_id', 'owner_id');
  final rows = await db.execute(
    Sql.named('''
      SELECT u.id::text, u.name, u.email, s.access, s.all_cards,
             ARRAY(SELECT sc.card_id::text FROM shared_cards sc
                   JOIN cards c ON c.id = sc.card_id AND c.owner_id = s.owner_id
                   WHERE sc.owner_id = s.owner_id
                     AND sc.member_id = s.member_id
                   ORDER BY c.created_at, c.id)
      FROM shares s JOIN users u ON u.id = s.$theirs
      WHERE s.$mine = @u::uuid
        ${otherId == null ? '' : 'AND s.$theirs = @other::uuid'}
      ORDER BY lower(coalesce(u.name, u.email, '')), u.id
    '''),
    parameters: {'u': userId, 'other': ?otherId},
  );
  return [
    for (final [id, name, email, access, allCards, cardIds] in rows)
      {
        'id': id,
        'name': name,
        'email': email,
        'access': access,
        'allCards': allCards,
        if (allCards != true) 'cardIds': cardIds,
      },
  ];
}

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

/// Adds the invite and share routes to [routes]. [inviteLinkBase] is the
/// web address an invite's link starts with; the code is appended.
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
    final ({bool allCards, List<String> cardIds}) scope;
    try {
      scope = _scope(body) ?? (throw const InvalidField('cardIds'));
    } on InvalidField catch (e) {
      return _invalid(e.field);
    }
    final (:allCards, cardIds: chosen) = scope;

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
      await tx.execute(
        Sql.named('''
          INSERT INTO shared_cards (owner_id, member_id, card_id)
          SELECT @o::uuid, @m::uuid, ic.card_id
          FROM invite_cards ic
          JOIN cards c ON c.id = ic.card_id AND c.owner_id = @o::uuid
          WHERE ic.code = @code
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
      final [share] = await _shares(
        tx,
        caller.userId,
        given: false,
        otherId: owner! as String,
      );
      return jsonResponse(share);
    });
  }

  Future<Response> list(Request request, Caller caller, Session db) async =>
      jsonResponse({
        'given': await _shares(db, caller.userId, given: true),
        'received': await _shares(db, caller.userId, given: false),
      });

  /// Changes the access or the cards of the caller's share with the
  /// person; the cards must be the caller's own.
  Future<Response> change(Request request, Caller caller, Session db) async {
    final memberId = request.params['memberId']!;
    final body = await _objectBody(request);
    return inTransaction(db, (tx) async {
      final parties = {'o': caller.userId, 'm': memberId};
      final found =
          _uuid.hasMatch(memberId) &&
          (await tx.execute(
            Sql.named(
              'SELECT 1 FROM shares '
              'WHERE owner_id = @o::uuid AND member_id = @m::uuid FOR UPDATE',
            ),
            parameters: parties,
          )).isNotEmpty;
      if (!found) return _notFound();
      if (body == null) return _invalid('body');
      final access = body['access'];
      if (access != null &&
          (access is! String || !_shareAccess.contains(access))) {
        return _invalid('access');
      }
      final ({bool allCards, List<String> cardIds})? scope;
      try {
        scope = _scope(body);
      } on InvalidField catch (e) {
        return _invalid(e.field);
      }
      for (final cardId in scope?.cardIds ?? const <String>[]) {
        if (await accessTo(tx, caller.userId, cardId) != Access.owner) {
          return _notFound();
        }
      }

      if (access != null) {
        await tx.execute(
          Sql.named(
            'UPDATE shares SET access = @access '
            'WHERE owner_id = @o::uuid AND member_id = @m::uuid',
          ),
          parameters: {...parties, 'access': access},
        );
      }
      if (scope != null) {
        await tx.execute(
          Sql.named(
            'UPDATE shares SET all_cards = @all '
            'WHERE owner_id = @o::uuid AND member_id = @m::uuid',
          ),
          parameters: {...parties, 'all': scope.allCards},
        );
        await tx.execute(
          Sql.named(
            'DELETE FROM shared_cards '
            'WHERE owner_id = @o::uuid AND member_id = @m::uuid',
          ),
          parameters: parties,
        );
        for (final cardId in scope.cardIds) {
          await tx.execute(
            Sql.named(
              'INSERT INTO shared_cards (owner_id, member_id, card_id) '
              'VALUES (@o::uuid, @m::uuid, @card::uuid)',
            ),
            parameters: {...parties, 'card': cardId},
          );
        }
      }
      final [share] = await _shares(
        tx,
        caller.userId,
        given: true,
        otherId: memberId,
      );
      return jsonResponse(share);
    });
  }

  /// Ends the share from [ownerId] to [memberId] at once, deleting nothing
  /// else: the cards, their claims and everyone's mutes stay. 404 when
  /// there is no such share.
  Future<Response> end(Session db, String ownerId, String memberId) async {
    if (!_uuid.hasMatch(ownerId) || !_uuid.hasMatch(memberId)) {
      return _notFound();
    }
    final ended = await db.execute(
      Sql.named(
        'DELETE FROM shares WHERE owner_id = @o::uuid AND member_id = @m::uuid',
      ),
      parameters: {'o': ownerId, 'm': memberId},
    );
    return ended.affectedRows > 0 ? Response(204) : _notFound();
  }

  Future<Response> stopSharing(Request request, Caller caller, Session db) =>
      end(db, caller.userId, request.params['memberId']!);

  Future<Response> stopSeeing(Request request, Caller caller, Session db) =>
      end(db, request.params['ownerId']!, caller.userId);

  routes
    ..add('POST', '/v1/invites', signedIn(createInvite))
    ..add('GET', '/v1/invites/<code>', signedIn(readInvite))
    ..add('POST', '/v1/invites/<code>/accept', signedIn(accept))
    ..add('GET', '/v1/shares', signedIn(list))
    ..add('PATCH', '/v1/shares/<memberId>', signedIn(change))
    ..add('DELETE', '/v1/shares/<memberId>', signedIn(stopSharing))
    ..add('DELETE', '/v1/shares/received/<ownerId>', signedIn(stopSeeing));
}
