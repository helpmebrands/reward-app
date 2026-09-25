/// A household's cards, credits and claims: served as the domain's
/// `AppData`, with linked credits resolved from the catalogue, and written
/// through routes that keep catalogue terms out of the household's hands.
/// Documented in `lat.md/api/api-architecture.md#Household data`.
library;

import 'dart:convert';

import 'package:domain/domain.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'auth.dart';
import 'catalog.dart';
import 'catalog_admin.dart' show parseCreditTerms;
import 'devices.dart' show InvalidField;
import 'src/database.dart';
import 'src/responses.dart';
import 'change_notices.dart';
import 'src/routes.dart';
import 'src/signed_in.dart';

/// The snapshot version the api serves, the app's current one.
const servedDataVersion = 2;

/// Settings the household does not hold: the app's own defaults.
const servedSettings = Settings(useSoonDays: 30, theme: ThemeSetting.system);

String _iso(Object? value) => (value! as DateTime).toUtc().toIso8601String();
String? _date(Object? value) => value == null
    ? null
    : (value as DateTime).toIso8601String().substring(0, 10);

/// Everything a household holds, as the snapshot the app already reads.
class HouseholdData {
  HouseholdData(this.data, this.versionsByTemplate);

  final AppData data;

  /// The published versions of every template a card links to.
  final Map<String, List<TemplateVersion>> versionsByTemplate;
}

/// Makes sure every linked card has a benefit row for every credit any
/// version in force by [today] has had, so a credit added in a new version
/// has household state (and a claimable id) the day it appears.
Future<void> _materializeLinkedCredits(
  Session db,
  String householdId,
  Map<String, List<TemplateVersion>> versions,
  IsoDate today,
) async {
  final cards = await db.execute(
    Sql.named(
      'SELECT id::text, template_id FROM cards '
      'WHERE household_id = @h::uuid AND template_id IS NOT NULL',
    ),
    parameters: {'h': householdId},
  );
  for (final [cardId, templateId] in cards) {
    final credits = {
      for (final v in versions[templateId] ?? const <TemplateVersion>[])
        if (compareIsoDate(v.effectiveFrom, today) <= 0)
          for (final c in v.template.benefits) c.id,
    };
    for (final credit in credits) {
      await db.execute(
        Sql.named('''
          INSERT INTO benefits (household_id, card_id, template_credit_id)
          VALUES (@h::uuid, @c::uuid, @credit)
          ON CONFLICT (card_id, template_credit_id) DO NOTHING
        '''),
        parameters: {'h': householdId, 'c': cardId, 'credit': credit},
      );
    }
  }
}

/// The household as `AppData` on [today]: a linked card named and priced by
/// its template's version in force, each linked credit resolved by the
/// domain for the cycle it is in, and a credit not yet or no longer in any
/// version left out.
Future<HouseholdData> loadHousehold(
  Session db,
  String householdId,
  IsoDate today,
) async {
  final templateIds = (await db.execute(
    Sql.named(
      'SELECT DISTINCT template_id FROM cards '
      'WHERE household_id = @h::uuid AND template_id IS NOT NULL',
    ),
    parameters: {'h': householdId},
  )).map((r) => r[0]! as String);
  final versions = {
    for (final id in templateIds)
      id: await publishedVersions(db, templateId: id),
  };
  await _materializeLinkedCredits(db, householdId, versions, today);

  final cardRows = await db.execute(
    Sql.named('''
      SELECT id::text, template_id, label, issuer, product, network, kind,
             last4, annual_fee_cents, anniversary_on, archived, created_at,
             updated_at
      FROM cards WHERE household_id = @h::uuid ORDER BY created_at, id
    '''),
    parameters: {'h': householdId},
  );
  final cards = <Card>[];
  for (final r in cardRows) {
    final templateId = r[1] as String?;
    final template = templateId == null
        ? null
        : (versionInForce(versions[templateId]!, today) ??
                  versions[templateId]!.first)
              .template;
    cards.add(
      Card(
        id: r[0]! as String,
        templateId: templateId,
        label: r[2] as String?,
        issuer: template?.issuer ?? r[3]! as String,
        product: template?.product ?? r[4]! as String,
        network:
            template?.network ?? CardNetwork.values.byName(r[5]! as String),
        kind: CardKind.values.byName(r[6]! as String),
        last4: r[7] as String?,
        annualFeeCents: template?.annualFeeCents ?? r[8]! as int,
        anniversaryOn: _date(r[9])!,
        archived: r[10]! as bool,
        createdAt: _iso(r[11]),
        updatedAt: _iso(r[12]),
      ),
    );
  }
  final cardsById = {for (final c in cards) c.id: c};

  final claims = [
    for (final r in await db.execute(
      Sql.named('''
        SELECT id::text, benefit_id::text, cycle_key, amount_cents,
               claimed_at, note
        FROM claims WHERE household_id = @h::uuid
        ORDER BY claimed_at, created_at
      '''),
      parameters: {'h': householdId},
    ))
      Claim(
        id: r[0]! as String,
        benefitId: r[1]! as String,
        cycleKey: r[2]! as String,
        amountCents: r[3]! as int,
        claimedAt: r[4]! as String,
        note: r[5] as String?,
      ),
  ];

  final benefits = <Benefit>[];
  for (final r in await db.execute(
    Sql.named('''
      SELECT id::text, card_id::text, template_credit_id, enrolled_at,
             enrollment_note, enrollment_url, spend_met_at, last_call_only,
             active, created_at, updated_at, name, description, category,
             icon, merchant, value_cents, cadence, anchor, interval_months,
             enrollment_required, spend_threshold_cents, ends_on,
             redemption_steps, notes, opted_out_at, tracked_from
      FROM benefits WHERE household_id = @h::uuid ORDER BY created_at, id
    '''),
    parameters: {'h': householdId},
  )) {
    final card = cardsById[r[1]]!;
    final creditId = r[2] as String?;
    final state = LinkedBenefitState(
      id: r[0]! as String,
      cardId: card.id,
      templateBenefitId: creditId ?? '',
      enrolledAt: r[3] as String?,
      enrollmentNote: r[4] as String?,
      enrollmentUrl: r[5] as String?,
      spendMetAt: r[6] as String?,
      lastCallOnly: r[7]! as bool,
      active: r[8]! as bool,
      optedOutAt: r[25] as String?,
      trackedFrom: _date(r[26]),
      createdAt: _iso(r[9]),
      updatedAt: _iso(r[10]),
    );
    if (creditId != null) {
      final resolved = resolveLinkedBenefit(
        versions[card.templateId] ?? const [],
        state,
        card,
        today,
        claims: [
          for (final c in claims)
            if (c.benefitId == state.id) c,
        ],
      );
      if (resolved != null) benefits.add(resolved);
      continue;
    }
    benefits.add(
      benefitFromCredit(
        benefitTemplateFromJson({
          'id': '',
          'name': r[11],
          'description': r[12],
          'category': r[13],
          'icon': r[14] ?? '',
          'merchant': r[15],
          'valueCents': r[16],
          'cadence': r[17],
          'anchor': r[18],
          'intervalMonths': r[19],
          'enrollmentRequired': r[20],
          'spendThresholdCents': r[21],
          'endsOn': _date(r[22]),
          'redemptionSteps': r[23],
          'notes': r[24],
        }),
        state,
      ).copyWith(templateBenefitId: null, icon: r[14]),
    );
  }

  return HouseholdData(
    AppData(
      version: servedDataVersion,
      cards: cards,
      benefits: benefits,
      claims: claims,
      settings: servedSettings,
    ),
    versions,
  );
}

Response _invalid(String field) =>
    jsonResponse({'error': 'invalid', 'field': field}, status: 400);
Response _notFound() => jsonResponse({'error': 'not found'}, status: 404);
Response _forbidden() => jsonResponse({'error': 'forbidden'}, status: 403);
Response _systemMaintained() =>
    jsonResponse({'error': 'system maintained'}, status: 409);

Future<Object?> _jsonBody(Request request) async {
  final text = await request.readAsString();
  if (text.trim().isEmpty) return const <String, Object?>{};
  try {
    return jsonDecode(text);
  } on FormatException {
    return null;
  }
}

/// A key's value when present: absent keys are left alone by a patch, an
/// explicit null clears.
bool _has(Map<String, dynamic> body, String key) => body.containsKey(key);

String? _optionalText(Map<String, dynamic> body, String key) {
  final value = body[key];
  if (value == null) return null;
  if (value is! String) throw InvalidField(key);
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// Adds the household data routes.
void addHouseholdDataRoutes(RouteTable routes, SignedIn signedIn) {
  Handler writer(SignedInHandler handler) =>
      signedIn((request, caller, db) async {
        if (!caller.role.canWrite) return _forbidden();
        return handler(request, caller, db);
      });

  /// The row's household and link, or null when it is not this household's.
  Future<({String? templateId})?> ownCard(
    Session db,
    Caller caller,
    String id,
  ) async {
    if (!_isUuid(id)) return null;
    final rows = await db.execute(
      Sql.named(
        'SELECT template_id FROM cards '
        'WHERE id = @id::uuid AND household_id = @h::uuid',
      ),
      parameters: {'id': id, 'h': caller.householdId},
    );
    return rows.isEmpty ? null : (templateId: rows.single[0] as String?);
  }

  Future<({String? creditId, String cardId})?> ownBenefit(
    Session db,
    Caller caller,
    String id,
  ) async {
    if (!_isUuid(id)) return null;
    final rows = await db.execute(
      Sql.named(
        'SELECT template_credit_id, card_id::text FROM benefits '
        'WHERE id = @id::uuid AND household_id = @h::uuid',
      ),
      parameters: {'id': id, 'h': caller.householdId},
    );
    return rows.isEmpty
        ? null
        : (
            creditId: rows.single[0] as String?,
            cardId: rows.single[1]! as String,
          );
  }

  Future<Response> data(Request request, Caller caller, Session db) async {
    final household = await inTransaction(
      db,
      (tx) async =>
          loadHousehold(tx, caller.householdId, await databaseToday(tx)),
    );
    return jsonResponse({
      ...appDataToJson(household.data),
      'termsChanged': await termsChangedMarks(
        db,
        caller.userId,
        household.data.cards,
        household.versionsByTemplate,
      ),
    });
  }

  /// One card and its credits, as the household sees them now.
  Future<Map<String, Object?>> cardView(
    Session db,
    Caller caller,
    String cardId,
  ) async {
    final household = await loadHousehold(
      db,
      caller.householdId,
      await databaseToday(db),
    );
    return {
      'card': cardToJson(
        household.data.cards.firstWhere((c) => c.id == cardId),
      ),
      'benefits': [
        for (final b in household.data.benefits)
          if (b.cardId == cardId) benefitToJson(b),
      ],
    };
  }

  Future<Response> addCard(Request request, Caller caller, Session db) async {
    final body = await _jsonBody(request);
    if (body is! Map<String, dynamic>) return _invalid('body');
    try {
      final anniversary = body['anniversaryOn'];
      if (anniversary is! String || anniversaryError(anniversary) != null) {
        return _invalid('anniversaryOn');
      }
      final templateId = body['templateId'];
      if (templateId != null && templateId is! String) {
        return _invalid('templateId');
      }
      final label = _optionalText(body, 'label');
      final last4 = _optionalText(body, 'last4');

      return await inTransaction(db, (tx) async {
        final today = await databaseToday(tx);
        final household = await loadHousehold(tx, caller.householdId, today);
        final String issuer;
        final String product;
        CardKind kind;
        TemplateVersion? version;
        CardNetwork? network;
        int? fee;
        if (templateId is String) {
          version = versionInForce(
            await publishedVersions(tx, templateId: templateId),
            today,
          );
          if (version == null) return _invalid('templateId');
          issuer = version.template.issuer;
          product = version.template.product;
          kind = version.template.kind;
        } else {
          issuer = _requiredText(body, 'issuer');
          product = _requiredText(body, 'product');
          network = _enum(CardNetwork.values, body, 'network');
          kind = CardKind.personal;
          final f = body['annualFeeCents'];
          if (f is! int || f < 0) return _invalid('annualFeeCents');
          fee = f;
        }
        if (_has(body, 'kind')) kind = _enum(CardKind.values, body, 'kind');

        final cards = household.data.cards;
        final String? stored;
        if (label == null) {
          stored = defaultLabel(cards, issuer, product);
        } else {
          if (labelError(
                label,
                cards: cards,
                issuer: issuer,
                product: product,
              ) !=
              null) {
            return jsonResponse({'error': 'label taken'}, status: 409);
          }
          stored = label;
        }

        final id =
            (await tx.execute(
                  Sql.named('''
            INSERT INTO cards (household_id, template_id, label, issuer,
              product, network, kind, last4, annual_fee_cents,
              anniversary_on)
            VALUES (@h::uuid, @template, @label, @issuer, @product,
              @network, @kind, @last4, @fee::int, @anniversary::date)
            RETURNING id::text
          '''),
                  parameters: {
                    'h': caller.householdId,
                    'template': templateId,
                    'label': stored,
                    'issuer': version == null ? issuer : null,
                    'product': version == null ? product : null,
                    'network': network?.name,
                    'kind': kind.name,
                    'last4': last4,
                    'fee': fee,
                    'anniversary': anniversary,
                  },
                )).single[0]!
                as String;
        return jsonResponse(await cardView(tx, caller, id), status: 201);
      });
    } on InvalidField catch (e) {
      return _invalid(e.field);
    }
  }

  Future<Response> editCard(Request request, Caller caller, Session db) async {
    final id = request.params['cardId']!;
    final body = await _jsonBody(request);
    return inTransaction(db, (tx) async {
      final own = await ownCard(tx, caller, id);
      if (own == null) return _notFound();
      if (body is! Map<String, dynamic>) return _invalid('body');
      const terms = ['issuer', 'product', 'network', 'annualFeeCents'];
      if (own.templateId != null && terms.any(body.containsKey)) {
        return _systemMaintained();
      }
      try {
        final sets = <String, Object?>{};
        if (_has(body, 'label')) sets['label'] = _optionalText(body, 'label');
        if (_has(body, 'last4')) sets['last4'] = _optionalText(body, 'last4');
        if (_has(body, 'kind')) {
          sets['kind'] = _enum(CardKind.values, body, 'kind').name;
        }
        if (_has(body, 'anniversaryOn')) {
          final a = body['anniversaryOn'];
          if (a is! String || anniversaryError(a) != null) {
            throw const InvalidField('anniversaryOn');
          }
          sets['anniversary_on'] = a;
        }
        if (_has(body, 'archived')) {
          final a = body['archived'];
          if (a is! bool) throw const InvalidField('archived');
          sets['archived'] = a;
        }
        if (_has(body, 'issuer')) {
          sets['issuer'] = _requiredText(body, 'issuer');
        }
        if (_has(body, 'product')) {
          sets['product'] = _requiredText(body, 'product');
        }
        if (_has(body, 'network')) {
          sets['network'] = _enum(CardNetwork.values, body, 'network').name;
        }
        if (_has(body, 'annualFeeCents')) {
          final f = body['annualFeeCents'];
          if (f is! int || f < 0) throw const InvalidField('annualFeeCents');
          sets['annual_fee_cents'] = f;
        }

        final today = await databaseToday(tx);
        final household = await loadHousehold(tx, caller.householdId, today);
        final current = household.data.cards.firstWhere((c) => c.id == id);
        if (sets.containsKey('label') ||
            sets.containsKey('issuer') ||
            sets.containsKey('product')) {
          final label = sets.containsKey('label')
              ? sets['label'] as String?
              : current.label;
          if (labelError(
                label ?? '',
                cards: household.data.cards,
                issuer: (sets['issuer'] ?? current.issuer) as String,
                product: (sets['product'] ?? current.product) as String,
                cardId: id,
              ) !=
              null) {
            return jsonResponse({'error': 'label taken'}, status: 409);
          }
        }
        if (sets.isNotEmpty) {
          final columns = [
            for (final column in sets.keys)
              '$column = @$column${_casts[column] ?? ''}',
          ];
          await tx.execute(
            Sql.named(
              'UPDATE cards SET ${columns.join(', ')}, updated_at = now() '
              'WHERE id = @id::uuid',
            ),
            parameters: {...sets, 'id': id},
          );
        }
        return jsonResponse((await cardView(tx, caller, id))['card']!);
      } on InvalidField catch (e) {
        return _invalid(e.field);
      }
    });
  }

  Future<Response> deleteCard(
    Request request,
    Caller caller,
    Session db,
  ) async {
    final id = request.params['cardId']!;
    if (await ownCard(db, caller, id) == null) return _notFound();
    await db.execute(
      Sql.named('DELETE FROM cards WHERE id = @id::uuid'),
      parameters: {'id': id},
    );
    return Response(204);
  }

  /// Writes a household credit's terms, from a body checked by the domain.
  Map<String, Object?> termColumns(Map<String, dynamic> body) {
    final credit = parseCreditTerms(body, '', id: '');
    final json = benefitTemplateToJson(credit);
    return {
      'name': credit.name,
      'description': credit.description,
      'category': json['category'],
      'icon': credit.icon.isEmpty ? null : credit.icon,
      'merchant': credit.merchant,
      'value_cents': credit.valueCents,
      'cadence': credit.cadence.name,
      'anchor': credit.anchor.name,
      'interval_months': credit.intervalMonths,
      'enrollment_required': credit.enrollmentRequired,
      'spend_threshold_cents': credit.spendThresholdCents,
      'ends_on': credit.endsOn,
      'redemption_steps': jsonEncode(credit.redemptionSteps),
      'notes': credit.notes,
    };
  }

  Future<Response> benefitView(
    Session db,
    Caller caller,
    String id, {
    int status = 200,
  }) async {
    final household = await loadHousehold(
      db,
      caller.householdId,
      await databaseToday(db),
    );
    return jsonResponse(
      benefitToJson(household.data.benefits.firstWhere((b) => b.id == id)),
      status: status,
    );
  }

  Future<Response> addBenefit(
    Request request,
    Caller caller,
    Session db,
  ) async {
    final cardId = request.params['cardId']!;
    final body = await _jsonBody(request);
    return inTransaction(db, (tx) async {
      final own = await ownCard(tx, caller, cardId);
      if (own == null) return _notFound();
      if (own.templateId != null) return _systemMaintained();
      if (body is! Map<String, dynamic>) return _invalid('body');
      try {
        final columns = termColumns(body);
        final id =
            (await tx.execute(
                  Sql.named('''
            INSERT INTO benefits (household_id, card_id, ${columns.keys.join(', ')})
            VALUES (@h::uuid, @card::uuid,
              ${columns.keys.map((c) => '@$c${_casts[c] ?? ''}').join(', ')})
            RETURNING id::text
          '''),
                  parameters: {
                    ...columns,
                    'h': caller.householdId,
                    'card': cardId,
                  },
                )).single[0]!
                as String;
        return await benefitView(tx, caller, id, status: 201);
      } on InvalidField catch (e) {
        return _invalid(e.field);
      }
    });
  }

  Future<Response> editBenefit(
    Request request,
    Caller caller,
    Session db,
  ) async {
    final id = request.params['benefitId']!;
    final body = await _jsonBody(request);
    return inTransaction(db, (tx) async {
      final own = await ownBenefit(tx, caller, id);
      if (own == null) return _notFound();
      if (own.creditId != null) return _systemMaintained();
      if (body is! Map<String, dynamic>) return _invalid('body');
      try {
        final columns = termColumns(body);
        await tx.execute(
          Sql.named(
            'UPDATE benefits SET '
            '${columns.keys.map((c) => '$c = @$c${_casts[c] ?? ''}').join(', ')}'
            ', updated_at = now() WHERE id = @id::uuid',
          ),
          parameters: {...columns, 'id': id},
        );
        return await benefitView(tx, caller, id);
      } on InvalidField catch (e) {
        return _invalid(e.field);
      }
    });
  }

  Future<Response> putState(Request request, Caller caller, Session db) async {
    final id = request.params['benefitId']!;
    final body = await _jsonBody(request);
    return inTransaction(db, (tx) async {
      if (await ownBenefit(tx, caller, id) == null) return _notFound();
      if (body is! Map<String, dynamic>) return _invalid('body');
      final sets = <String, Object?>{};
      for (final (key, column) in [
        ('enrolledAt', 'enrolled_at'),
        ('enrollmentNote', 'enrollment_note'),
        ('enrollmentUrl', 'enrollment_url'),
        ('spendMetAt', 'spend_met_at'),
        ('optedOutAt', 'opted_out_at'),
        ('trackedFrom', 'tracked_from'),
      ]) {
        if (!_has(body, key)) continue;
        final value = body[key];
        if (value != null && value is! String) return _invalid(key);
        sets[column] = value;
      }
      final trackedFrom = sets['tracked_from'];
      if (trackedFrom is String && anniversaryError(trackedFrom) != null) {
        return _invalid('trackedFrom');
      }
      final url = sets['enrollment_url'];
      if (url is String && enrollmentUrlError(url) != null) {
        return _invalid('enrollmentUrl');
      }
      for (final (key, column) in [
        ('lastCallOnly', 'last_call_only'),
        ('active', 'active'),
      ]) {
        if (!_has(body, key)) continue;
        if (body[key] is! bool) return _invalid(key);
        sets[column] = body[key];
      }
      if (sets.isNotEmpty) {
        await tx.execute(
          Sql.named(
            'UPDATE benefits SET '
            '${sets.keys.map((c) => '$c = @$c${_casts[c] ?? ''}').join(', ')}, '
            'updated_at = now() WHERE id = @id::uuid',
          ),
          parameters: {...sets, 'id': id},
        );
      }
      return benefitView(tx, caller, id);
    });
  }

  Future<Response> deleteBenefit(
    Request request,
    Caller caller,
    Session db,
  ) async {
    final id = request.params['benefitId']!;
    final own = await ownBenefit(db, caller, id);
    if (own == null) return _notFound();
    if (own.creditId != null) return _systemMaintained();
    await db.execute(
      Sql.named('DELETE FROM benefits WHERE id = @id::uuid'),
      parameters: {'id': id},
    );
    return Response(204);
  }

  Future<Response> addClaim(Request request, Caller caller, Session db) async {
    final key = request.headers['idempotency-key']?.trim() ?? '';
    if (key.isEmpty) return _invalid('Idempotency-Key');
    final body = await _jsonBody(request);
    if (body is! Map<String, dynamic>) return _invalid('body');
    final benefitId = body['benefitId'];
    if (benefitId is! String) return _invalid('benefitId');
    final cycleKey = body['cycleKey'];
    if (cycleKey is! String || anniversaryError(cycleKey) != null) {
      return _invalid('cycleKey');
    }
    final amount = body['amountCents'];
    if (amount is! int || amount <= 0) return _invalid('amountCents');
    final claimedAt = body['claimedAt'];
    if (claimedAt != null &&
        (claimedAt is! String || DateTime.tryParse(claimedAt) == null)) {
      return _invalid('claimedAt');
    }
    final note = body['note'];
    if (note != null && note is! String) return _invalid('note');
    // What the key promises: the same request. Canonical, so key order in
    // the client's JSON does not matter.
    final canonical = jsonEncode({
      'amountCents': amount,
      'benefitId': benefitId,
      'claimedAt': claimedAt,
      'cycleKey': cycleKey,
      'note': note,
    });

    return inTransaction(db, (tx) async {
      if (await ownBenefit(tx, caller, benefitId) == null) return _notFound();
      final inserted = await tx.execute(
        Sql.named('''
          INSERT INTO claims (household_id, benefit_id, cycle_key,
            amount_cents, claimed_at, note, idempotency_key, request_body)
          VALUES (@h::uuid, @b::uuid, @cycle, @amount, @at, @note, @key,
            @request)
          ON CONFLICT (household_id, idempotency_key) DO NOTHING
          RETURNING id::text
        '''),
        parameters: {
          'h': caller.householdId,
          'b': benefitId,
          'cycle': cycleKey,
          'amount': amount,
          'at': claimedAt ?? DateTime.now().toUtc().toIso8601String(),
          'note': note,
          'key': key,
          'request': canonical,
        },
      );
      final row = (await tx.execute(
        Sql.named('''
          SELECT id::text, benefit_id::text, cycle_key, amount_cents,
                 claimed_at, note, request_body
          FROM claims WHERE household_id = @h::uuid AND idempotency_key = @key
        '''),
        parameters: {'h': caller.householdId, 'key': key},
      )).single;
      if (inserted.isEmpty && row[6] != canonical) {
        return jsonResponse({'error': 'idempotency key reused'}, status: 409);
      }
      return jsonResponse(
        claimToJson(
          Claim(
            id: row[0]! as String,
            benefitId: row[1]! as String,
            cycleKey: row[2]! as String,
            amountCents: row[3]! as int,
            claimedAt: row[4]! as String,
            note: row[5] as String?,
          ),
        ),
        status: 201,
      );
    });
  }

  Future<Response> deleteClaim(
    Request request,
    Caller caller,
    Session db,
  ) async {
    final id = request.params['claimId']!;
    if (!_isUuid(id)) return _notFound();
    final removed = await db.execute(
      Sql.named(
        'DELETE FROM claims WHERE id = @id::uuid AND household_id = @h::uuid',
      ),
      parameters: {'id': id, 'h': caller.householdId},
    );
    return removed.affectedRows > 0 ? Response(204) : _notFound();
  }

  /// Replaces a linked card with one the household maintains, in one
  /// transaction: the new card and credits copy the terms resolved today
  /// and every piece of household state, the claims and every member's
  /// mutes move to the new ids, and the linked card is deleted.
  Future<Response> convert(Request request, Caller caller, Session db) async {
    final id = request.params['cardId']!;
    return inTransaction(db, (tx) async {
      final own = await ownCard(tx, caller, id);
      if (own == null) return _notFound();
      if (own.templateId == null) {
        return jsonResponse({'error': 'user maintained'}, status: 409);
      }
      final today = await databaseToday(tx);
      final household = await loadHousehold(tx, caller.householdId, today);
      final card = household.data.cards.firstWhere((c) => c.id == id);
      final created =
          (await tx.execute(
                Sql.named('''
          INSERT INTO cards (household_id, label, issuer, product, network,
            kind, last4, annual_fee_cents, anniversary_on, archived,
            created_at)
          SELECT household_id, label, @issuer, @product, @network, kind,
            last4, @fee, anniversary_on, archived, created_at
          FROM cards WHERE id = @id::uuid
          RETURNING id::text
        '''),
                parameters: {
                  'id': id,
                  'issuer': card.issuer,
                  'product': card.product,
                  'network': card.network.name,
                  'fee': card.annualFeeCents,
                },
              )).single[0]!
              as String;

      final benefitIds = <String, String>{};
      for (final b in household.data.benefits.where((b) => b.cardId == id)) {
        final terms = termColumns(benefitToJson(b));
        final state = {
          'enrolled_at': b.enrolledAt,
          'enrollment_note': b.enrollmentNote,
          'enrollment_url': b.enrollmentUrl,
          'spend_met_at': b.spendMetAt,
          'last_call_only': b.lastCallOnly,
          'active': b.active,
          'opted_out_at': b.optedOutAt,
          'tracked_from': b.trackedFrom,
        };
        final columns = {...terms, ...state};
        final newId =
            (await tx.execute(
                  Sql.named('''
            INSERT INTO benefits (household_id, card_id, created_at,
              ${columns.keys.join(', ')})
            SELECT household_id, @card::uuid, created_at,
              ${columns.keys.map((c) => '@$c${_casts[c] ?? ''}').join(', ')}
            FROM benefits WHERE id = @old::uuid
            RETURNING id::text
          '''),
                  parameters: {...columns, 'card': created, 'old': b.id},
                )).single[0]!
                as String;
        benefitIds[b.id] = newId;
        for (final table in ['claims', 'member_mutes']) {
          await tx.execute(
            Sql.named(
              'UPDATE $table SET benefit_id = @new::uuid '
              'WHERE benefit_id = @old::uuid',
            ),
            parameters: {'new': newId, 'old': b.id},
          );
        }
      }
      await tx.execute(
        Sql.named(
          'UPDATE member_mutes SET card_id = @new::uuid '
          'WHERE card_id = @old::uuid',
        ),
        parameters: {'new': created, 'old': id},
      );
      await tx.execute(
        Sql.named('DELETE FROM cards WHERE id = @id::uuid'),
        parameters: {'id': id},
      );
      return jsonResponse({
        ...await cardView(tx, caller, created),
        'replaces': id,
        'benefitIds': benefitIds,
      });
    });
  }

  routes
    ..add('GET', '/v1/household/data', signedIn(data))
    ..add('POST', '/v1/cards/<cardId>/convert', writer(convert))
    ..add('POST', '/v1/cards', writer(addCard))
    ..add('PATCH', '/v1/cards/<cardId>', writer(editCard))
    ..add('DELETE', '/v1/cards/<cardId>', writer(deleteCard))
    ..add('POST', '/v1/cards/<cardId>/benefits', writer(addBenefit))
    ..add('PUT', '/v1/benefits/<benefitId>', writer(editBenefit))
    ..add('PUT', '/v1/benefits/<benefitId>/state', writer(putState))
    ..add('DELETE', '/v1/benefits/<benefitId>', writer(deleteBenefit))
    ..add('POST', '/v1/claims', writer(addClaim))
    ..add('DELETE', '/v1/claims/<claimId>', writer(deleteClaim));
}

/// Casts for the columns a patch writes whose parameter type Postgres
/// cannot infer.
const _casts = {
  'anniversary_on': '::date',
  'ends_on': '::date',
  'tracked_from': '::date',
  'interval_months': '::int',
  'spend_threshold_cents': '::int',
  'redemption_steps': '::jsonb',
};

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

bool _isUuid(String id) => _uuid.hasMatch(id);

String _requiredText(Map<String, dynamic> body, String key) {
  final value = body[key];
  if (value is! String || value.trim().isEmpty) throw InvalidField(key);
  return value.trim();
}

E _enum<E extends Enum>(List<E> values, Map<String, dynamic> body, String key) {
  final value = body[key];
  for (final v in values) {
    if (v.name == value) return v;
  }
  throw InvalidField(key);
}
