/// Backend base URL. Override at build/run time with:
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
/// (10.0.2.2 is the Android emulator's alias for the host machine's
/// localhost; use your machine's LAN IP for a physical device, or
/// http://localhost:8000 for iOS simulator / web / desktop.)
class ApiConfig {
  ApiConfig._();

  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );

  /// Must match the backend's `application_version` setting exactly, or
  /// login is rejected with "There is an updated version...". Override with
  /// --dart-define=APP_VERSION=x.y.z to match your seeded/admin value.
  static const String appVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '1.0.0',
  );
}
