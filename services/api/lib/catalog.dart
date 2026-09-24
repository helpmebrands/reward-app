/// The catalogue as stored in Postgres, read into the domain's
/// `TemplateVersion`s, and the two read routes. Documented in
/// `lat.md/api/api-architecture.md#Catalogue`.
library;

import 'package:domain/domain.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'auth.dart';
import 'src/responses.dart';
import 'src/routes.dart';
import 'src/signed_in.dart';

String _date(Object? value) =>
    (value! as DateTime).toIso8601String().substring(0, 10);

/// Versions from [db], every template or just [templateId], ordered by
/// template then version. Published only, unless [status] asks for drafts.
Future<List<TemplateVersion>> loadVersions(
  Session db, {
  String? templateId,
  String status = 'published',
  int? version,
}) async {
  final filter = {'status': status, 'template': templateId, 'version': version};
  final versions = await db.execute(
    Sql.named('''
      SELECT template_id, version, effective_from, issuer, product, network,
             kind, annual_fee_cents
      FROM template_versions
      WHERE status = @status
        AND (@template::text IS NULL OR template_id = @template::text)
        AND (@version::int IS NULL OR version = @version::int)
      ORDER BY template_id, version
    '''),
    parameters: filter,
  );
  final credits = await db.execute(
    Sql.named('''
      SELECT c.template_id, c.version, c.credit_id, c.name, c.description,
             c.category, c.icon, c.merchant, c.value_cents, c.cadence,
             c.anchor, c.interval_months, c.enrollment_required,
             c.spend_threshold_cents, c.ends_on, c.redemption_steps, c.notes
      FROM template_credits c
      JOIN template_versions v USING (template_id, version)
      WHERE v.status = @status
        AND (@template::text IS NULL OR c.template_id = @template::text)
        AND (@version::int IS NULL OR c.version = @version::int)
      ORDER BY c.template_id, c.version, c.position
    '''),
    parameters: filter,
  );
  final byVersion = <String, List<BenefitTemplate>>{};
  for (final c in credits) {
    byVersion
        .putIfAbsent('${c[0]}#${c[1]}', () => [])
        .add(
          benefitTemplateFromJson({
            'id': c[2],
            'name': c[3],
            'description': c[4],
            'category': c[5],
            'icon': c[6],
            'merchant': c[7],
            'valueCents': c[8],
            'cadence': c[9],
            'anchor': c[10],
            'intervalMonths': c[11],
            'enrollmentRequired': c[12],
            'spendThresholdCents': c[13],
            'endsOn': c[14] == null ? null : _date(c[14]),
            'redemptionSteps': c[15],
            'notes': c[16],
          }),
        );
  }
  return [
    for (final v in versions)
      TemplateVersion(
        version: v[1]! as int,
        effectiveFrom: _date(v[2]),
        template: CardTemplate(
          id: v[0]! as String,
          issuer: v[3]! as String,
          product: v[4]! as String,
          network: CardNetwork.values.byName(v[5]! as String),
          kind: CardKind.values.byName(v[6]! as String),
          annualFeeCents: v[7]! as int,
          benefits: byVersion['${v[0]}#${v[1]}'] ?? const [],
        ),
      ),
  ];
}

/// Every published version, of every template or of [templateId].
Future<List<TemplateVersion>> publishedVersions(
  Session db, {
  String? templateId,
}) => loadVersions(db, templateId: templateId);

/// The date the database calls today, so "in force" means the same thing
/// to every replica.
Future<IsoDate> databaseToday(Session db) async =>
    _date((await db.execute('SELECT current_date')).single[0]);

/// Adds `GET /v1/catalog` and `GET /v1/catalog/<templateId>`.
void addCatalogRoutes(RouteTable routes, SignedIn signedIn) {
  Future<Response> catalog(Request request, Caller caller, Session db) async {
    final today = await databaseToday(db);
    final byTemplate = <String, List<TemplateVersion>>{};
    for (final v in await publishedVersions(db)) {
      byTemplate.putIfAbsent(v.templateId, () => []).add(v);
    }
    return jsonResponse([
      for (final versions in byTemplate.values)
        if (versionInForce(versions, today) case final v?)
          templateVersionToJson(v),
    ]);
  }

  Future<Response> template(Request request, Caller caller, Session db) async {
    final id = request.params['templateId']!;
    final versions = await publishedVersions(db, templateId: id);
    if (versions.isEmpty) {
      return jsonResponse({'error': 'not found'}, status: 404);
    }
    return jsonResponse({
      'id': id,
      'versions': versions.map(templateVersionToJson).toList(),
    });
  }

  routes
    ..add('GET', '/v1/catalog', signedIn(catalog))
    ..add('GET', '/v1/catalog/<templateId>', signedIn(template));
}
