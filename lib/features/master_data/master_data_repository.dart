import '../../core/api_client.dart';

/// The download-datav2 endpoints (sfa-api: app/routers/download.py). One generic POST: the
/// sequence and the payloads live in MasterDataState, next to the RN code they mirror.
class MasterDataRepository {
  MasterDataRepository({ApiClient? client}) : _client = client ?? ApiClient.instance;
  final ApiClient _client;

  Future<ApiEnvelope> post(String path, Map<String, dynamic> body) => postEnvelope(_client, path, body);

  /// For GETs whose answer isn't the usual envelope (materials-inventory-sap returns SAP's
  /// {code, status, data} -- which getEnvelope keeps whole in `data`).
  Future<ApiEnvelope> get(String path, Map<String, dynamic> query) => getEnvelope(_client, path, query: query);
}
