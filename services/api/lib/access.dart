/// Who may do what with a card: its owner everything, and each person a
/// share covers what the share gives (the `card_access` view, migration
/// `0015`). Documented in `lat.md/api/api-architecture.md#Owners and shares`.
library;

import 'package:postgres/postgres.dart';

/// What a person may do with a card.
enum Access {
  /// Everything: the card itself, its credits' terms, deleting, converting
  /// and sharing it.
  owner,

  /// Claims and a credit's state, besides reading.
  record,

  /// Reading, and the person's own preferences on it.
  view;

  /// Whether this access logs usage: claims and a credit's state.
  bool get records => this != view;
}

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

/// [userId]'s access to the card [cardId], or null when they cannot see it.
/// Every route on a card, a credit or a claim authorises through this.
Future<Access?> accessTo(Session db, String userId, String cardId) async {
  if (!_uuid.hasMatch(cardId)) return null;
  final rows = await db.execute(
    Sql.named(
      'SELECT access FROM card_access '
      'WHERE card_id = @c::uuid AND user_id = @u::uuid',
    ),
    parameters: {'c': cardId, 'u': userId},
  );
  return rows.isEmpty ? null : Access.values.byName(rows.single[0]! as String);
}

/// The users [userIds] as `{id, name, email}`, ordered by what the app
/// shows: the name, or the email without one.
Future<List<Map<String, Object?>>> people(
  Session db,
  Iterable<String> userIds,
) async {
  if (userIds.isEmpty) return const [];
  final rows = await db.execute(
    Sql.named('''
      SELECT id::text, name, email FROM users
      WHERE id = ANY(@ids::uuid[])
      ORDER BY lower(coalesce(name, email, '')), id
    '''),
    parameters: {'ids': TypedValue(Type.uuidArray, userIds.toSet().toList())},
  );
  return [
    for (final [id, name, email] in rows)
      {'id': id, 'name': name, 'email': email},
  ];
}
