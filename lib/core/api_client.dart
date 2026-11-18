import 'package:dio/dio.dart';

import 'api_config.dart';
import 'token_storage.dart';

/// A thin wrapper so every call goes through one Dio instance with the
/// bearer token attached automatically, mirroring the RN app's axios/RTK
/// Query `prepareHeaders` (see src/services/authApi.js).
class ApiClient {
  ApiClient._internal() {
    _dio = Dio(BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      headers: {'Accept': 'application/json'},
      // The backend always returns a JSON body (even on 401/422/500) that callers need to
      // read -- so accept every HTTP response as "valid" and let ApiEnvelope.fromResponse
      // parse it. Only genuine transport failures (connection refused, timeout, DNS) should
      // still throw DioException. (Previously this was `status < 500`, which meant a 500
      // response's real error message -- the whole reason the backend returns a body on
      // failure -- was discarded in favor of Dio's generic "status code of 500" boilerplate.)
      validateStatus: (status) => true,
    ));
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await TokenStorage.instance.readToken();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
    ));
  }

  static final ApiClient instance = ApiClient._internal();
  late final Dio _dio;

  Dio get dio => _dio;
}

/// The {code, status, message, data, error_parameters?} envelope every
/// sfa-api mobile (/api/v1) response uses -- see app/responses.py.
class ApiEnvelope {
  final int code;
  final String? status;
  final String message;
  final dynamic data;
  final Map<String, dynamic>? errorParameters;

  ApiEnvelope({required this.code, this.status, required this.message, this.data, this.errorParameters});

  bool get isSuccess => code >= 200 && code < 300;

  factory ApiEnvelope.fromResponse(Response response) {
    final body = response.data;
    if (body is Map<String, dynamic>) {
      return ApiEnvelope(
        code: (body['code'] as num?)?.toInt() ?? response.statusCode ?? 0,
        status: body['status'] as String?,
        message: (body['message'] ?? '').toString(),
        data: body['data'],
        errorParameters: body['error_parameters'] as Map<String, dynamic>?,
      );
    }
    return ApiEnvelope(code: response.statusCode ?? 0, message: 'Unexpected response', data: body);
  }

  /// error_parameters.error_code, when present (used by login to distinguish
  /// "wrong password" from "another device active" etc -- see
  /// ApiResponser::authError in the PHP original).
  int? get authErrorCode {
    final c = errorParameters?['error_code'];
    if (c is int) return c;
    return null;
  }
}
