import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';
import '../../core/formatting.dart';
import '../../core/offline_store.dart';
import '../../core/safe_notifier.dart';
import '../auth/auth_state.dart';

enum DashboardStatus { loading, loaded, error }

/// One gauge: MTD actual vs target.
class DashboardGauge {
  const DashboardGauge({required this.label, required this.percentage, required this.actual, required this.target, this.targetLabel = 'Target'});
  final String label;

  /// calculatePercentage's text, e.g. '84.3' or '0.0'.
  final String percentage;
  final String actual;
  final String target;
  final String targetLabel;
}

/// The dashboard figures (GET /api/v1/actual-coob-dashboard) -- the RN app's UserScreen.js.
///
/// The RN app only shows them when online. Here the last figures are also saved, so the
/// dashboard still shows something offline (marked with when they were fetched).
class DashboardState extends ChangeNotifier with SafeNotifier {
  DashboardState({required AuthState auth, ApiClient? client, OfflineStore? store, DateTime Function()? clock})
      : _auth = auth,
        _client = client ?? ApiClient.instance,
        _store = store ?? FileOfflineStore.instance,
        _clock = clock ?? DateTime.now;

  final AuthState _auth;
  final ApiClient _client;
  final OfflineStore _store;
  final DateTime Function() _clock;

  DashboardStatus status = DashboardStatus.loading;
  String? errorMessage;
  Map<String, dynamic> figures = const {};

  /// Set when [figures] come from the saved copy because the server couldn't be reached.
  DateTime? offlineSince;

  /// "As of" is yesterday: the figures are month-to-date up to the previous day.
  DateTime get asOf => _clock().subtract(const Duration(days: 1));

  Future<void> load() async {
    status = DashboardStatus.loading;
    errorMessage = null;
    notifyListeners();

    final salesOrg = _auth.salesOrg;
    final routes = _auth.userRoutes;
    final result = await fetch(
      _client,
      // `sales_org_download_data.length > 0 && sales_org_download_data[0]`: false when there is none.
      salesOrg: salesOrg.isNotEmpty ? salesOrg.first : 'false',
      salesDistrict: jsNumberText(routes.isNotEmpty ? routes.first : null),
    );
    final employeeId = _auth.user?.employeeId;

    if (result.isUnauthenticated) {
      await _auth.signOutLocally(message: 'Your session has expired. Please log in again.');
      return;
    }
    final rows = result.data;
    if (result.isSuccess && rows is List) {
      figures = rows.isNotEmpty && rows.first is Map ? Map<String, dynamic>.from(rows.first as Map) : <String, dynamic>{};
      offlineSince = null;
      status = DashboardStatus.loaded;
      notifyListeners();
      await _store.write(OfflineDocs.dashboard,
          {'employee_id': employeeId, 'saved_at': _clock().toIso8601String(), 'data': figures});
      return;
    }

    final saved = await _store.read(OfflineDocs.dashboard);
    if (saved != null && saved['employee_id'] == employeeId && saved['data'] is Map) {
      figures = Map<String, dynamic>.from(saved['data'] as Map);
      offlineSince = DateTime.tryParse((saved['saved_at'] ?? '').toString());
      status = DashboardStatus.loaded;
    } else {
      errorMessage = result.message.isNotEmpty ? result.message : 'Could not load the dashboard.';
      status = DashboardStatus.error;
    }
    notifyListeners();
  }

  /// Overridable in tests.
  @protected
  Future<ApiEnvelope> fetch(ApiClient client, {required String salesOrg, required String salesDistrict}) =>
      getEnvelope(client, '/api/v1/actual-coob-dashboard', query: {'sales_org': salesOrg, 'sales_district': salesDistrict});

  /// The five gauges, in the RN screen's order, with its formatting: revenue with two decimals,
  /// volumes rounded with thousands separators. Volume percentages use parseInt'd values, as in
  /// the RN code.
  List<DashboardGauge> get gauges => [
        _gauge('Revenue NSR', 'Actual_NSR', 'COOB_NSR', decimals: true),
        _gauge('Volume Raw', 'Actual_Raw', 'COOB_Raw'),
        _gauge('Volume 8oE', 'Actual_8oe', 'COOB_8oe'),
        _gauge('Volume Physical', 'Actual_Phy', 'COOB_Phy'),
        _gauge('Revenue GSR', 'Actual_GSR', 'COOB_GSR', decimals: true, targetLabel: 'GSR Target'),
      ];

  DashboardGauge _gauge(String label, String actualKey, String targetKey, {bool decimals = false, String targetLabel = 'Target'}) {
    final actual = asNum(figures[actualKey]);
    final target = asNum(figures[targetKey]);
    // `actual && target ? calculatePercentage(...) : 0.0` -- 0 or missing on either side gives 0.
    final pct = (actual == null || actual == 0 || target == null || target == 0)
        ? '0.0'
        : decimals
            ? calculatePercentage(actual, target)
            : calculatePercentage(actual.truncate(), target.truncate());
    String show(num? value) => value == null ? '0' : (decimals ? numberWithDecimals(value) : roundedWithCommas(value));
    return DashboardGauge(label: label, percentage: pct, actual: show(actual), target: show(target), targetLabel: targetLabel);
  }
}
