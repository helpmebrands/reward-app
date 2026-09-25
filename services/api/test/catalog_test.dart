import 'dart:io';

import 'package:api/catalog_seed.dart';
import 'package:domain/domain.dart';
import 'package:test/test.dart';

/// The committed seed migration is what the generator makes of today's
/// `catalog.dart`, so the two cannot drift.
void main() {
  // @lat: [[api-tests#Catalogue#The seed migration is generated from catalog.dart]]
  test('migrations/0006_catalog_seed.sql is the rendered catalogue', () {
    final committed = File(
      'migrations/0006_catalog_seed.sql',
    ).readAsStringSync();
    expect(
      committed,
      renderCatalogSeed(cardTemplates),
      reason:
          'regenerate with: dart run tool/catalog_seed.dart > '
          'migrations/0006_catalog_seed.sql',
    );
  });

  test('the seed leaves out the blank template and escapes quotes', () {
    final sql = renderCatalogSeed(cardTemplates);
    expect(sql, isNot(contains("'blank'")));
    // A name with an apostrophe survives as SQL.
    final quoted = renderCatalogSeed([
      const CardTemplate(
        id: 't',
        issuer: "Macy's",
        product: 'Card',
        network: CardNetwork.visa,
        kind: CardKind.personal,
        annualFeeCents: 0,
        benefits: [],
      ),
    ]);
    expect(quoted, contains("'Macy''s'"));
  });
}
