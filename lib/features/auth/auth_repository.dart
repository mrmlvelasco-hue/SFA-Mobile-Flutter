import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../core/device_info_service.dart';

/// Talks to the sfa-api mobile auth endpoints
/// (app/routers/auth.py: POST /login, POST /logout).
class AuthRepository {
  AuthRepository({ApiClient? client}) : _client = client ?? ApiClient.instance;
  final ApiClient _client;

  Future<ApiEnvelope> login({required String username, required String password}) async {
    final device = DeviceInfoService.instance;
    final body = {
      'username': username,
      'password': password,
      'deviceId': await device.deviceId(),
      'device_name': device.deviceName(),
      'lat': device.latStub(),
      'lng': device.lngStub(),
      'ip': device.ipStub(),
      'app_version': device.appVersion(),
    };
    try {
      final response = await _client.dio.post('/api/v1/login', data: body);
      return ApiEnvelope.fromResponse(response);
    } on DioException catch (e) {
      return _networkError(e);
    }
  }

  Future<ApiEnvelope> logout({required String employeeId}) async {
    try {
      final response = await _client.dio.post('/api/v1/logout', data: {'employee_id': employeeId});
      return ApiEnvelope.fromResponse(response);
    } on DioException catch (e) {
      return _networkError(e);
    }
  }

  ApiEnvelope _networkError(DioException e) {
    // With validateStatus accepting every HTTP response, this should now only fire for
    // genuine transport failures -- but if Dio still attached a response (e.g. a body that
    // failed to parse as JSON), prefer whatever message is in it over Dio's own wording.
    final data = e.response?.data;
    if (data is Map<String, dynamic> && data['message'] != null) {
      return ApiEnvelope.fromResponse(e.response!);
    }
    return ApiEnvelope(
      code: 0,
      message: e.type == DioExceptionType.connectionError || e.type == DioExceptionType.connectionTimeout
          ? 'Could not reach the server. Check your connection and the API base URL.'
          : (e.message ?? 'Network error'),
    );
  }
}
