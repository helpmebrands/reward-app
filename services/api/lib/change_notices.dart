/// Catalogue change notices: when a new version of a template is published,
/// every member holding a linked card on it gets a "terms changed" mark and,
/// unless they muted the card, a push. Cards the household maintains itself
/// get neither. Documented in `lat.md/api/api-architecture.md#Change notices`.
library;

import 'dart:convert';

import 'package:domain/domain.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'auth.dart';
import 'catalog.dart';
import 'push.dart';
import 'reminder_sender.dart';
import 'src/responses.dart';
import 'src/routes.dart';
import 'src/signed_in.dart';

String _credit(String name) =>
    name.toLowerCase().endsWith('credit') ? name : '$name credit';

/// What changed from [before] to [after], each worded to follow "Your
/// Gold's": `Uber Cash credit changes to $20`, `annual fee changes to
/// $350`, `Uber Cash credit ends`, `new $50 Lounge credit starts`. A change
/// to anything else is `terms change`.
List<String> termChanges(TemplateVersion? before, TemplateVersion after) {
  final changes = <String>[];
  final old = before?.template;
  final next = after.template;
  if (old != null && old.annualFeeCents != next.annualFeeCents) {
    changes.add('annual fee changes to ${formatMoney(next.annualFeeCents)}');
  }
  final oldCredits = {for (final c in old?.benefits ?? const []) c.id: c};
  final nextCredits = {for (final c in next.benefits) c.id: c};
  for (final credit in next.benefits) {
    final was = oldCredits[credit.id];
    if (was == null) {
      changes.add(
        'new ${formatMoney(credit.valueCents)} ${_credit(credit.name)} starts',
      );
    } else if (was.valueCents != credit.valueCents) {
      changes.add(
        '${_credit(credit.name)} changes to ${formatMoney(credit.valueCents)}',
      );
    } else if (jsonEncode(benefitTemplateToJson(was)) !=
        jsonEncode(benefitTemplateToJson(credit))) {
      changes.add('${_credit(credit.name)} terms change');
    }
  }
  for (final credit in old?.benefits ?? const <BenefitTemplate>[]) {
    if (!nextCredits.containsKey(credit.id)) {
      changes.add('${_credit(credit.name)} ends');
    }
  }
  return changes.isEmpty ? const ['terms change'] : changes;
}

/// The push for one card's change: the first change and the date it takes
/// effect, and how many more there are. Tagged per card, so a later notice
/// for the same card replaces this one.
PushMessage changeNotice({
  required String cardName,
  required String cardId,
  required int version,
  required List<String> changes,
  required IsoDate effectiveFrom,
  required IsoDate today,
}) {
  final more = changes.length - 1;
  final tail = more == 0
      ? '.'
      : ', and $more other change${more == 1 ? '' : 's'}.';
  return PushMessage(
    title: '$cardName terms are changing',
    body:
        "Your $cardName's ${changes.first} on "
        '${formatDate(effectiveFrom, today)}$tail',
    tag: 'terms-$cardId',
    data: {'noticeId': 'terms|$cardId|$version', 'url': '/cards/$cardId'},
  );
}

/// [versions]' published version [version] and the one before it.
(TemplateVersion?, TemplateVersion)? _pair(
  List<TemplateVersion> versions,
  int version,
) {
  final sorted = [...versions]..sort((a, b) => a.version - b.version);
  final at = sorted.indexWhere((v) => v.version == version);
  if (at < 0) return null;
  return (at == 0 ? null : sorted[at - 1], sorted[at]);
}

/// Every publish event not yet told: marks each holder of a linked card on
/// that template, and pushes to those with reminders on who have not muted
/// the card, once each ([sendOnce]). Returns the pushes delivered.
Future<int> sendChangeNotices(
  Session db,
  PushSender push, {
  DateTime? now,
}) async {
  final today = (now ?? DateTime.now()).toUtc().toIso8601String().substring(
    0,
    10,
  );
  final events = await db.execute('''
    SELECT id, template_id, version FROM catalog_events
    WHERE kind = 'version published' AND noticed_at IS NULL ORDER BY id
  ''');
  var delivered = 0;
  for (final [eventId, templateId as String, version as int] in events) {
    final pair = _pair(
      await publishedVersions(db, templateId: templateId),
      version,
    );
    if (pair != null) {
      final (before, after) = pair;
      final changes = termChanges(before, after);
      final holders = await db.execute(
        Sql.named('''
          SELECT c.id::text, c.label, m.user_id::text,
                 coalesce(p.enabled, false)
                   AND NOT EXISTS (SELECT 1 FROM member_mutes x
                                   WHERE x.user_id = m.user_id
                                     AND x.card_id = c.id)
          FROM cards c
          JOIN memberships m ON m.household_id = c.household_id
          LEFT JOIN member_preferences p ON p.user_id = m.user_id
          WHERE c.template_id = @t
        '''),
        parameters: {'t': templateId},
      );
      for (final [cardId as String, label, userId as String, wants as bool]
          in holders) {
        await db.execute(
          Sql.named('''
            INSERT INTO terms_changed (card_id, user_id, version)
            VALUES (@c::uuid, @u::uuid, @v)
            ON CONFLICT (card_id, user_id) DO UPDATE
              SET version = EXCLUDED.version, created_at = now()
          '''),
          parameters: {'c': cardId, 'u': userId, 'v': version},
        );
        if (!wants) continue;
        final name = (label as String?)?.trim();
        final notice = changeNotice(
          cardName: name == null || name.isEmpty
              ? productName(after.template.issuer, after.template.product)
              : name,
          cardId: cardId,
          version: version,
          changes: changes,
          effectiveFrom: after.effectiveFrom,
          today: today,
        );
        delivered += await sendOnce(
          db,
          push,
          userId,
          notice.data['noticeId']!,
          notice,
        );
      }
    }
    await db.execute(
      Sql.named('UPDATE catalog_events SET noticed_at = now() WHERE id = @id'),
      parameters: {'id': eventId},
    );
  }
  return delivered;
}

/// [userId]'s marks on [cards], each with the version, the date it takes
/// effect and what changed, for the household data snapshot.
Future<List<Map<String, Object?>>> termsChangedMarks(
  Session db,
  String userId,
  List<Card> cards,
  Map<String, List<TemplateVersion>> versionsByTemplate,
) async {
  final byId = {for (final c in cards) c.id: c};
  final rows = await db.execute(
    Sql.named('''
      SELECT card_id::text, version FROM terms_changed
      WHERE user_id = @u::uuid ORDER BY created_at, card_id
    '''),
    parameters: {'u': userId},
  );
  return [
    for (final [cardId as String, version as int] in rows)
      if (byId[cardId]?.templateId case final templateId?)
        if (_pair(versionsByTemplate[templateId] ?? const [], version) case (
          final before,
          final after,
        ))
          {
            'cardId': cardId,
            'version': version,
            'effectiveFrom': after.effectiveFrom,
            'changes': termChanges(before, after),
          },
  ];
}

/// Adds `POST /v1/cards/<cardId>/terms-seen`, which clears the caller's mark
/// on a card of their household (204, whether or not there was one; 404 for
/// any other card). Readers may: it changes nothing shared.
void addChangeNoticeRoutes(RouteTable routes, SignedIn signedIn) {
  final uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

  Future<Response> seen(Request request, Caller caller, Session db) async {
    final cardId = request.params['cardId']!;
    final found =
        uuid.hasMatch(cardId) &&
        (await db.execute(
          Sql.named(
            'SELECT 1 FROM cards WHERE id = @c::uuid AND household_id = @h::uuid',
          ),
          parameters: {'c': cardId, 'h': caller.householdId},
        )).isNotEmpty;
    if (!found) return jsonResponse({'error': 'not found'}, status: 404);
    await db.execute(
      Sql.named(
        'DELETE FROM terms_changed WHERE card_id = @c::uuid AND user_id = @u::uuid',
      ),
      parameters: {'c': cardId, 'u': caller.userId},
    );
    return Response(204);
  }

  routes.add('POST', '/v1/cards/<cardId>/terms-seen', signedIn(seen));
}
