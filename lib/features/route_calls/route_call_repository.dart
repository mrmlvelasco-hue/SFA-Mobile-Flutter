import '../../core/api_client.dart';
import '../../core/device_info_service.dart';

/// The download-datav2 calls the Route Call Schedule needs (sfa-api: app/routers/download.py).
/// The RN app makes these, plus ~14 more for pricing, promos, inventory etc., in one big
/// "Downloading data" step right after login (src/components/DownloadData.js). Here they're
/// fetched when the screen that needs them opens; the rest arrive with their own screens.
class RouteCallRepository {
  RouteCallRepository({ApiClient? client}) : _client = client ?? ApiClient.instance;
  final ApiClient _client;

  /// POST /api/v1/download-datav2 -- the summary: today's route calls plus constants, feedback
  /// reasons, non-sales activities, order list/summary. Same body the RN app sends.
  Future<ApiEnvelope> downloadData({required String employeeId, required List<String> salesOrg}) async {
    final device = DeviceInfoService.instance;
    return postEnvelope(_client, '/api/v1/download-datav2', {
      'employee_id': employeeId,
      'device_id': await device.deviceId(),
      'lat': device.latStub(),
      'lng': device.lngStub(),
      'ip': device.ipStub(),
      'sales_org': salesOrg,
    });
  }

  /// POST /api/v1/download-datav2/order-details -- every order on record for these customers,
  /// used to mark today's calls as done.
  Future<ApiEnvelope> orderDetails(List<String> customerNumbers) {
    return postEnvelope(_client, '/api/v1/download-datav2/order-details', {'customer_list': customerNumbers});
  }
}
