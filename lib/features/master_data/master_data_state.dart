import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';
import '../../core/device_info_service.dart';
import '../../core/formatting.dart';
import '../../core/offline_store.dart';
import '../../core/safe_notifier.dart';
import '../auth/auth_state.dart';
import 'master_data_repository.dart';

enum MasterDataStatus { checking, downloading, ready, failed }

/// The after-login "Downloading data" step -- ported from the RN app's
/// src/components/DownloadData.js -- and the downloaded data itself, which every screen reads so
/// the app works offline for the rest of the day.
///
/// Same 16 calls, same order, same payloads as the RN app. Differences, on purpose:
/// - the whole download fails on the first failing call, instead of some failures being ignored
///   and the rest saved (the RN app only checked `status` on 9 of the 16 responses);
/// - the cached pricing belongs to the user who downloaded it -- the RN app reused one device-wide
///   pricing cache for whoever logged in next.
class MasterDataState extends ChangeNotifier with SafeNotifier {
  MasterDataState({
    required AuthState auth,
    MasterDataRepository? repository,
    OfflineStore? store,
    DateTime Function()? clock,
  })  : _auth = auth,
        _repository = repository ?? MasterDataRepository(),
        _store = store ?? FileOfflineStore.instance,
        _clock = clock ?? DateTime.now;

  final AuthState _auth;
  final MasterDataRepository _repository;
  final OfflineStore _store;
  final DateTime Function() _clock;

  static const totalSteps = 16;

  MasterDataStatus status = MasterDataStatus.checking;

  /// Name of the call in progress, as the RN progress modal shows it ('Materials', 'Pricing and
  /// Discount', ...).
  String step = '';

  /// 0.0 - 1.0
  double progress = 0;
  String? errorMessage;

  /// The combined download -- the same keys as the RN app's `offlineData.data`: constants,
  /// route_calls, collections, outlets, receivables, rebates, pickUpDiscount, partners,
  /// subsidiarysgl, subsidiarydoc, orderList, order_summary, feedback_reasons,
  /// non_sales_activities, inventory, materials, pricing, inventory_reason, sales_returns,
  /// promo_discount, empties_pullout_tab, order_details, customer_sales_vol, customer_promo.
  Map<String, dynamic> data = const {};
  DateTime? downloadedAt;

  bool get isReady => status == MasterDataStatus.ready;

  /// Uses today's saved download if there is one for this user, otherwise downloads.
  Future<void> start() async {
    final user = _auth.user;
    if (user == null) return;
    status = MasterDataStatus.checking;
    notifyListeners();

    final saved = await _store.read(OfflineDocs.downloadData);
    if (saved != null &&
        saved['employee_id'] == user.employeeId &&
        saved['day'] == dayKey(_clock()) &&
        saved['data'] is Map<String, dynamic>) {
      final restored = Map<String, dynamic>.from(saved['data'] as Map<String, dynamic>);
      restored['pricing'] = (await _ownPricing(user.employeeId))?['data'] ?? const [];
      data = restored;
      downloadedAt = DateTime.tryParse((saved['downloaded_at'] ?? '').toString());
      status = MasterDataStatus.ready;
      notifyListeners();
      return;
    }
    await download();
  }

  Future<void> download() async {
    final user = _auth.user;
    if (user == null) return;
    status = MasterDataStatus.downloading;
    errorMessage = null;
    step = 'Fetching Data';
    progress = 0;
    notifyListeners();

    try {
      final combined = await _runDownload(user.employeeId, user.deviceId);
      if (isDisposed) return; // logged out mid-download: don't save it back
      final now = _clock();
      await _store.write(OfflineDocs.downloadData, {
        'employee_id': user.employeeId,
        'day': dayKey(now),
        'downloaded_at': now.toIso8601String(),
        'data': Map<String, dynamic>.from(combined)..remove('pricing'), // pricing has its own doc
      });
      data = combined;
      downloadedAt = now;
      progress = 1;
      status = MasterDataStatus.ready;
      notifyListeners();
    } on _StepFailed catch (failure) {
      if (failure.result.isUnauthenticated) {
        await _auth.signOutLocally(message: 'Your session has expired. Please log in again.');
        return;
      }
      final message = failure.result.message.isNotEmpty ? failure.result.message : 'Download failed.';
      errorMessage = '${failure.step}: $message';
      status = MasterDataStatus.failed;
      notifyListeners();
    } catch (e) {
      // A response in an unexpected shape, or the phone's storage failing -- show it rather than
      // leaving the screen on "downloading" forever.
      errorMessage = '$step: $e';
      status = MasterDataStatus.failed;
      notifyListeners();
    }
  }

  var _done = 0;

  Future<ApiEnvelope> _call(String name, String path, Map<String, dynamic> body) async {
    step = name;
    notifyListeners();
    final result = await _repository.post(path, body);
    if (!result.isSuccess || result.status == 'Error') throw _StepFailed(name, result);
    _advance();
    return result;
  }

  void _advance() {
    _done++;
    progress = _done / totalSteps;
    notifyListeners();
  }

  Future<Map<String, dynamic>> _runDownload(String employeeId, String savedDeviceId) async {
    _done = 0;
    final salesOrg = _auth.salesOrg;
    final deviceInfo = DeviceInfoService.instance;
    // user.device_id from the login response, as the RN app sends; the local id if it's missing.
    final deviceId = savedDeviceId.isNotEmpty ? savedDeviceId : await deviceInfo.deviceId();
    final device = <String, dynamic>{
      'employee_id': employeeId,
      'device_id': deviceId,
      'lat': deviceInfo.latStub(),
      'lng': deviceInfo.lngStub(),
      'ip': deviceInfo.ipStub(),
      'sales_org': salesOrg,
    };

    final summary = _map((await _call('Fetching Data', '/api/v1/download-datav2', device)).data);
    final constants = _map(summary['constants']);
    final routeCalls = summary['route_calls'] is Map
        ? Map<String, dynamic>.from(summary['route_calls'] as Map)
        : <String, dynamic>{'count': 0, 'list': <dynamic>[]};
    final calls = _list(routeCalls['list']).whereType<Map>().toList();
    // Not de-duplicated, as in the RN app: a customer with two calls today is listed twice.
    final customers = calls.map((c) => c['customer_number']).toList();
    final customerOrg = calls.map((c) => {'customer_number': c['customer_number'], 'sales_org': c['sales_org']}).toList();
    final offices = _list(constants['sales_offices']).whereType<Map>().map((o) => o['sap_officeId']).toList();
    final org = _list(summary['org']);

    Future<dynamic> post(String name, String path, Map<String, dynamic> body) async =>
        (await _call(name, '/api/v1/download-datav2/$path', body)).data;

    final skuList = await post('Materials', 'sku-list', {'sales_org': salesOrg});
    final promoDiscount = await post('Promo discount', 'promo-discount', {...device, 'customer_list': customers});
    final emptiesTab = await post('Empties Pullout', 'empties-pullout-tab', {...device, 'customer_list': customers});
    final orderDetails = await post('Order Details', 'order-details', {'customer_list': customers});
    final salesReturn = await post('Sales Return', 'sales-return', {'customer_list': customers, 'org': salesOrg});
    final materials = await post('Material Inventory', 'material-inventory', {'sales_area': offices, 'org': salesOrg});
    final collections = _map(await post('AR Collections', 'collections', {'customer_list': customers}));
    final outlets = _map(await post('Customer Info', 'outlets', {'customer_org': customerOrg}));
    final receivables = _map(await post('Receivables', 'receivables', {'customer_list': customers}));
    final rebates = _map(await post('Rebates', 'rebates', {'customer_list': customers}));
    final pickUpDiscount =
        await post('Pickup Discount', 'customer-pickup-discount', {'employee_id': employeeId, 'customer_list': customers});
    final partners = _map(await post('Customer Partners', 'partners', {'customer_list': customers}));
    final pricing = await _pricing(employeeId, constants, routeCalls, customers);
    final salesVol = await post('Sales Volume', 'customer-sales-vol', {'route_calls': routeCalls, 'customer_list': customers});
    final customerPromo = await post('Customer Promo', 'customer-promo',
        {'employee_id': employeeId, 'org': org.isNotEmpty ? org.first : null, 'customer_list': customers});

    return {
      'constants': constants,
      'route_calls': routeCalls,
      'collections': collections['collections'] ?? const [],
      'outlets': outlets['outlets'] ?? const [],
      'promotions': const [],
      'receivables': receivables['receivables'] ?? const [],
      'rebates': rebates['rebates'] ?? const [],
      'pickUpDiscount': pickUpDiscount ?? const [],
      'partners': partners['partners'],
      'subsidiarysgl': summary['subsidiarysgl'],
      'subsidiarydoc': summary['subsidiarydoc'],
      'orderList': summary['orderList'],
      'order_summary': summary['order_summary'],
      'feedback_reasons': summary['feedback_reasons'],
      'non_sales_activities': summary['non_sales_activities'],
      'inventory': skuList ?? const [],
      'materials': materials ?? const [],
      'pricing': pricing,
      'inventory_reason': summary['inventory_reason'],
      'sales_returns': salesReturn,
      'promo_discount': promoDiscount,
      'empties_pullout_tab': emptiesTab ?? const [],
      'order_details': orderDetails,
      'customer_sales_vol': {
        'original': {'data': salesVol},
      },
      'customer_promo': customerPromo,
    };
  }

  /// The RN rule: reuse the saved pricing unless there is none, or the server flags a price
  /// update (constants.price_update) and the saved pricing isn't from today.
  Future<dynamic> _pricing(String employeeId, Map<String, dynamic> constants, Map<String, dynamic> routeCalls,
      List<dynamic> customers) async {
    final today = dayKey(_clock());
    final local = await _ownPricing(employeeId);
    final localList = local == null ? const [] : _list(local['data']);
    final priceUpdate = _truthy(constants['price_update']);
    if (localList.isNotEmpty && !(priceUpdate && local!['day'] != today)) {
      step = 'Pricing and Discount (saved)';
      _advance();
      return localList;
    }
    final result = await _call('Pricing and Discount', '/api/v1/download-datav2/all-pricing',
        {'route_calls': routeCalls, 'customer_list': customers});
    final downloaded = result.data ?? const [];
    await _store.write(OfflineDocs.pricing, {'employee_id': employeeId, 'day': today, 'data': downloaded});
    return downloaded;
  }

  Future<Map<String, dynamic>?> _ownPricing(String employeeId) async {
    final doc = await _store.read(OfflineDocs.pricing);
    return doc != null && doc['employee_id'] == employeeId ? doc : null;
  }

  static Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  static List<dynamic> _list(dynamic value) => value is List ? value : const [];

  /// JavaScript truthiness (the RN code tests `if (constants.price_update)`): true, non-zero
  /// numbers and non-empty strings -- including '0' and 'false', which are truthy in JS.
  static bool _truthy(dynamic value) =>
      value == true || (value is num && value != 0) || (value is String && value.isNotEmpty);
}

class _StepFailed implements Exception {
  _StepFailed(this.step, this.result);
  final String step;
  final ApiEnvelope result;
}
