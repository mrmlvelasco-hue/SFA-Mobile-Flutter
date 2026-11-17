import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the bearer token and the device identity between app launches,
/// the Flutter equivalent of the RN app's AsyncStorage usage for the auth
/// token / device id.
class TokenStorage {
  TokenStorage._();
  static final TokenStorage instance = TokenStorage._();

  final _storage = const FlutterSecureStorage();

  static const _tokenKey = 'sfa_access_token';
  static const _deviceIdKey = 'sfa_device_id';

  Future<String?> readToken() => _storage.read(key: _tokenKey);

  Future<void> saveToken(String token) => _storage.write(key: _tokenKey, value: token);

  Future<void> clearToken() => _storage.delete(key: _tokenKey);

  Future<String?> readDeviceId() => _storage.read(key: _deviceIdKey);

  Future<void> saveDeviceId(String id) => _storage.write(key: _deviceIdKey, value: id);
}
