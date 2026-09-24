import 'package:flutter_test/flutter_test.dart';
import 'package:reward/data/api_config.dart';

/// The api's base URL comes from a build-time define per environment, with
/// the staging api as the default for a local run. The define case only
/// means something when the suite is run with it, as the verify gate does:
/// `flutter test test/api_config_test.dart
/// --dart-define=API_BASE_URL=https://example.test`.
void main() {
  const defined = bool.hasEnvironment('API_BASE_URL');

  // @lat: [[mobile-tests#Api config#The define sets the api base URL]]
  test(
    'with --dart-define=API_BASE_URL the base URL is the define',
    () => expect(ApiConfig.baseUrl, 'https://example.test'),
    skip: defined
        ? false
        : 'run with --dart-define=API_BASE_URL=https://example.test',
  );

  // @lat: [[mobile-tests#Api config#Without the define the app talks to staging]]
  test(
    'without the define the base URL is the staging api',
    () => expect(ApiConfig.baseUrl, ApiConfig.stagingUrl),
    skip: defined ? 'API_BASE_URL is defined' : false,
  );
}
