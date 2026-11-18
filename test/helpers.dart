import 'package:sfa_mobile/core/api_client.dart';
import 'package:sfa_mobile/core/token_storage.dart';
import 'package:sfa_mobile/features/auth/auth_repository.dart';
import 'package:sfa_mobile/features/auth/auth_state.dart';
import 'package:sfa_mobile/features/auth/sfa_user.dart';
import 'package:sfa_mobile/features/route_calls/route_call_repository.dart';

/// flutter_secure_storage is a native plugin -- not available under `flutter test`.
class InMemoryTokenStorage extends TokenStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> readToken() async => values['token'];
  @override
  Future<void> saveToken(String token) async => values['token'] = token;
  @override
  Future<void> clearToken() async => values.remove('token');
  @override
  Future<String?> readSession() async => values['session'];
  @override
  Future<void> saveSession(String json) async => values['session'] = json;
  @override
  Future<void> clearSession() async => values.remove('session');
  @override
  Future<String?> readDeviceId() async => values['device'];
  @override
  Future<void> saveDeviceId(String id) async => values['device'] = id;
}

class FakeAuthRepository extends AuthRepository {
  FakeAuthRepository([ApiEnvelope? loginResponse])
      : loginResponse = loginResponse ?? ApiEnvelope(code: 200, message: 'Successfully logged in!');
  ApiEnvelope loginResponse;
  int logoutCalls = 0;

  @override
  Future<ApiEnvelope> login({required String username, required String password}) async => loginResponse;

  @override
  Future<ApiEnvelope> logout({required String employeeId}) async {
    logoutCalls++;
    return ApiEnvelope(code: 200, message: 'Success');
  }
}

/// An AuthState that is already signed in as jdelacruz (E1), without touching storage or network.
AuthState signedInAuth({InMemoryTokenStorage? storage}) {
  final auth = AuthState(repository: FakeAuthRepository(), storage: storage ?? InMemoryTokenStorage());
  auth.user = SfaUser(id: 1, employeeId: 'E1', username: 'jdelacruz', fullName: 'Dela Cruz, Juan S');
  auth.salesOrg = const ['1000'];
  auth.status = AuthStatus.signedIn;
  return auth;
}

Map<String, dynamic> routeCallJson(String customer, String outlet, String? itemNumber,
        {String control = 'CN', String date = '2026-11-18 00:00:00.000'}) =>
    {
      'customer_number': customer,
      'outlet_name': outlet,
      'owner_name': 'Owner of $outlet',
      'address': 'Address of $outlet',
      'control_number': '$control-$customer',
      'item_number': itemNumber,
      'call_date': date,
    };

/// The same shape as the demo data `python manage.py seed` creates in sfa-api.
List<Map<String, dynamic>> demoRouteCalls() => [
      routeCallJson('DEMO0003', 'Kuya Ben Carinderia', '000003'),
      routeCallJson('DEMO0001', 'Aling Nena Sari-Sari Store', '000001'),
      routeCallJson('DEMO0002', 'JM Mini Mart', '000002'),
      routeCallJson('DEMO0004', 'Ate Lorna Grocery', '000004'),
      routeCallJson('DEMO0005', 'Tindahan ni Mang Pepe', '000000'),
    ];

class FakeRouteCallRepository extends RouteCallRepository {
  FakeRouteCallRepository({List<Map<String, dynamic>>? calls, this.orders = const [], this.summaryResponse})
      : calls = calls ?? demoRouteCalls();

  final List<Map<String, dynamic>> calls;
  final List<Map<String, dynamic>> orders;
  final ApiEnvelope? summaryResponse;
  int downloadCalls = 0;
  List<String>? lastOrderCustomers;

  @override
  Future<ApiEnvelope> downloadData({required String employeeId, required List<String> salesOrg}) async {
    downloadCalls++;
    return summaryResponse ??
        ApiEnvelope(code: 200, message: 'Success', data: {
          'route_calls': {'count': calls.length, 'list': calls},
          'constants': {'app_version': '1.0.0'},
        });
  }

  @override
  Future<ApiEnvelope> orderDetails(List<String> customerNumbers) async {
    lastOrderCustomers = customerNumbers;
    return ApiEnvelope(code: 200, message: 'Success', data: orders);
  }
}
