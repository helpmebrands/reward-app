import 'dart:io';

import 'package:api/catalog_seed.dart';
import 'package:domain/domain.dart';

/// Prints the catalogue seed migration:
/// `dart run tool/catalog_seed.dart > migrations/0006_catalog_seed.sql`.
void main() => stdout.write(renderCatalogSeed(cardTemplates));
