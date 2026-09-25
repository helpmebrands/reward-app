/// Where the app finds the api. The release pipeline builds each
/// environment with its own `--dart-define=API_BASE_URL=…`; a local run
/// without one talks to staging.
abstract final class ApiConfig {
  /// The staging api, the default for a build without the define.
  static const stagingUrl = 'https://reward-api-bduraqeztq-uc.a.run.app';

  /// The api's base URL, from `API_BASE_URL` at build time.
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: stagingUrl,
  );
}
