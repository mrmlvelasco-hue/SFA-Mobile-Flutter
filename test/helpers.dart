import 'package:sfa_mobile/core/api_client.dart';
import 'package:sfa_mobile/core/formatting.dart';
import 'package:sfa_mobile/core/offline_store.dart';
import 'package:sfa_mobile/core/token_storage.dart';
import 'package:sfa_mobile/features/auth/auth_repository.dart';
import 'package:sfa_mobile/features/auth/auth_state.dart';
import 'package:sfa_mobile/features/auth/sfa_user.dart';
import 'package:sfa_mobile/features/master_data/master_data_repository.dart';

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

/// An AuthState that is already signed in as jdelacruz (E1) today, without touching storage or
/// the network.
AuthState signedInAuth({InMemoryTokenStorage? storage, InMemoryOfflineStore? offlineStore, DateTime Function()? clock}) {
  final auth = AuthState(
    repository: FakeAuthRepository(),
    storage: storage ?? InMemoryTokenStorage(),
    offlineStore: offlineStore ?? InMemoryOfflineStore(),
    clock: clock,
  );
  auth.user = SfaUser(id: 1, employeeId: 'E1', username: 'jdelacruz', fullName: 'Dela Cruz, Juan S', deviceId: 'phone-1');
  auth.salesOrg = const ['1000'];
  auth.userRoutes = const ['R1'];
  auth.loginDay = dayKey((clock ?? DateTime.now)());
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
      'sales_org': '1000',
    };

/// The same shape as the demo data `python manage.py seed` creates in sfa-api.
List<Map<String, dynamic>> demoRouteCalls() => [
      routeCallJson('DEMO0003', 'Kuya Ben Carinderia', '000003'),
      routeCallJson('DEMO0001', 'Aling Nena Sari-Sari Store', '000001'),
      routeCallJson('DEMO0002', 'JM Mini Mart', '000002'),
      routeCallJson('DEMO0004', 'Ate Lorna Grocery', '000004'),
      routeCallJson('DEMO0005', 'Tindahan ni Mang Pepe', '000000'),
    ];

/// A downloaded-master-data map (MasterDataState.data) holding [calls] and [orders].
Map<String, dynamic> downloadDataWith({List<Map<String, dynamic>>? calls, List<Map<String, dynamic>> orders = const []}) {
  final list = calls ?? demoRouteCalls();
  return {
    'route_calls': {'count': list.length, 'list': list},
    'order_details': orders,
  };
}

/// Answers every download-datav2 call like the backend does for the seeded demo data, and
/// records what was asked, in order. Override a call's answer with [responses] (keyed by the last
/// path segment, e.g. 'sku-list').
class FakeMasterDataRepository extends MasterDataRepository {
  FakeMasterDataRepository({Map<String, ApiEnvelope>? responses, this.priceUpdate = false}) : responses = responses ?? {};

  final Map<String, ApiEnvelope> responses;
  final bool priceUpdate;
  final List<String> paths = [];
  final Map<String, Map<String, dynamic>> bodies = {};

  @override
  Future<ApiEnvelope> post(String path, Map<String, dynamic> body) async {
    final name = path.split('/').last;
    paths.add(name);
    bodies[name] = body;
    final override = responses[name];
    if (override != null) return override;
    return ApiEnvelope(code: 200, status: 'Success', message: 'Success', data: _defaultData(name));
  }

  dynamic _defaultData(String name) {
    switch (name) {
      case 'download-datav2':
        return {
          'constants': {
            'app_version': '1.0.0',
            'price_update': priceUpdate,
            'sales_offices': [
              {'sap_officeId': '9101'}
            ],
          },
          'route_calls': {'count': 5, 'list': demoRouteCalls()},
          'org': ['1000'],
          'feedback_reasons': [
            {'id': 1, 'name': 'Store closed'}
          ],
          'non_sales_activities': [],
          'inventory_reason': [],
          'subsidiarysgl': [],
          'subsidiarydoc': [],
          'orderList': [],
          'order_summary': [],
        };
      case 'collections':
        return {'collections': []};
      case 'outlets':
        return {'outlets': []};
      case 'receivables':
        return {'receivables': []};
      case 'rebates':
        return {'rebates': []};
      case 'partners':
        return {'partners': []};
      case 'all-pricing':
        return [
          {'customer_number': 'DEMO0001', 'material_code': 'M1', 'price': 100}
        ];
      case 'order-details':
        return [
          {'customer_number': 'DEMO0002', 'control_number': 'CN-DEMO0002', 'sequence_number': '000002', 'call_date': '2026-11-18 00:00:00.000'}
        ];
      default:
        return [];
    }
  }
}
