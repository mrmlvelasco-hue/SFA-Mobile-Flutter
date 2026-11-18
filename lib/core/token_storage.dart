import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the bearer token, the signed-in session (the login response's user, sales orgs and
/// routes), and the device identity between app launches -- the Flutter equivalent of the RN app's
/// AsyncStorage usage.
///
/// Not a private-constructor singleton on purpose: tests subclass it with an in-memory version,
/// because flutter_secure_storage is a native plugin that isn't available under `flutter test`.
class TokenStorage {
  TokenStorage();
  static final TokenStorage instance = TokenStorage();

  final _storage = const FlutterSecureStorage();

  static const _tokenKey = 'sfa_access_token';
  static const _sessionKey = 'sfa_session';
  static const _deviceIdKey = 'sfa_device_id';

  Future<String?> readToken() => _storage.read(key: _tokenKey);

  Future<void> saveToken(String token) => _storage.write(key: _tokenKey, value: token);

  Future<void> clearToken() => _storage.delete(key: _tokenKey);

  Future<String?> readSession() => _storage.read(key: _sessionKey);

  Future<void> saveSession(String json) => _storage.write(key: _sessionKey, value: json);

  Future<void> clearSession() => _storage.delete(key: _sessionKey);

  Future<String?> readDeviceId() => _storage.read(key: _deviceIdKey);

  Future<void> saveDeviceId(String id) => _storage.write(key: _deviceIdKey, value: id);
}
