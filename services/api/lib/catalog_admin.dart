/// The catalogue admin api: new templates and drafts, edits checked by the
/// domain's rules, and publishing with provenance. Documented in
/// `lat.md/api/api-architecture.md#Catalogue admin`.
library;

import 'dart:convert';

import 'package:domain/domain.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'auth.dart';
import 'catalog.dart';
import 'devices.dart' show InvalidField;
import 'src/database.dart';
import 'src/responses.dart';
import 'src/routes.dart';
import 'src/signed_in.dart';

Future<bool> isAdmin(Session db, String userId) async => (await db.execute(
  Sql.named('SELECT 1 FROM admins WHERE user_id = @u::uuid'),
  parameters: {'u': userId},
)).isNotEmpty;

final _templateId = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');
final _creditSlug = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');

/// A draft's body read into a `TemplateVersion` for [templateId], checked
/// field by field; the first field at fault is thrown as [InvalidField].
/// [effectiveFrom] is kept when the body names none.
TemplateVersion parseVersion(
  String templateId,
  int version,
  Object? body, {
  required IsoDate effectiveFrom,
}) {
  if (body is! Map<String, dynamic>) throw const InvalidField('body');

  T field<T>(Map<String, dynamic> json, String name, String at) {
    final value = json[name];
    if (value is! T) throw InvalidField(at);
    return value;
  }

  String text(Map<String, dynamic> json, String name, String at) {
    final value = field<String>(json, name, at);
    if (value.trim().isEmpty) throw InvalidField(at);
    return value;
  }

  E choice<E extends Enum>(
    List<E> values,
    Map<String, dynamic> json,
    String name,
    String at, [
    String Function(E value)? spell,
  ]) {
    final value = field<String>(json, name, at);
    for (final v in values) {
      if ((spell?.call(v) ?? v.name) == value) return v;
    }
    throw InvalidField(at);
  }

  final from = body['effectiveFrom'] ?? effectiveFrom;
  if (from is! String || anniversaryError(from) != null) {
    throw const InvalidField('effectiveFrom');
  }
  final fee = field<int>(body, 'annualFeeCents', 'annualFeeCents');
  if (fee < 0) throw const InvalidField('annualFeeCents');

  final credits = <BenefitTemplate>[];
  final ids = <String>{};
  for (final (i, raw) in field<List>(body, 'credits', 'credits').indexed) {
    final at = 'credits[$i]';
    if (raw is! Map<String, dynamic>) throw InvalidField(at);
    final id = text(raw, 'id', '$at.id');
    final slash = id.indexOf('/');
    if (slash < 0 ||
        id.substring(0, slash) != templateId ||
        !_creditSlug.hasMatch(id.substring(slash + 1)) ||
        !ids.add(id)) {
      throw InvalidField('$at.id');
    }
    final cadence = choice(Cadence.values, raw, 'cadence', '$at.cadence');
    final interval = raw['intervalMonths'];
    if (interval != null && interval is! int) {
      throw InvalidField('$at.intervalMonths');
    }
    if (intervalMonthsError(cadence, '${interval ?? ''}') != null) {
      throw InvalidField('$at.intervalMonths');
    }
    final value = field<int>(raw, 'valueCents', '$at.valueCents');
    if (value <= 0) throw InvalidField('$at.valueCents');
    final spend = raw['spendThresholdCents'];
    if (spend != null && (spend is! int || spend <= 0)) {
      throw InvalidField('$at.spendThresholdCents');
    }
    final endsOn = raw['endsOn'];
    if (endsOn != null && (endsOn is! String || endsOnError(endsOn) != null)) {
      throw InvalidField('$at.endsOn');
    }
    final steps = raw['redemptionSteps'] ?? const <Object>[];
    if (steps is! List || steps.any((s) => s is! String)) {
      throw InvalidField('$at.redemptionSteps');
    }
    final enrollment = raw['enrollmentRequired'] ?? false;
    if (enrollment is! bool) throw InvalidField('$at.enrollmentRequired');
    for (final optional in ['description', 'merchant', 'notes']) {
      if (raw[optional] != null && raw[optional] is! String) {
        throw InvalidField('$at.$optional');
      }
    }
    credits.add(
      BenefitTemplate(
        id: id,
        name: text(raw, 'name', '$at.name'),
        description: raw['description'] as String?,
        category: choice(
          BenefitCategory.values,
          raw,
          'category',
          '$at.category',
          (c) => c == BenefitCategory.feeCredit ? 'fee_credit' : c.name,
        ),
        icon: text(raw, 'icon', '$at.icon'),
        merchant: raw['merchant'] as String?,
        valueCents: value,
        cadence: cadence,
        anchor: choice(CycleAnchor.values, raw, 'anchor', '$at.anchor'),
        intervalMonths: interval as int?,
        enrollmentRequired: enrollment,
        spendThresholdCents: spend as int?,
        endsOn: endsOn as String?,
        redemptionSteps: steps.cast<String>(),
        notes: raw['notes'] as String?,
      ),
    );
  }

  return TemplateVersion(
    version: version,
    effectiveFrom: from,
    template: CardTemplate(
      id: templateId,
      issuer: text(body, 'issuer', 'issuer'),
      product: text(body, 'product', 'product'),
      network: choice(CardNetwork.values, body, 'network', 'network'),
      kind: choice(CardKind.values, body, 'kind', 'kind'),
      annualFeeCents: fee,
      benefits: credits,
    ),
  );
}

/// Replaces a draft's fields and credits with [v]'s.
Future<void> writeDraft(Session tx, TemplateVersion v) async {
  final key = {'t': v.templateId, 'v': v.version};
  await tx.execute(
    Sql.named('''
      UPDATE template_versions SET effective_from = @from::date,
        issuer = @issuer, product = @product, network = @network,
        kind = @kind, annual_fee_cents = @fee
      WHERE template_id = @t AND version = @v
    '''),
    parameters: {
      ...key,
      'from': v.effectiveFrom,
      'issuer': v.template.issuer,
      'product': v.template.product,
      'network': v.template.network.name,
      'kind': v.template.kind.name,
      'fee': v.template.annualFeeCents,
    },
  );
  await tx.execute(
    Sql.named(
      'DELETE FROM template_credits WHERE template_id = @t AND version = @v',
    ),
    parameters: key,
  );
  for (final (position, credit) in v.template.benefits.indexed) {
    final json = benefitTemplateToJson(credit);
    await tx.execute(
      Sql.named('''
        INSERT INTO template_credits (template_id, version, credit_id,
          position, name, description, category, icon, merchant, value_cents,
          cadence, anchor, interval_months, enrollment_required,
          spend_threshold_cents, ends_on, redemption_steps, notes)
        VALUES (@t, @v, @id, @position, @name, @description, @category,
          @icon, @merchant, @value, @cadence, @anchor, @interval::int,
          @enrollment, @spend::int, @endsOn::date, @steps::jsonb, @notes)
      '''),
      parameters: {
        ...key,
        'id': credit.id,
        'position': position,
        'name': credit.name,
        'description': credit.description,
        'category': json['category'],
        'icon': credit.icon,
        'merchant': credit.merchant,
        'value': credit.valueCents,
        'cadence': credit.cadence.name,
        'anchor': credit.anchor.name,
        'interval': credit.intervalMonths,
        'enrollment': credit.enrollmentRequired,
        'spend': credit.spendThresholdCents,
        'endsOn': credit.endsOn,
        'steps': jsonEncode(credit.redemptionSteps),
        'notes': credit.notes,
      },
    );
  }
}

/// The version with its status and provenance, as the admin routes answer.
Future<Map<String, Object?>?> adminVersionJson(
  Session db,
  String templateId,
  int version,
) async {
  final meta = await db.execute(
    Sql.named('''
      SELECT status, published_by, published_at, source_url, notes
      FROM template_versions WHERE template_id = @t AND version = @v
    '''),
    parameters: {'t': templateId, 'v': version},
  );
  if (meta.isEmpty) return null;
  final [status, by, at, source, notes] = meta.single;
  final v = (await loadVersions(
    db,
    templateId: templateId,
    version: version,
    status: status! as String,
  )).single;
  return {
    ...templateVersionToJson(v),
    'status': status,
    'publishedBy': ?by,
    'publishedAt': ?(at as DateTime?)?.toUtc().toIso8601String(),
    'sourceUrl': ?source,
    'notes': ?notes,
  };
}

Response _notFound() => jsonResponse({'error': 'not found'}, status: 404);
Response _conflict(String reason) =>
    jsonResponse({'error': reason}, status: 409);
Response _invalid(String field) =>
    jsonResponse({'error': 'invalid', 'field': field}, status: 400);

Future<Object?> _jsonBody(Request request) async {
  try {
    return jsonDecode(await request.readAsString());
  } on FormatException {
    return null;
  }
}

/// Adds the `/v1/admin/catalog` routes; every one is admin only.
void addCatalogAdminRoutes(RouteTable routes, SignedIn signedIn) {
  Handler admin(SignedInHandler handler) =>
      signedIn((request, caller, db) async {
        if (!await isAdmin(db, caller.userId)) {
          return jsonResponse({'error': 'forbidden'}, status: 403);
        }
        return handler(request, caller, db);
      });

  /// The version in the path, or null when it is not a number.
  int? versionOf(Request request) =>
      int.tryParse(request.params['version'] ?? '');

  Future<String?> statusOf(Session db, String templateId, int version) async {
    final rows = await db.execute(
      Sql.named(
        'SELECT status FROM template_versions '
        'WHERE template_id = @t AND version = @v',
      ),
      parameters: {'t': templateId, 'v': version},
    );
    return rows.isEmpty ? null : rows.single[0] as String?;
  }

  Future<Response> createTemplate(
    Request request,
    Caller caller,
    Session db,
  ) async {
    final body = await _jsonBody(request);
    if (body is! Map<String, dynamic>) return _invalid('body');
    final id = body['id'];
    if (id is! String || !_templateId.hasMatch(id)) return _invalid('id');
    final exists = await db.execute(
      Sql.named('SELECT 1 FROM card_templates WHERE id = @id'),
      parameters: {'id': id},
    );
    if (exists.isNotEmpty) return _conflict('template exists');
    final TemplateVersion draft;
    try {
      draft = parseVersion(id, 1, body, effectiveFrom: await databaseToday(db));
    } on InvalidField catch (e) {
      return _invalid(e.field);
    }
    return inTransaction(db, (tx) async {
      final created = await tx.execute(
        Sql.named(
          'INSERT INTO card_templates (id) VALUES (@id) '
          'ON CONFLICT DO NOTHING RETURNING id',
        ),
        parameters: {'id': id},
      );
      if (created.isEmpty) return _conflict('template exists');
      await tx.execute(
        Sql.named('''
          INSERT INTO template_versions (template_id, version, effective_from,
            status, issuer, product, network, kind, annual_fee_cents)
          VALUES (@id, 1, current_date, 'draft', '', '', 'other',
            'personal', 0)
        '''),
        parameters: {'id': id},
      );
      await writeDraft(tx, draft);
      return jsonResponse((await adminVersionJson(tx, id, 1))!, status: 201);
    });
  }

  Future<Response> createDraft(
    Request request,
    Caller caller,
    Session db,
  ) async {
    final id = request.params['templateId']!;
    return inTransaction(db, (tx) async {
      final rows = await tx.execute(
        Sql.named('''
          SELECT version, status FROM template_versions
          WHERE template_id = @t ORDER BY version DESC FOR UPDATE
        '''),
        parameters: {'t': id},
      );
      if (rows.isEmpty) return _notFound();
      if (rows.any((r) => r[1] == 'draft')) return _conflict('draft exists');
      final latest = rows.first[0]! as int;
      final from = (await publishedVersions(
        tx,
        templateId: id,
      )).firstWhere((v) => v.version == latest);
      final next = latest + 1;
      await tx.execute(
        Sql.named('''
          INSERT INTO template_versions (template_id, version, effective_from,
            status, issuer, product, network, kind, annual_fee_cents)
          SELECT template_id, @next, effective_from, 'draft', issuer, product,
            network, kind, annual_fee_cents
          FROM template_versions WHERE template_id = @t AND version = @v
        '''),
        parameters: {'t': id, 'v': latest, 'next': next},
      );
      await writeDraft(
        tx,
        TemplateVersion(
          version: next,
          effectiveFrom: from.effectiveFrom,
          template: from.template,
        ),
      );
      return jsonResponse((await adminVersionJson(tx, id, next))!, status: 201);
    });
  }

  Future<Response> editDraft(Request request, Caller caller, Session db) async {
    final id = request.params['templateId']!;
    final version = versionOf(request);
    if (version == null) return _notFound();
    final status = await statusOf(db, id, version);
    if (status == null) return _notFound();
    if (status == 'published') return _conflict('published');
    final current = (await loadVersions(
      db,
      templateId: id,
      version: version,
      status: 'draft',
    )).single;
    final TemplateVersion draft;
    try {
      draft = parseVersion(
        id,
        version,
        await _jsonBody(request),
        effectiveFrom: current.effectiveFrom,
      );
    } on InvalidField catch (e) {
      return _invalid(e.field);
    }
    return inTransaction(db, (tx) async {
      await writeDraft(tx, draft);
      return jsonResponse((await adminVersionJson(tx, id, version))!);
    });
  }

  Future<Response> publish(Request request, Caller caller, Session db) async {
    final id = request.params['templateId']!;
    final version = versionOf(request);
    if (version == null) return _notFound();
    final body = await _jsonBody(request);
    if (body is! Map<String, dynamic>) return _invalid('body');
    final from = body['effectiveFrom'];
    if (from is! String || anniversaryError(from) != null) {
      return _invalid('effectiveFrom');
    }
    final source = body['sourceUrl'];
    if (source is! String ||
        source.trim().isEmpty ||
        enrollmentUrlError(source) != null) {
      return _invalid('sourceUrl');
    }
    final notes = body['notes'];
    if (notes != null && notes is! String) return _invalid('notes');

    return inTransaction(db, (tx) async {
      final status = await statusOf(tx, id, version);
      if (status == null) return _notFound();
      if (status == 'published') return _conflict('published');
      await tx.execute(
        Sql.named('''
          UPDATE template_versions SET status = 'published',
            effective_from = @from::date, published_by = @by,
            published_at = now(), source_url = @source, notes = @notes
          WHERE template_id = @t AND version = @v
        '''),
        parameters: {
          't': id,
          'v': version,
          'from': from,
          'by': caller.userId,
          'source': source,
          'notes': notes,
        },
      );
      await tx.execute(
        Sql.named('''
          INSERT INTO catalog_events (kind, template_id, version, published_by)
          VALUES ('version published', @t, @v, @by)
        '''),
        parameters: {'t': id, 'v': version, 'by': caller.userId},
      );
      return jsonResponse((await adminVersionJson(tx, id, version))!);
    });
  }

  const draft = '/v1/admin/catalog/<templateId>/drafts';
  routes
    ..add('POST', '/v1/admin/catalog', admin(createTemplate))
    ..add('POST', draft, admin(createDraft))
    ..add('PUT', '$draft/<version>', admin(editDraft))
    ..add('POST', '$draft/<version>/publish', admin(publish));
}
