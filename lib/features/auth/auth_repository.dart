import '../../core/api_client.dart';
import '../../core/device_info_service.dart';

/// Talks to the sfa-api mobile auth endpoints
/// (app/routers/auth.py: POST /login, POST /logout).
class AuthRepository {
  AuthRepository({ApiClient? client}) : _client = client ?? ApiClient.instance;
  final ApiClient _client;

  Future<ApiEnvelope> login({required String username, required String password}) async {
    final device = DeviceInfoService.instance;
    return postEnvelope(_client, '/api/v1/login', {
      'username': username,
      'password': password,
      'deviceId': await device.deviceId(),
      'device_name': device.deviceName(),
      'lat': device.latStub(),
      'lng': device.lngStub(),
      'ip': device.ipStub(),
      'app_version': device.appVersion(),
    });
  }

  Future<ApiEnvelope> logout({required String employeeId}) {
    return postEnvelope(_client, '/api/v1/logout', {'employee_id': employeeId});
  }
}
